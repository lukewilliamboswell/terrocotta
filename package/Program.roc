## Platform-independent Model-View-Update state and stepping.
import Layout
import LayoutTypes
import Render
import Element
import Event
import Drag
import Font exposing [Measurable]
import rrt.Mouse as RrtMouse

HostState : {
	keys : List(U8),
	keys_pressed : List(U8),
	keys_released : List(U8),
	mouse : {
		buttons : List(U8),
		buttons_pressed : List(U8),
		buttons_released : List(U8),
		left : Bool,
		middle : Bool,
		right : Bool,
		wheel : F32,
		x : F32,
		y : F32,
	},
}

EventBindings(msg) : Dict(U64, List(Event.Handler(msg)))

ScrollState : {

	## Current horizontal and vertical content displacement.
	position : LayoutTypes.Pos,

	## Horizontal and vertical velocity retained for inertial scrolling.
	momentum : { x : F32, y : F32 },

	## Whether pointer-driven scrolling is currently active.
	pointer_active : Bool,

	## Pointer position captured when the current drag began.
	pointer_origin : LayoutTypes.Pos,

	## Scroll position captured when the current drag began.
	scroll_origin : LayoutTypes.Pos,

	## Time associated with the current inertial scroll motion.
	momentum_time : F32,
}

default_scroll_state : ScrollState
default_scroll_state = {
	position: { x: 0, y: 0 },
	momentum: { x: 0, y: 0 },
	pointer_active: Bool.False,
	pointer_origin: { x: 0, y: 0 },
	scroll_origin: { x: 0, y: 0 },
	momentum_time: 0,
}

## Adapt RocRay's package-owned input values to Terrocotta's event snapshot.
build_input : { keys : List(U8), mouse : RrtMouse.State, ..input_state } -> HostState
build_input = |input| {
	{
		keys: derive(input.keys, 1),
		keys_pressed: derive(input.keys, 2),
		keys_released: derive(input.keys, 4),
		mouse: {
			buttons: derive(input.mouse.buttons, 1),
			buttons_pressed: derive(input.mouse.buttons, 2),
			buttons_released: derive(input.mouse.buttons, 4),
			left: input.mouse.left,
			middle: input.mouse.middle,
			right: input.mouse.right,
			wheel: input.mouse.wheel_y,
			x: input.mouse.x,
			y: input.mouse.y,
		},
	}
}

## Expand packed per-key/button state bytes into per-index 0/1 lists.
derive : List(U8), U8 -> List(U8)
derive = |states, mask|
	List.map(states, |byte| if U8.bitwise_and(byte, mask) != 0 1 else 0)

Program :: [].{

	State(model, msg, font) : {
		model : model,
		layout : Layout(font),
		event_bindings : EventBindings(msg),
		hovered : List(U64),
		focused : U64,
		scroll : Dict(U64, ScrollState),
		drag : Drag.DragState,
		commands : List(Render.Command(font)),
	}

	## Initialize package state. The first RocRay update builds the first layout.
	init : model, Font.Handle(font) -> State(model, msg, font)
	init = |model, font| {
		{
			model,
			layout: Layout.new(font),
			event_bindings: Dict.empty(),
			hovered: [],
			focused: 0,
			scroll: Dict.empty(),
			drag: Idle,
			commands: [],
		}
	}

	## Advance interaction and solve the layout that render will draw.
	step : {
		state : State(model, msg, font),
		input : { keys : List(U8), mouse : RrtMouse.State, ..input_state },
		viewport : { width : I32, height : I32 },
		view : model -> Element.View(msg, font),
		update : model, msg -> model,
	} -> Try(State(model, msg, font), Layout.LayoutError)
		where [font.Measurable]
	step = |{ state, input: input_snapshot, viewport, view, update }| {
		input = build_input(input_snapshot)
		screen = { w: viewport.width.to_f32(), h: viewport.height.to_f32() }

		scroll = update_scroll_containers(state.layout, state.scroll, { x: input.mouse.x, y: input.mouse.y }, input.mouse.wheel)?
		{ messages, hovered, focused, drag } = handle_events(state.layout, state.event_bindings, input, state.hovered, state.focused, state.drag)?

		var $model = state.model
		for message in messages {
			$model = update($model, message)
		}

		var $layout = state.layout.clear()
		var $event_bindings = Dict.empty()
		for element_op in view($model) {
			($layout, node) = $layout.update(
				element_op,
				|node_id| get_box_status(node_id, hovered, focused, input),
				|node_id| scroll.get(node_id).map_ok(|item| item.position).ok_or({ x: 0, y: 0 }),
			)?
			$event_bindings = match node {
				Node(node_id, Events(events)) => $event_bindings.insert(node_id, events)
				_ => $event_bindings
			}
		}

		$layout = $layout.solve(screen)?
		commands = $layout.to_commands(screen)?
		Ok({ model: $model, layout: $layout, event_bindings: $event_bindings, hovered, focused, scroll, drag, commands })
	}
}

