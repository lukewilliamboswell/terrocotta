## Bridge Terracotta's platform-independent startup settings to current roc-ray.
import rr.App
import rr.Mouse

import tc.Program as TcProgram

RocRayApp := [].{
	step : App.Input(msg) -> _
	step = |input| {
		fields = input.fields()
		devices = fields.devices
		mouse = devices.mouse
		{
			messages: fields.messages,
			input: {
				keys: devices.keys,
				text_input: devices.text_input,
				gamepads: devices.gamepads,
				mouse: {
					buttons: mouse.buttons,
					left: mouse.left,
					middle: mouse.middle,
					right: mouse.right,
					wheel: mouse.wheel,
					wheel_x: mouse.wheel_x,
					wheel_y: mouse.wheel_y,
					delta_x: mouse.delta_x,
					delta_y: mouse.delta_y,
					x: mouse.x,
					y: mouse.y,
				},
			},
			window: { size: fields.window.size, focused: fields.window.focused, minimized: fields.window.minimized },
			time: {
				elapsed_seconds: fields.time.elapsed_seconds,
				timestamp_nanos: fields.time.simulation_nanos,
				cycle_count: fields.time.cycle_count,
				monotonic_nanos: fields.time.monotonic_nanos,
			},
			capture: fields.capture,
		}
	}

	config : TcProgram.Config -> App.Config
	config = |config| {
		pacing = if config.vsync {
			VSync
		} else if config.target_fps > 0 {
			Capped(config.target_fps)
		} else {
			Uncapped
		}
		cursor = if config.cursor_visible Visible else Hidden

		App.default
			.with_title(config.title)
			.with_size({ width: config.width, height: config.height })
			.with_frame_pacing(pacing)
			.with_resizable(config.resizable)
			.with_fullscreen(config.fullscreen)
			.with_cursor_mode(cursor)
	}
}
