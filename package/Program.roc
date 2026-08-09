## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, renderer, init!, view, update })
import Layout
import LayoutTypes
import Render
import Element
import Color
import Event
import Drag

HostState(host, mouse) : {
	frame_time : F32,
	timestamp_nanos : U64,
	screen : { width : I32, height : I32 },
	keys : List(U8),
	mouse : {
		buttons : List(U8),
		left : Bool,
		middle : Bool,
		right : Bool,
		wheel : F32,
		wheel_x : F32,
		wheel_y : F32,
		delta_x : F32,
		delta_y : F32,
		x : F32,
		y : F32,
		..mouse,
	},
	..host,
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

Program :: [].{

	## Timing supplied to the optional pure per-frame model update.
	Frame : {
		delta_seconds : F32,
		timestamp_nanos : U64,
		screen : { width : F32, height : F32 },
	}

	Config : {
		title : Str,
		width : I32,
		height : I32,
		target_fps : I32,
		resizable : Bool,
		fullscreen : Bool,
		vsync : Bool,
		cursor_visible : Bool,
	}

	default : Config
	default = {
		title: "Terrocotta App",
		width: 800,
		height: 600,
		target_fps: 2000,
		resizable: Bool.True,
		fullscreen: Bool.False,
		vsync: Bool.False,
		cursor_visible: Bool.True,
	}

	## State for the message-driven renderer. `update` produces and retains one
	## command list; `render!` receives the platform-owned drawing capability and
	## only replays that list. No host capability is retained in the model.
	State(model, msg, draw_frame) :: {
		model : model,
		render_snapshot : RenderSnapshot(model),
		layout : Layout,
		renderer : Render.Adapter(draw_frame),
		commands : List(Render.Command),
		hovered : List(U64),
		focused : U64,
		scroll : Dict(U64, ScrollState),
		drag : Drag.DragState,
	}

	## Model/frame pair associated with retained commands. `CurrentModel` avoids
	## retaining a second ARC owner on frames with no UI event messages;
	## `RetainedModel` owns the required pre-event model only when it differs
	## from the next retained model.
	RenderSnapshot(model) : [
		CurrentModel(Frame),
		RetainedModel({ model : model, frame : Frame }),
	]

	## The full structural step accepted by a program. Terracotta reads
	## host observations from it but passes the complete value to `on_step`, so
	## platform-specific observations and external messages are never projected
	## away.
	Step(msg, input, mouse, window, time, step) : {
		messages : List(msg),
		input : {
			keys : List(U8),
			mouse : {
				buttons : List(U8),
				left : Bool,
				middle : Bool,
				right : Bool,
				wheel : F32,
				wheel_x : F32,
				wheel_y : F32,
				delta_x : F32,
				delta_y : F32,
				x : F32,
				y : F32,
				..mouse,
			},
			..input,
		},
		window : { size : { width : I32, height : I32 }, ..window },
		time : { elapsed_seconds : F32, timestamp_nanos : U64, ..time },
		..step,
	}

	## Result returned by a platform-step hook. Actions and tasks remain owned by
	## the enclosing platform rather than being discarded by Terracotta.
	StepResult(model, action, task) : {
		model : model,
		actions : List(action),
		tasks : List(task),
	}

	## Fold a batch of platform messages with the application's ordinary update
	## function. `new!` uses this for `step.messages`; custom programs can use it
	## when they want to augment the default platform-message behavior.
	apply_messages : m, List(msg), (m, msg -> m) -> m
	apply_messages = |model, messages, update| {
		var $model = model
		for message in messages {
			$model = update($model, message)
		}
		$model
	}

	## Preserve platform work returned by `on_step` while replacing only the
	## program state prepared for this cycle.
	step_work : StepResult(m, action, task) -> { actions : List(action), tasks : List(task) }
	step_work = |result| { actions: result.actions, tasks: result.tasks }

	## Build a message-driven program. `update`
	## accepts the platform's full structural step, folds `step.messages` through
	## `update`, and prepares retained commands. `render!` only replays those
	## commands. Use `custom!` when platform-step processing needs to return
	## actions or tasks of its own.
	new! : {
		config : Config,
		renderer : Render.Adapter(draw_frame),
		init! : Config => Try(m, [Exit(I64)]),
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : startup => Try(State(m, msg, draw_frame), [Exit(I64)]),
		update : State(m, msg, draw_frame), Step(msg, input, mouse, window, time, step) -> Try({ model : State(m, msg, draw_frame), actions : List(action), tasks : List(task) }, [Exit(I64), ..]),
		render! : State(m, msg, draw_frame), draw_frame => Try({}, [Exit(I64), ..]),
	}
	new! = |{ config, renderer, init!, view, update }| Program.custom!({
		config,
		init!: |cfg| init!(cfg).map_ok(|model| { model, renderer }),
		on_step: |model, step| {
			{ model: Program.apply_messages(model, step.messages, update), actions: [], tasks: [] }
		},
		on_frame: |model, _frame| model,
		before_render!: |_model, _frame, _draw_frame| {},
		view,
		update,
	})

	## Advanced constructor for message-driven programs. `on_step` receives the
	## full platform step after inherited scrolling is updated and may fold,
	## replace, or augment `step.messages`; its returned actions and tasks pass
	## through unchanged. `on_frame` then creates the render model, layout, and
	## retained commands. UI events update the retained `model` afterwards.
	##
	## `before_render!` runs immediately before replaying those retained commands
	## with the exact pre-event model and `Frame` that produced them. It receives
	## no platform step or task messages, so retained state remains compact.
	custom! : {
		config : Config,
		init! : Config => Try({ model : m, renderer : Render.Adapter(draw_frame) }, [Exit(I64)]),
		on_step : m, Step(msg, input, mouse, window, time, step) -> StepResult(m, action, task),
		on_frame : m, Frame -> m,
		before_render! : m, Frame, draw_frame => {},
		view : m -> Element.View(msg),
		update : m, msg -> m,
	} -> {
		init! : startup => Try(State(m, msg, draw_frame), [Exit(I64)]),
		update : State(m, msg, draw_frame), Step(msg, input, mouse, window, time, step) -> Try({ model : State(m, msg, draw_frame), actions : List(action), tasks : List(task) }, [Exit(I64), ..]),
		render! : State(m, msg, draw_frame), draw_frame => Try({}, [Exit(I64), ..]),
	}
	custom! = |{ config, init!, on_step, on_frame, before_render!, view, update }| {
		init_state! = |_startup| {
			initialized = init!(config)?
			initial_frame = {
				delta_seconds: 0,
				timestamp_nanos: 0,
				screen: { width: config.width.to_f32(), height: config.height.to_f32() },
			}
			Ok(
				State.(
					{
						model: initialized.model,
						render_snapshot: CurrentModel(initial_frame),
						layout: Layout.new(initialized.renderer),
						renderer: initialized.renderer,
						commands: [],
						hovered: [],
						focused: 0,
						scroll: Dict.empty(),
						drag: Idle,
					},
				),
			)
		}

		update_state = |State.(state), step| {
			host = host_state(step)
			scroll = prepare_scroll(state.layout, state.scroll, host)?
			step_result = on_step(state.model, step)
			frame = frame_from_host(host)
			render_model = on_frame(step_result.model, frame)
			prepared = prepare_frame({ ..state, model: render_model, scroll }, host, frame, view, update)?
			next_state = State.(
				{
					model: prepared.model,
					render_snapshot: prepared.render_snapshot,
					layout: prepared.layout,
					renderer: state.renderer,
					commands: prepared.commands,
					hovered: prepared.hovered,
					focused: prepared.focused,
					scroll: prepared.scroll,
					drag: prepared.drag,
				},
			)
			work = Program.step_work(step_result)
			Ok({ model: next_state, actions: work.actions, tasks: work.tasks })
		}

		render_state! = |State.(state), draw_frame| {
			match state.render_snapshot {
				CurrentModel(frame) => before_render!(state.model, frame, draw_frame)
				RetainedModel(snapshot) => before_render!(snapshot.model, snapshot.frame, draw_frame)
			}
			Render.render!(state.renderer, draw_frame, state.commands)
			Ok({})
		}

		{ init!: init_state!, update: update_state, render!: render_state! }
	}
}

FramePreparation(model) : {

	## Exact snapshot paired with the retained commands. It uses the final model
	## directly when no UI messages ran, avoiding a duplicate ARC owner.
	render_snapshot : Program.RenderSnapshot(model),
	model : model,
	layout : Layout,
	commands : List(Render.Command),
	hovered : List(U64),
	focused : U64,
	scroll : Dict(U64, ScrollState),
	drag : Drag.DragState,
}

host_state : Program.Step(msg, input, mouse, window, time, step) -> HostState({}, mouse)
host_state = |step| {
	frame_time: step.time.elapsed_seconds,
	timestamp_nanos: step.time.timestamp_nanos,
	screen: step.window.size,
	keys: step.input.keys,
	mouse: step.input.mouse,
}

## Apply scrolling from the previous layout before any frame or platform-step
## model work. All adapters use this first phase so a frame observes the same
## inherited scroll ordering.
prepare_scroll : Layout, Dict(U64, ScrollState), HostState(host, mouse) -> Try(Dict(U64, ScrollState), [Exit(I64), ..])
prepare_scroll = |layout, scroll, host| {
	update_scroll_containers(layout, scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))
}