## Return whether an overflow mode permits user scrolling.
scrolls_axis : Element.Overflow -> Bool
scrolls_axis = |mode| match mode {
	Visible => Bool.False
	Hidden => Bool.False
	Scroll => Bool.True
}

## Clamp one retained scroll axis to its valid content range.
clamp_scroll_axis : Element.Overflow, F32, F32, F32 -> F32
clamp_scroll_axis = |mode, current, content, viewport| {
	if scrolls_axis(mode) {
		minimum = 0 - F32.max(content - viewport, 0)
		F32.min(0, F32.max(minimum, current))
	} else {
		0
	}
}

## Clamp retained state and apply wheel input to the deepest hovered container.
update_scroll_containers : Layout(draw), Dict(U64, ScrollState), LayoutTypes.Pos, F32 -> Try(Dict(U64, ScrollState), Layout.LayoutError)
update_scroll_containers = |layout, scroll, pointer, wheel| {
	hovered = layout.hover_path(pointer)?
	containers = layout.scroll_containers()
	var $scroll = scroll
	for node in containers {
		{
			current = $scroll.get(node.id).ok_or(default_scroll_state)
			base_x = clamp_scroll_axis(node.overflow.x, current.position.x, node.content_dimensions.w, node.scroll_container_dimensions.w)
			base_y = clamp_scroll_axis(node.overflow.y, current.position.y, node.content_dimensions.h, node.scroll_container_dimensions.h)
			position = { x: base_x, y: base_y }
			$scroll = $scroll.insert(node.id, { ..current, position })
		}
	}
	if wheel != 0 {
		match deepest_vertical_scroll_target(containers, hovered) {
			ScrollTarget(node_id) => {
				data = layout.get_scroll_container_data(node_id)
				current = $scroll.get(node_id).ok_or(default_scroll_state)
				next_y = clamp_scroll_axis(data.overflow.y, current.position.y + wheel * 10, data.content_dimensions.h, data.scroll_container_dimensions.h)
				$scroll = $scroll.insert(node_id, { ..current, position: { ..current.position, y: next_y } })
			}
			NoScrollTarget => {}
		}
	}
	Ok($scroll)
}

ScrollCandidate : {
	id : U64,
	scroll_container_dimensions : LayoutTypes.Size,
	content_dimensions : LayoutTypes.Size,
	overflow : { x : Element.Overflow, y : Element.Overflow },
	scroll_position : LayoutTypes.Pos,
}

## Select the deepest hovered container that can scroll vertically.
deepest_vertical_scroll_target : List(ScrollCandidate), List(U64) -> [ScrollTarget(U64), NoScrollTarget]
deepest_vertical_scroll_target = |containers, hovered| {
	var $target = NoScrollTarget
	for node_id in hovered {
		if $target == NoScrollTarget {
			for data in containers {
				if data.id == node_id and scrolls_axis(data.overflow.y) {
					$target = ScrollTarget(node_id)
				}
			}
		}
	}
	$target
}

