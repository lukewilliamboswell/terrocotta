## Model-View-Update architecture runtime.
## Wires init, view, and update into the platform's { init!, render! } contract.
##
## Usage:
##   program = Program.new!({ config, init!, view, update })
##
## `init!` receives the platform startup capability and returns the initial
## model, a pure text measurer, and one retained command renderer. Programs
## derive compact render data from a pre-event model rather than retaining that
## model for rendering.
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
	## command list plus its compact render data; `render!` passes both to the
	## renderer's single resource-owning closure. `Layout` retains only its
	## separate pure text measurer, and State never retains a second app model.
	State(model, msg, draw_frame, data) :: {
		model : model,
		render_data : { data : data, frame : Frame },
		layout : Layout,
		renderer : Render.Adapter(draw_frame, data),
		commands : List(Render.Command),
		hovered : List(U64),
		focused : U64,
		scroll : Dict(U64, ScrollState),
		drag : Drag.DragState,
	}

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

	## Ordered platform work emitted while reducing messages.
	Work(action, task) : {
		actions : List(action),
		tasks : List(task),
	}

	## Return a next model without scheduling platform work. This is the common
	## reducer result for ordinary UI updates.
	no_work : m -> StepResult(m, action, task)
	no_work = |model| { model, actions: [], tasks: [] }

	## Fold a batch of platform messages with the application's ordinary update
	## function. `new!` uses this for `step.messages`; custom programs can use it
	## when they want to augment the default platform-message behavior. Work is
	## appended element-by-element into unique accumulators, keeping a message
	## batch amortized-linear even when reducers emit several items each.
	apply_messages : m, List(msg), (m, msg -> StepResult(m, action, task)) -> StepResult(m, action, task)
	apply_messages = |model, messages, update| {
		var $model = model
		var $actions = []
		var $tasks = []
		for message in messages {
			result = update($model, message)
			$model = result.model
			for action in result.actions {
				$actions = $actions.append(action)
			}
			for task in result.tasks {
				$tasks = $tasks.append(task)
			}
		}
		{ model: $model, actions: $actions, tasks: $tasks }
	}

	## Preserve platform work returned by `on_step` while replacing only the
	## program state prepared for this cycle.
	step_work : StepResult(m, action, task) -> Work(action, task)
	step_work = |result| { actions: result.actions, tasks: result.tasks }

	## Concatenate ordered work. Callers pass earlier work first, so actions and
	## tasks preserve platform-step order before UI-event order.
	append_work : Work(action, task), Work(action, task) -> Work(action, task)
	append_work = |earlier, later| {
		actions: earlier.actions.concat(later.actions),
		tasks: earlier.tasks.concat(later.tasks),
	}

	## Build a message-driven program. `init!` supplies the initial model, a pure
	## text measurer, and command renderer. `new!` installs empty render data;
	## use `custom!` when renderer pre-work needs a compact app-derived
	## projection or when platform step/frame hooks need customization.
	new! : {
		config : Config,
		init! : Config, startup => Try({ model : m, measure_text : Render.MeasureText, renderer : Render.Adapter(draw_frame, {}) }, [Exit(I64)]),
		view : m -> Element.View(msg),
		update : m, msg -> StepResult(m, action, task),
	} -> {
		init! : startup => Try(State(m, msg, draw_frame, {}), [Exit(I64)]),
		update : State(m, msg, draw_frame, {}), Step(msg, input, mouse, window, time, step) -> Try({ model : State(m, msg, draw_frame, {}), actions : List(action), tasks : List(task) }, [Exit(I64), ..]),
		render! : State(m, msg, draw_frame, {}), draw_frame => Try({}, [Exit(I64), ..]),
	}
	new! = |{ config, init!, view, update }| Program.custom!({
		config,
		init!,
		on_step: |model, step| Program.apply_messages(model, step.messages, update),
		on_frame: |model, _frame| model,
		render_data: |_model, _frame| {},
		view,
		update,
	})

	## Advanced constructor for message-driven programs. `on_step` receives the
	## full platform step after inherited scrolling is updated and may fold,
	## replace, or augment `step.messages`; its returned actions and tasks pass
	## through unchanged. `on_frame` then creates the render model, layout, and
	## retained commands. `render_data` then derives ordinary compact data from
	## that exact pre-event render model and Frame. UI events update the retained
	## `model` afterwards and may emit same-cycle actions and tasks; those follow
	## `on_step` work in event order.
	##
	## The renderer receives `render_data` and the same Frame immediately before
	## replaying the retained commands. Its single closure owns any associated
	## shaders or uniforms; Program stores no second app model.
	custom! : {
		config : Config,
		init! : Config, startup => Try({ model : m, measure_text : Render.MeasureText, renderer : Render.Adapter(draw_frame, data) }, [Exit(I64)]),
		on_step : m, Step(msg, input, mouse, window, time, step) -> StepResult(m, action, task),
		on_frame : m, Frame -> m,
		render_data : m, Frame -> data,
		view : m -> Element.View(msg),
		update : m, msg -> StepResult(m, action, task),
	} -> {
		init! : startup => Try(State(m, msg, draw_frame, data), [Exit(I64)]),
		update : State(m, msg, draw_frame, data), Step(msg, input, mouse, window, time, step) -> Try({ model : State(m, msg, draw_frame, data), actions : List(action), tasks : List(task) }, [Exit(I64), ..]),
		render! : State(m, msg, draw_frame, data), draw_frame => Try({}, [Exit(I64), ..]),
	}
	custom! = |{ config, init!, on_step, on_frame, render_data, view, update }| {
		init_state! = |startup| {
			initialized = init!(config, startup)?
			initial_frame = {
				delta_seconds: 0,
				timestamp_nanos: 0,
				screen: { width: config.width.to_f32(), height: config.height.to_f32() },
			}
			Ok(
				State.(
					{
						model: initialized.model,
						render_data: { data: render_data(initialized.model, initial_frame), frame: initial_frame },
						layout: Layout.new(initialized.measure_text),
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
			frame_input = {
				model: render_model,
				layout: state.layout,
				hovered: state.hovered,
				focused: state.focused,
				scroll,
				drag: state.drag,
			}
			prepared = prepare_frame(frame_input, state.commands, host, frame, render_data, view, update)?
			next_state = State.(
				{
					model: prepared.model,
					render_data: { data: prepared.render_data, frame },
					layout: prepared.layout,
					renderer: state.renderer,
					commands: prepared.commands,
					hovered: prepared.hovered,
					focused: prepared.focused,
					scroll: prepared.scroll,
					drag: prepared.drag,
				},
			)
			work = Program.append_work(Program.step_work(step_result), prepared.work)
			Ok({ model: next_state, actions: work.actions, tasks: work.tasks })
		}

		render_state! = |State.(state), draw_frame| {
			Render.render!(state.renderer, draw_frame, state.render_data.data, state.render_data.frame, state.commands)
			Ok({})
		}

		{ init!: init_state!, update: update_state, render!: render_state! }
	}
}

FramePreparation(model, data, action, task) : {

	## Compact data derived from the exact pre-event model paired with retained
	## commands. Program does not add a model owner here; applications should keep
	## this projection free of renderer resources.
	render_data : data,
	model : model,
	work : Program.Work(action, task),
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

## Apply scrolling from the previous layout before platform-step and frame-model
## work. This preserves scroll-before-frame ordering for every update.
prepare_scroll : Layout, Dict(U64, ScrollState), HostState(host, mouse) -> Try(Dict(U64, ScrollState), [Exit(I64), ..])
prepare_scroll = |layout, scroll, host| {
	update_scroll_containers(layout, scroll, { x: host.mouse.x, y: host.mouse.y }, host.mouse.wheel).map_err(|_e| Exit(1))
}

## Convert host timing and screen observations into the compact `Frame` passed
## to frame hooks and retained render data.
frame_from_host : HostState(host, mouse) -> Program.Frame
frame_from_host = |host| {
	screen = { w: host.screen.width.to_f32(), h: host.screen.height.to_f32() }
	{
		delta_seconds: host.frame_time,
		timestamp_nanos: host.timestamp_nanos,
		screen: { width: screen.w, height: screen.h },
	}
}

## Prepare layout, compact render data, UI events, and one retained command list
## after scroll and the frame model are current. Render data is deliberately
## derived before UI events, exactly matching the retained commands.
FrameInput(model) : {
	model : model,
	layout : Layout,
	hovered : List(U64),
	focused : U64,
	scroll : Dict(U64, ScrollState),
	drag : Drag.DragState,
}

prepare_frame : FrameInput(m), List(Render.Command), HostState(host, mouse), Program.Frame, (m, Program.Frame -> data), (m -> Element.View(msg)), (m, msg -> Program.StepResult(m, action, task)) -> Try(FramePreparation(m, data, action, task), [Exit(I64), ..])
prepare_frame = |state, previous_commands, host, frame, derive_render_data, view, update| {
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
	render_data = derive_render_data($model, frame)
	{ messages, hovered, focused, drag } = handle_events($layout, $event_bindings, host, state.hovered, state.focused, state.drag).map_err(|_e| Exit(1))?
	ui_result = Program.apply_messages($model, messages, update)
	$model = ui_result.model

	commands = $layout.to_commands(screen, previous_commands).map_err(|_e| Exit(1))?
	Ok({ render_data, model: $model, work: Program.step_work(ui_result), layout: $layout, commands, hovered, focused, scroll: state.scroll, drag })
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
expect Program.apply_messages(3, [4, 5], |model, message| Program.no_work(model + message)).model == 12

## Custom step work remains attached to the enclosing platform result.
expect Program.step_work({ model: "ignored", actions: ["first", "second"], tasks: [7] }) == {
	actions: ["first", "second"],
	tasks: [7],
}

## Step work precedes UI work, while each UI message keeps reducer order.
expect {
	ui = Program.apply_messages(
		0,
		[1, 2],
		|model, message| {
			model: model + message,
			actions: [message, message + 10],
			tasks: [model, model + 100],
		},
	)
	all_work = Program.append_work({ actions: [10], tasks: [20] }, Program.step_work(ui))

	ui.model == 3 and all_work.actions == [10, 1, 11, 2, 12] and all_work.tasks == [20, 0, 100, 1, 101]
}

## Render data is a compact pre-event projection rather than a retained model.
expect {
	frame : Program.Frame
	frame = { delta_seconds: 0.25, timestamp_nanos: 42, screen: { width: 640, height: 480 } }
	project = |model, render_frame| { value: model, timestamp_nanos: render_frame.timestamp_nanos }

	project(8, frame) == { value: 8, timestamp_nanos: 42 }
}

full_step_rows : Program.Step(
	Str,
	{ text_input : List(U32), gamepads : List(U8) },
	{},
	{ focused : Bool, minimized : Bool },
	{ frame_count : U64, wall_timestamp_nanos : U64 },
	{ capture : Bool },
) -> { messages : List(Str), text_input : List(U32), gamepads : List(U8), focused : Bool, minimized : Bool, frame_count : U64, capture : Bool }
full_step_rows = |step| {
	messages: step.messages,
	text_input: step.input.text_input,
	gamepads: step.input.gamepads,
	focused: step.window.focused,
	minimized: step.window.minimized,
	frame_count: step.time.frame_count,
	capture: step.capture,
}

## Structural steps retain all platform observations for custom `on_step` code.
expect full_step_rows({
	messages: ["external"],
	input: {
		keys: [],
		text_input: [65],
		gamepads: [2],
		mouse: { buttons: [], left: False, middle: False, right: False, wheel: 0, wheel_x: 0, wheel_y: 0, delta_x: 0, delta_y: 0, x: 0, y: 0 },
	},
	window: { size: { width: 800, height: 600 }, focused: True, minimized: False },
	time: { elapsed_seconds: 0.016, timestamp_nanos: 16_000_000, frame_count: 7, wall_timestamp_nanos: 17_000_000 },
	capture: True,
}) == {
	messages: ["external"],
	text_input: [65],
	gamepads: [2],
	focused: True,
	minimized: False,
	frame_count: 7,
	capture: True,
}