## Convert host timing and screen observations into the compact `Frame` passed
## to frame hooks and retained render snapshots.
frame_from_host : HostState(host, mouse) -> Program.Frame
frame_from_host = |host| {
	screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }
	{
		delta_seconds: host.frame_time,
		timestamp_nanos: host.timestamp_nanos,
		screen: { width: screen.w, height: screen.h },
	}
}

## Shared layout, event, and command-preparation phase for every adapter.
## Callers update scroll and their frame model first, then this function views
## and solves the layout, handles UI events, and retains one command list. The
## returned snapshot is deliberately from before UI events, exactly matching
## the retained commands.
prepare_frame : {
	model : m,
	layout : Layout,
	hovered : List(U64),
	focused : U64,
	scroll : Dict(U64, ScrollState),
	drag : Drag.DragState,
	..state,
},
HostState(host, mouse),
Program.Frame,
(m -> Element.View(msg)),

(m, msg -> m) -> Try(FramePreparation(m), [Exit(I64), ..])
prepare_frame = |state, host, frame, view, update| {
	screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }

	var $layout = state.layout.clear()
	var $event_bindings = Dict.empty()
	var $model = state.model

	for element_op in view($model) {
		($layout, node) = $layout.update!(
			element_op,
			|node_id| get_box_status(node_id, state.hovered, state.focused, host),
			|node_id| state.scroll.get(node_id).map_ok(|item| item.position).ok_or({ x: 0, y: 0 }),
		).map_err(|_e| Exit(1))?

		$event_bindings = match node {
			Node(node_id, Events(events)) => $event_bindings.insert(node_id, events)
			_ => $event_bindings
		}
	}

	$layout = $layout.solve(screen).map_err(|_e| Exit(1))?
	{ messages, hovered, focused, drag } = handle_events($layout, $event_bindings, host, state.hovered, state.focused, state.drag).map_err(|_e| Exit(1))?
	render_snapshot = render_snapshot_for_events(state.model, frame, messages)
	for message in messages {
		$model = update($model, message)
	}

	commands = $layout.to_commands(screen).map_err(|_e| Exit(1))?
	Ok({ render_snapshot, model: $model, layout: $layout, commands, hovered, focused, scroll: state.scroll, drag })
}