default_box_status : Element.BoxStatus
default_box_status = { hovered: Bool.False, pressed: Bool.False, focused: Bool.False, disabled: Bool.False }

get_box_status : U64, List(U64), U64, HostState -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, host| {
	hovered = prev_hovered.contains(node_index)
	{ hovered, pressed: hovered and host.mouse.left, focused: node_index == focused, disabled: Bool.False }
}

is_mouse_button_pressed : List(U8), U64 -> Bool
is_mouse_button_pressed = |states, button|
	match states.get(button) {
		Ok(state) => U8.bitwise_and(state, 1) != 0
		Err(_) => Bool.False
	}

is_key_pressed : List(U8), U64 -> Bool
is_key_pressed = |states, key|
	match states.get(key) {
		Ok(state) => U8.bitwise_and(state, 1) != 0
		Err(_) => Bool.False
	}

handle_events : Layout(draw), EventBindings(msg), HostState, List(U64), U64, Drag.DragState -> Try({ messages : List(msg), hovered : List(U64), focused : U64, drag : Drag.DragState }, Layout.LayoutError)
handle_events = |layout, event_bindings, host, prev_hovered, prev_focused, drag_state| {
	root_index = 0
	pointer = { x: host.mouse.x, y: host.mouse.y }
	hovered = layout.hover_path(pointer)?

	# OnPointerEnter/OnPointerLeave/OnHover
	var $msgs = get_pointer_enter_events(event_bindings, prev_hovered, hovered)
	$msgs = $msgs.concat(get_pointer_leave_events(event_bindings, prev_hovered, hovered))
	$msgs = $msgs.concat(get_hover_events(event_bindings, hovered))
	$msgs = $msgs.concat(get_pointer_events(layout, event_bindings, hovered, host)?)

	# OnClick
	mouse_left_button = 0
	if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}

	focused = if is_mouse_button_pressed(host.mouse.buttons_pressed, mouse_left_button) {
		hovered.get(0).ok_or(root_index)
	} else {
		prev_focused
	}

	# Key events
	$msgs = $msgs.concat(get_key_events(event_bindings, focused, host.keys_pressed, host.keys, host.keys_released))

	# Drag gestures
	{ drag, messages: drag_msgs } = Drag.advance(layout, event_bindings, hovered, drag_state, host.mouse)?
	$msgs = $msgs.concat(drag_msgs)

	Ok({ messages: $msgs, hovered, focused, drag })
}

pointer_button_state : HostState, U64 -> Event.PointerButtonState
pointer_button_state = |host, button| {
	{
		down: is_mouse_button_pressed(host.mouse.buttons, button),
		pressed: is_mouse_button_pressed(host.mouse.buttons_pressed, button),
		released: is_mouse_button_pressed(host.mouse.buttons_released, button),
	}
}

pointer_buttons : HostState -> Event.PointerButtons
pointer_buttons = |host| {
	{
		left: pointer_button_state(host, 0),
		middle: pointer_button_state(host, 1),
		right: pointer_button_state(host, 2),
	}
}

pointer_event : Layout(draw), U64, HostState -> Try(Event.PointerEvent, Layout.LayoutError)
pointer_event = |layout, node_id, host| {
	Ok({
		position: { x: host.mouse.x, y: host.mouse.y },
		buttons: pointer_buttons(host),
		target: {
			id: node_id,
			bounds: layout.node_bounds(node_id)?,
		},
	})
}

