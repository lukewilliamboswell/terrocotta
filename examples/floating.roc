## Minimal floating-root demonstration.
app [Model, Msg, program] {
	rr: platform "../../roc-ray-elm/platform/main.roc",
	tc: "../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Program as RayProgram

import tc.Color
import tc.Element exposing [box, text, View, style, default_floating_config]
import tc.Widget exposing [column, row, button]
import tc.Program
import tc.Render
import tc.Theme

import RocRayApp
import RocRayRenderer

theme = Theme.light

Model :: Program.State(AppModel, Msg, Draw.Frame, {})

AppModel : { attach : Element.AttachPoint }

Msg : Element.AttachPoint

init! : Program.Config, App.Startup => Try({ model : AppModel, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config, _startup| {
	rendering = RocRayRenderer.default!({})
	Ok({ model: { attach: Center }, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

update : AppModel, Msg -> Program.StepResult(AppModel, action, task)
update = |model, msg| {
	Program.no_work({ ..model, attach: msg })
}

view : AppModel -> View(Msg)
view = |model| {
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
			text("Attachment points:"),
			column(
				theme,
				[
					row(
						theme,
						[
							button(theme, Secondary, "LeftTop", [OnClick(LeftTop)]),
							button(theme, Secondary, "CenterTop", [OnClick(CenterTop)]),
							button(theme, Secondary, "RightTop", [OnClick(RightTop)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, "LeftCenter", [OnClick(LeftCenter)]),
							button(theme, Secondary, "Center", [OnClick(Center)]),
							button(theme, Secondary, "RightCenter", [OnClick(RightCenter)]),
						],
					),
					row(
						theme,
						[
							button(theme, Secondary, "LeftBottom", [OnClick(LeftBottom)]),
							button(theme, Secondary, "CenterBottom", [OnClick(CenterBottom)]),
							button(theme, Secondary, "RightBottom", [OnClick(RightBottom)]),
						],
					),
				],
			),
			text("Container:"),
			box(
				Id("floating-container"),
				|_| style
				# .width(Grow({min: 0, max: 10000}))
				# .height(Grow({min: 0, max: 10000}))
					.font_size(theme.font_size)
					.border({ color: theme.palette.primary.base.fill, top: 2, left: 2, right: 2, bottom: 2 })
					.radius(theme.radius),
				[],
				[
					box(
						Id("floating-card"),
						|_| style
							.width(Fit({ min: 0, max: 10000 }))
							.height(Fit({ min: 0, max: 10000 }))
							.pad((theme.gap, theme.gap, theme.gap, theme.gap))
							.background(theme.palette.primary.base.fill)
							.font_color(theme.palette.primary.base.content)
							.font_size(theme.font_size)
							.radius(theme.radius)
							.floating(
								Floating({
									target: Parent,
									config: {
										..default_floating_config,
										z_index: 100,
										attach_points: { element: model.attach, target: model.attach },
									},
								}),
							),
						[],
						[text("floating")],
					),
				],
			),
		],
	)
}

config : Program.Config
config = { ..Program.default, title: "Floating Root", width: 720, height: 520 }

tc_program = Program.new!({
	config,
	init!,
	view,
	update,
})

ray_update : Model, RayProgram.Step(Msg) -> Try(RayProgram.Next(Model, Msg), [Exit(I64), ..])
ray_update = |Model.(state), step| {
	tc_update = tc_program.update
	next = tc_update(state, step.fields())?
	Ok({ model: Model.(next.model), actions: next.actions, tasks: next.tasks })
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
	update: ray_update,
	render!: ray_render!,
}
