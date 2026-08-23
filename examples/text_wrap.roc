## Text wrapping showcase using a font loaded once from a RocRay asset store.
app [Model, Msg, program] {
	rr: platform "../../roc-ray/platform/main.roc",
	tc: "../package/main.roc",
	roc: "nightly-2026-08-21-90da19f",
}

import rr.App
import rr.Assets
import rr.Draw

import tc.Element exposing [TextWrap.*, View, box, style, text]
import tc.Font
import tc.Program
import tc.Theme

theme = Theme.light

lorem : Str
lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer non sem vitae lacus gravida facilisis. Donec porttitor, justo sed luctus feugiat, nibh lorem malesuada enim, sed pulvinar erat lectus id massa."

newline_lorem : Str
newline_lorem = "Lorem ipsum dolor sit amet.\nInteger non sem vitae lacus.\nDonec porttitor justo sed luctus."

none_lorem : Str
none_lorem = "Short raw line."

Model : Program.State(AppModel, Msg, Draw.Font)

AppModel : {}

Msg : [NoOp]

update : AppModel, Msg -> AppModel
update = |model, _msg| model

label : Str -> View(Msg, Draw.Font)
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

paragraph : TextWrap, Str -> View(Msg, Draw.Font)
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

panel : Str, TextWrap, Str -> View(Msg, Draw.Font)
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

view : AppModel -> View(Msg, Draw.Font)
view = |_model| {
	box(
		Auto,
		|_| style
			.direction(Col)
			.gap(theme.gap)
			.pad((theme.gap, theme.gap, theme.gap, theme.gap))
			.background(theme.palette.background.base.fill)
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

configure : List(Str) -> App.Config
configure = |_args| App.default.with_title("Text Wrap Example").with_size({ width: 800, height: 600 }).with_resizable(Bool.True)

init! : App.InitCallback({ model : AppModel, font : Font.Handle(Draw.Font) }, _)
init! = |_startup| {
	store = Assets.Store.open!(Assets.working_directory("examples/assets"))?
	ray_font = Draw.load_store_font!(store, { path: "Inter-Regular.ttf", size: 36 })?
	font = Font.handle(0, ray_font)
	Ok({ model: {}, font })
}

program = Program.new(configure, init!, update, view)
