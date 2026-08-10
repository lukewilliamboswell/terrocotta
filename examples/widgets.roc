## Example showcasing theme-aware widgets.
app [Model, Msg, program] {
	rr: platform "../../roc-ray-elm/platform/main.roc",
	tc: "../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Program as RayProgram
import tc.Color
import tc.Element exposing [Font, View, box, style]
import tc.Layout
import tc.Program
import tc.Render
import tc.Theme
import tc.Widget

import RocRayApp
import RocRayRenderer

import "assets/Inter-Regular.ttf" as inter_font_bytes : List(U8)

Model :: Program.State(AppModel, Msg, Draw.Frame, {})

AppModel : { theme : Theme, font : Font, slider_value : F32, select_open : Bool, select_selected : U64, toggle_on : Bool }

Msg : [SetSliderValue(F32), SetTheme(Theme), ToggleSelect(Bool), SelectOption(U64), SetToggle(Bool)]

theme_card : Theme, Str, AppModel -> View
theme_card = |theme, name, model| {
	Widget.panel(
		theme,
		[
			Widget.label(theme, "Heading"),
			Widget.heading(theme, name),
			Widget.label(theme, "Badge"),
			Widget.row(
				theme,
				[
					Widget.badge(theme, Primary, "Primary"),
					Widget.badge(theme, Success, "Success"),
					Widget.badge(theme, Warning, "Warning"),
					Widget.badge(theme, Danger, "Danger"),
				],
			),
			Widget.label(theme, "Button"),
			Widget.row(
				theme,
				[
					Widget.button(theme, Primary, "OK", []),
					Widget.button(theme, Secondary, "Cancel", []),
				],
			),
			Widget.label(theme, "Checkbox"),
			Widget.row(
				theme,
				[
					Widget.checkbox(
						theme,
						model.theme == Theme.light,
						"Theme Light",
						|checked| if checked SetTheme(Theme.light) else SetTheme(Theme.dark),
					),
					Widget.checkbox(
						theme,
						model.theme == Theme.dark,
						"Theme Dark",
						|checked| if checked SetTheme(Theme.dark) else SetTheme(Theme.light),
					),
				],
			),
			Widget.label(theme, "Toggle: ${if model.toggle_on "On" else "Off"}"),
			Widget.row(
				theme,
				[
					Widget.toggle(
						theme,
						model.toggle_on,
						|checked| SetToggle(checked),
					),
					Widget.label(theme, if model.theme == Theme.dark "Theme Dark enabled" else "Theme Dark disabled"),
				],
			),
			Widget.label(theme, "Slider: ${model.slider_value.to_str()}"),
			Widget.slider(
				theme,
				model.slider_value,
				0,
				100,
				1,
				|value| SetSliderValue(value),
			),
			Widget.label(theme, "Select"),
			Widget.select(
				theme,
				{
					open: model.select_open,
					selected: model.select_selected,
					options: ["Low", "Medium", "High"],
					on_toggle_open: |open| ToggleSelect(open),
					on_select: |index| SelectOption(index),
				},
			),
		],
	)
}

view : AppModel -> View
view = |model| {
	box(
		Auto,
		|_| style
			.background(0x242424.Color)
			.pad((model.theme.gap, model.theme.gap, model.theme.gap, model.theme.gap))
			.gap(model.theme.gap)
			.direction(Col)
			.child_align({ x: Start, y: Start })
			.font_family(model.font)
			.font_size(model.theme.font_size),
		[],
		[
			theme_card(model.theme, "Widget Demo", model),
		],
	)
}

update : AppModel, Msg -> Program.StepResult(AppModel, action, task)
update = |model, msg| {
	Program.no_work(
		match msg {
			SetSliderValue(value) => { ..model, slider_value: value }
			SetTheme(theme) => { ..model, theme: theme }
			ToggleSelect(open) => { ..model, select_open: open }
			SelectOption(index) => { ..model, select_open: False, select_selected: index }
			SetToggle(on) => { ..model, toggle_on: on }
		},
	)
}

init! : Program.Config => Try({ model : AppModel, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config| {
	ray_font = Draw.font_from_bytes!({ format: Ttf, bytes: inter_font_bytes, size: 2 * 16 }).map_err(|_| Exit(1))?
	rendering = RocRayRenderer.with_font!(ray_font)
	model = {
		theme: Theme.dark,
		font: rendering.font,
		slider_value: 45,
		select_open: False,
		select_selected: 0,
		toggle_on: False,
	}
	Ok({ model, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

config : Program.Config
config = { ..Program.default, title: "Widget Theme Showcase", width: 900, height: 520 }

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
