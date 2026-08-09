## Scrollable list demonstration.
app [Model, program] {
    rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.9.0/3sKTYuHvxSV77dDyZrxuUYgfrAarL6ZtasWMPeH32udh.tar.zst",
    tc: "../package/main.roc",
}

import rr.App
import rr.Draw
import rr.Host

import tc.Element exposing [box, text, View, style]
import tc.Program
import tc.Render
import tc.Theme

theme = Theme.light

Model : Program.State({}, Msg)

Msg : []

init! : Host => Try({}, [])
init! = |_host| Ok({})

measure_text! : Render.MeasureTextRaw => Render.TextSize
measure_text! = |config| {
	Draw.measure_text!({
		text: config.text,
		size: config.size,
		spacing: config.spacing,
		font: Draw.default_font,
	})
}

update : {}, Msg -> {}
update = |model, _msg| model

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
	rows = (1..<20).map(row).collect()
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

program : {
	init! : { config : App.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host, Draw.Frame => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
	config: App.default.with_title("Scrollable Container").with_size({ width: 720, height: 520 }),
	init!,
	view,
	update,
	measure_text!,
})
