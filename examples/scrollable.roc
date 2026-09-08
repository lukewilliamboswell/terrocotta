## Scrollable list demonstration.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc5/8x22d4JXTKSiPvj3Bd3br2u7rEL3baUzEvmSBrCBDvqV.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-09-07-14d9829",
}

import rr.App
import rr.Draw

import tc.Element exposing [box, text, View, style]
import tc.Program
import tc.Render
import tc.Theme

import RocRayApp
import RocRayRenderer

theme = Theme.light

Model :: Program.State({}, Msg, Draw.Frame, {})

Msg : []

init! : Program.Config, App.Startup => Try({ model : {}, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config, _startup| {
	rendering = RocRayRenderer.default!({})
	Ok({ model: {}, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

update : {}, Msg -> Program.StepResult({}, action, task)
update = |model, _msg| Program.no_work(model)

row : U64 -> View(Msg)
row = |index| {
	box(
		IdI("scroll-row", index),
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.child_align({ x: Start, y: Center })
			.background(theme.palette.background.weak.fill),
		[],
		[text("Scrollable row ${index.to_str()}")],
	)
}

view : {} -> View(Msg)
view = |_model| {
	var $rows = []
	for index in 1..<20 {
		$rows = $rows.append(row(index))
	}
	rows = $rows
	box(
		Id("page"),
		|_| style
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.gap(theme.gap)
			.background(theme.palette.background.base.fill)
			.font_family(theme.font)
			.font_size(theme.font_size)
			.font_color(theme.palette.background.base.content),
		[],
		[
			text("Move the pointer over the panel and use the mouse wheel."),
			box(
				Id("scroll-container"),
				|_| style
					.direction(Col)
					.child_align({ x: Start, y: Start })
					.gap(theme.gap)
					.pad((theme.gap, theme.gap, theme.gap, theme.gap))
					.border({ color: theme.palette.primary.base.fill, left: 2, right: 2, top: 2, bottom: 2 })
					.radius(theme.radius)
					.overflow(Hidden, Scroll),
				[],
				rows,
			),
		],
	)
}

config : Program.Config
config = { ..Program.default, title: "Scrollable Container", width: 720, height: 520 }

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
