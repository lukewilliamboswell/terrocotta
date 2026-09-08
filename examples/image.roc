## Image sizing with an application-owned roc-ray texture.
app [Model, Msg, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0-rc5/8x22d4JXTKSiPvj3Bd3br2u7rEL3baUzEvmSBrCBDvqV.tar.zst",
	tc: "../package/main.roc",
	roc: "nightly-2026-09-07-14d9829",
}

import rr.App
import rr.Assets
import rr.Draw

import tc.Element exposing [View, box, image, style]
import tc.Program
import tc.Render
import tc.Theme

import RocRayApp
import RocRayRenderer

import "assets/screwbot-crate-v2.png" as image_bytes : List(U8)

theme = Theme.dark

Model :: Program.State(AppModel, Msg, Draw.Frame, {})

AppModel : { texture : Element.Texture }
Msg : [NoOp]

init! : Program.Config, App.Startup => Try({ model : AppModel, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config, _startup| {
	texture = Assets.texture_from_bytes!({ format: Png, bytes: image_bytes }).map_err(|_| Exit(1))?
	rendering = RocRayRenderer.with_texture!(texture)
	Ok({ model: { texture: rendering.texture }, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

update : AppModel, Msg -> Program.StepResult(AppModel, action, task)
update = |model, _msg| Program.no_work(model)

view : AppModel -> View(Msg)
view = |model|
	box(
		Auto,
		|_| style
			.background(theme.palette.background.base.fill)
			.child_align({ x: Center, y: Center }),
		[],
		[
			box(
				Auto,
				|_| style
					.width(Fixed(400))
					.height(Fixed(300))
					.radius(theme.radius)
					.overflow(Hidden, Hidden),
				[],
				[image(model.texture)],
			),
		],
	)

config : Program.Config
config = { ..Program.default, title: "Image Example", width: 700, height: 500 }

tc_program = Program.new!({ config, init!, view, update })

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
	init!: App.init(RocRayApp.config(config), |startup| {
		tc_init! = tc_program.init!
		tc_init!(startup).map_ok(|state| Model.(state))
	}),
	update!: ray_update!,
	render!: ray_render!,
}