get_pointer_enter_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_pointer_enter_events = |bindings, prev_hovered, next_hovered| {
	next_hovered
		.iter()
		.keep_if(|node_index| !prev_hovered.contains(node_index))
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnPointerEnter(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_pointer_leave_events : EventBindings(msg), List(U64), List(U64) -> List(msg)
get_pointer_leave_events = |bindings, prev_hovered, next_hovered| {
	prev_hovered
		.iter()
		.keep_if(|node_index| !next_hovered.contains(node_index))
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnPointerLeave(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_hover_events : EventBindings(msg), List(U64) -> List(msg)
get_hover_events = |bindings, hovered| {
	hovered
		.iter()
		.fold(
			[],
			|msgs, node_index| {
				bindings
					.get(node_index)
					.ok_or([])
					.iter()
					.fold(
						msgs,
						|event_msgs, event| {
							match event {
								OnHover(msg) => event_msgs.append(msg)
								_ => event_msgs
							}
						},
					)
			},
		)
}

get_pointer_events : Layout(draw), EventBindings(msg), List(U64), HostState -> Try(List(msg), Layout.LayoutError)
get_pointer_events = |layout, bindings, hovered, host| {
	var $msgs = []
	for node_index in hovered {
		event = pointer_event(layout, node_index, host)?
		$msgs = $msgs.concat(
			bindings
				.get(node_index)
				.ok_or([])
				.iter()
				.fold(
					[],
					|event_msgs, binding| {
						match binding {
							OnPointer(callback) => event_msgs.concat((Box.unbox(callback))(event))
							_ => event_msgs
						}
					},
				),
		)
	}
	Ok($msgs)
}

get_click_events : EventBindings(msg), U64 -> List(msg)
get_click_events = |bindings, node_index| {
	bindings
		.get(node_index)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, event| {
				match event {
					OnClick(msg) => msgs.append(msg)
					_ => msgs
				}
			},
		)
}

get_key_events : EventBindings(msg), U64, List(U8), List(U8), List(U8) -> List(msg)
get_key_events = |bindings, focused, keys_pressed, keys_down, keys_released| {
	bindings
		.get(focused)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, binding| {
				match binding {
					OnKeyPressed(key, msg) => if is_key_pressed(keys_pressed, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if is_key_pressed(keys_down, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyUp(key, msg) => if is_key_pressed(keys_released, key) {
						msgs.append(msg)
					} else {
						msgs
					}
					_ => msgs
				}
			},
		)
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerEnter("enter-one")])
			.insert(2, [OnPointerEnter("enter-two")])

	get_pointer_enter_events(bindings, [1], [2, 1]) == ["enter-two"]
}

## Scroll positions clamp at the top and bottom limits.
expect {
	clamp_scroll_axis(Scroll, 15, 140, 60) == 0
		and clamp_scroll_axis(Scroll, -200, 140, 60) == -80
}

## A retained position is clamped upward when content shrinks.
expect {
	clamp_scroll_axis(Scroll, -80, 90, 60) == -30
}

## Scroll overflow stays clamped when content fits and moves when it overflows.
expect {
	scrolls_axis(Scroll)
		and clamp_scroll_axis(Scroll, -20, 60, 60) == 0
			and scrolls_axis(Scroll)
				and clamp_scroll_axis(Scroll, -20, 100, 60) == -20
}

## The deepest hovered scrollable container wins wheel routing.
expect {
	outer = {
		id: 1,
		scroll_container_dimensions: { w: 100, h: 100 },
		content_dimensions: { w: 100, h: 300 },
		overflow: { x: Hidden, y: Scroll },
		scroll_position: { x: 0, y: 0 },
	}
	inner = {
		id: 2,
		scroll_container_dimensions: { w: 80, h: 80 },
		content_dimensions: { w: 80, h: 200 },
		overflow: { x: Hidden, y: Scroll },
		scroll_position: { x: 0, y: 0 },
	}
	deepest_vertical_scroll_target([outer, inner], [2, 1]) == ScrollTarget(2)
}

expect {
	bindings =
		Dict.empty()
			.insert(1, [OnPointerLeave("leave-one")])
			.insert(2, [OnPointerLeave("leave-two")])

	get_pointer_leave_events(bindings, [2, 1], [1]) == ["leave-two"]
}
