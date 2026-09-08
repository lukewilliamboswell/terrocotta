## Minimal counter with increment and decrement buttons.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc5/8x22d4JXTKSiPvj3Bd3br2u7rEL3baUzEvmSBrCBDvqV.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-09-07-14d9829",
}

import rr.App
import rr.Draw

import tc.Color
import tc.Element exposing [box, text, View, style, default_font]
import tc.Program
import tc.Render
import tc.Theme
import tc.Widget exposing [button]

import RocRayApp
import RocRayRenderer

theme = Theme.dark

Model :: Program.State(AppModel, Msg, Draw.Frame, {})

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

init! : Program.Config, App.Startup => Try({ model : AppModel, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config, _startup| {
	rendering = RocRayRenderer.default!({})
	Ok({ model: { count: 0 }, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

update : AppModel, Msg -> Program.StepResult(AppModel, action, task)
update = |model, msg| Program.no_work(
	match msg {
		Decrement => { ..model, count: model.count - 1 }
		Increment => { ..model, count: model.count + 1 }
	},
)

view : AppModel -> View(Msg)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
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

config : Program.Config
config = { ..Program.default, title: "Counter Example", width: 640, height: 420 }

tc_program = Program.new!({
	config,
	init!,
	view,
	update,
})

ray_update! : Model, App.Input(Msg) => Try(Model, [Exit(I64), ..])
ray_update! = |Model.(state), input| {
	tc_update = tc_program.update
	next = tc_update(state, RocRayApp.step(input))?
	Ok(Model.(next.model))
}

ray_render! : Model, Draw.Frame => Try({}, [Exit(I64), ..])
ray_render! = |Model.(state), frame| {
	tc_render! = tc_program.render!
	tc_render!(state, frame)
}

program = {
	init!: App.init(
		RocRayApp.config(config),
		|startup| {
			tc_init! = tc_program.init!
			tc_init!(startup).map_ok(|state| Model.(state))
		},
	),
	update!: ray_update!,
	render!: ray_render!,
}