## Pair retained commands with their exact render model and frame. Empty UI
## event batches use the final model directly, avoiding a second ARC owner.
render_snapshot_for_events : m, Program.Frame, List(msg) -> Program.RenderSnapshot(m)
render_snapshot_for_events = |render_model, frame, messages| {
	if messages.len() == 0 {
		CurrentModel(frame)
	} else {
		RetainedModel({ model: render_model, frame })
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
update_scroll_containers : Layout, Dict(U64, ScrollState), LayoutTypes.Pos, F32 -> Try(Dict(U64, ScrollState), Layout.LayoutError)
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

get_box_status : U64, List(U64), U64, HostState(host, mouse) -> Element.BoxStatus
get_box_status = |node_index, prev_hovered, focused, host| {
	hovered = prev_hovered.contains(node_index)
	{ hovered, pressed: hovered and host.mouse.left, focused: node_index == focused, disabled: Bool.False }
}

has_input_state : List(U8), U64, U8 -> Bool
has_input_state = |states, index, mask|
	match states.get(index) {
		Ok(state) => U8.bitwise_and(state, mask) != 0
		Err(_) => Bool.False
	}

handle_events : Layout, EventBindings(msg), HostState(host, mouse), List(U64), U64, Drag.DragState -> Try({ messages : List(msg), hovered : List(U64), focused : U64, drag : Drag.DragState }, Layout.LayoutError)
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
	if has_input_state(host.mouse.buttons, mouse_left_button, 2) and hovered.len() > 0 {
		node_index = hovered.get(0)?
		$msgs = $msgs.concat(get_click_events(event_bindings, node_index))
	}

	focused = if has_input_state(host.mouse.buttons, mouse_left_button, 2) {
		hovered.get(0).ok_or(root_index)
	} else {
		prev_focused
	}

	# Key events
	$msgs = $msgs.concat(get_key_events(event_bindings, focused, host.keys))

	# Drag gestures use upstream's dedicated retained capture state machine.
	{ drag, messages: drag_messages } = Drag.advance(layout, event_bindings, hovered, drag_state, host.mouse)?
	$msgs = $msgs.concat(drag_messages)

	Ok({ messages: $msgs, hovered, focused, drag })
}

pointer_button_state : HostState(host, mouse), U64 -> Event.PointerButtonState
pointer_button_state = |host, button| {
	{
		down: has_input_state(host.mouse.buttons, button, 1),
		pressed: has_input_state(host.mouse.buttons, button, 2),
		released: has_input_state(host.mouse.buttons, button, 4),
	}
}

pointer_buttons : HostState(host, mouse) -> Event.PointerButtons
pointer_buttons = |host| {
	{
		left: pointer_button_state(host, 0),
		middle: pointer_button_state(host, 2),
		right: pointer_button_state(host, 1),
	}
}

pointer_event : Layout, U64, HostState(host, mouse) -> Try(Event.PointerEvent, Layout.LayoutError)
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

get_pointer_events : Layout, EventBindings(msg), List(U64), HostState(host, mouse) -> Try(List(msg), Layout.LayoutError)
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

get_key_events : EventBindings(msg), U64, List(U8) -> List(msg)
get_key_events = |bindings, focused, keys| {
	bindings
		.get(focused)
		.ok_or([])
		.iter()
		.fold(
			[],
			|msgs, binding| {
				match binding {
					OnKeyPressed(key, msg) => if has_input_state(keys, key, 2) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyDown(key, msg) => if has_input_state(keys, key, 1) {
						msgs.append(msg)
					} else {
						msgs
					}
					OnKeyUp(key, msg) => if has_input_state(keys, key, 4) {
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

## Default platform messages fold in arrival order before frame preparation.
expect Program.apply_messages(3, [4, 5], |model, message| model + message) == 12

## Custom step work remains attached to the enclosing platform result.
expect Program.step_work({ model: "ignored", actions: ["first", "second"], tasks: [7] }) == {
	actions: ["first", "second"],
	tasks: [7],
}

## A retained pre-event model is needed only when UI events run after commands
## are prepared; no-event frames keep one model owner.
expect {
	frame : Program.Frame
	frame = { delta_seconds: 0.25, timestamp_nanos: 42, screen: { width: 640, height: 480 } }

	render_snapshot_for_events(8, frame, []) == CurrentModel(frame)
		and render_snapshot_for_events(8, frame, ["ui-message"]) == RetainedModel({ model: 8, frame })
}
