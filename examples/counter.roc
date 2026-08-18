## Minimal counter with increment and decrement buttons.
app [Model, Msg, program] {
	rr: platform "../../roc-ray/platform/main.roc",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-14-549b94e",
}

import rr.App
import rr.Color as RayColor
import rr.Draw
import rr.Program as RayProgram

import tc.Element exposing [box, text, View, style]
import tc.Font
import tc.Program
import tc.Render
import tc.Theme
import tc.Widget exposing [button]

theme = Theme.dark

Model : Program.State(AppModel, Msg, Draw.Font)

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

update_model : AppModel, Msg -> AppModel
update_model = |model, msg| match msg {
	Decrement => { ..model, count: model.count - 1 }
	Increment => { ..model, count: model.count + 1 }
}

view : AppModel -> View(Msg, Draw.Font)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.background(theme.palette.background.base.fill)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content),
		[],
		[
			box(
				Auto,
				|_| style
					.height(Fit({ min: 0, max: 10000 }))
					.gap(theme.gap)
					.direction(Row),
				[],
				[
					button(theme, Primary, "-", [OnClick(Decrement)]),
					text("Count: ${model.count.to_str()}"),
					button(theme, Primary, "+", [OnClick(Increment)]),
				],
			),
		],
	)
}

program = { init!, update, render! }

init! : App.Init(Model, [])
init! = App.init(
	App.static_config(App.default.with_title("Counter Example").with_size({ width: 640, height: 420 })),
	|_startup| {
		font = Font.handle(0, Draw.default_font!())
		Ok(Program.init({ count: 0 }, font))
	},
)

update : Model, RayProgram.Step(Msg) -> RayProgram.Update(Model, Msg)
update = |model, step| {
	result = Program.step({
		state: model,
		input: step.input,
		viewport: step.window.size,
		view,
		update: update_model,
	})

	match result {
		Ok(next_model) => RayProgram.static(next_model)
		Err(_) => RayProgram.static(model).with_action(RayProgram.exit(1))
	}
}

render! : Model, Draw.Frame => Try({}, [Exit(I64), ..])
render! = |model, frame| {
	Render.draw_commands!(
		frame,
		model.commands,
		|color| RayColor.rgba(color.r, color.g, color.b, color.a),
	)
}
