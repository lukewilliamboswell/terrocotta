## Text wrapping showcase with lorem ipsum paragraphs.
app [Model, Msg, program] {
	rr: platform "../../roc-ray-elm/platform/main.roc",
	tc: "../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Program as RayProgram
import tc.Color
import tc.Element exposing [Font, TextWrap.*, View, box, default_font, style, text]
import tc.Program
import tc.Render
import tc.Theme

import RocRayApp
import RocRayRenderer

theme = Theme.light

font_path : Str
font_path = "examples/assets/Inter-Regular.ttf"

lorem : Str
lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer non sem vitae lacus gravida facilisis. Donec porttitor, justo sed luctus feugiat, nibh lorem malesuada enim, sed pulvinar erat lectus id massa."

newline_lorem : Str
newline_lorem = "Lorem ipsum dolor sit amet.\nInteger non sem vitae lacus.\nDonec porttitor justo sed luctus."

none_lorem : Str
none_lorem = "Short raw line."

Model :: Program.State(AppModel, Msg, Draw.Frame, {})

AppModel : {
	font : Font,
}

Msg : [NoOp]

init! : Program.Config => Try({ model : AppModel, measure_text : Render.MeasureText, renderer : Render.Adapter(Draw.Frame, {}) }, [Exit(I64)])
init! = |_config| {
	 ray_font = Draw.load_font!({ path: font_path, size: 2 * 18 }).map_err(|_| Exit(1))?
	rendering = RocRayRenderer.with_font!(ray_font)
	Ok({ model: { font: rendering.font }, measure_text: rendering.measure_text, renderer: rendering.renderer })
}

update : AppModel, Msg -> Program.StepResult(AppModel, action, task)
update = |model, _msg| Program.no_work(model)

label : Str -> View(Msg)
label = |content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_color(theme.palette.primary.strong.fill)
			.font_size(theme.font_size)
			.text_wrap(None),
		[],
		[text(content)],
	)
}

paragraph : Element.TextWrap, Str -> View(Msg)
paragraph = |wrap_mode, content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.child_align({ x: Start, y: Start })
			.font_color(theme.palette.background.base.content)
			.font_size(theme.font_size)
			.text_wrap(wrap_mode),
		[],
		[text(content)],
	)
}

panel : Str, Element.TextWrap, Str -> View(Msg)
panel = |title, wrap_mode, content| {
	box(
		Auto,
		|_| style
			.height(Fit({ min: 0, max: 10000 }))
			.direction(Col)
			.gap(theme.gap)
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.weak.fill)
			.border({ color: theme.palette.primary.base.fill, left: 1, right: 1, top: 1, bottom: 1 })
			.radius(theme.radius),
		[],
		[
			label(title),
			paragraph(wrap_mode, content),
		],
	)
}

view : AppModel -> View(Msg)
view = |model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.gap(theme.gap)
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.base.fill)
			.font_family(model.font)
			.font_color(theme.palette.background.base.content)
			.font_size(theme.font_size),
		[],
		[
			label("Text wrapping"),
			paragraph(None, "Same lorem ipsum copy rendered with Words, Newlines, and None wrap modes."),
			box(
				Auto,
				|_| style
					.direction(Row)
					.child_align({ x: Start, y: Start })
					.gap(theme.gap),
				[],
				[
					panel("Words", Words, lorem),
					panel("Newlines", Newlines, newline_lorem),
					panel("None", None, none_lorem),
				],
			),
		],
	)
}

config : Program.Config
config = { ..Program.default, title: "Text Wrap Example", width: 800, height: 600, resizable: Bool.True }

tc_program = Program.new!({
	config,
	init!,
	render_data: Program.no_render_data,
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
