## Minimal counter with increment and decrement buttons.
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
import tc.Widget exposing [button]

theme = Theme.dark

Model : Program.State(AppModel, Msg)

AppModel : {
	count : I32,
}

Msg : [
	Decrement,
	Increment,
]

init! : Host => Try(AppModel, [])
init! = |_host| Ok({ count: 0 })

update : AppModel, Msg -> AppModel
update = |model, msg| match msg {
	Decrement => { ..model, count: model.count - 1 }
	Increment => { ..model, count: model.count + 1 }
}

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

## Measure layout text with the built-in font. The handle in `config.font` is
## package-local; this example only uses the default font, so every handle maps
## to the same platform font.
measure_text! : Render.MeasureTextRaw => Render.TextSize
measure_text! = |config| {
	Draw.measure_text!({
		text: config.text,
		size: config.size,
		spacing: config.spacing,
		font: Draw.default_font,
	})
}

program : {
	init! : { config : App.Config, run! : Host => Try(Model, [Exit(I64)]) },
	render! : Model, Host, Draw.Frame => Try(Model, [Exit(I64), ..]),
}
program = Program.new!({
	config: App.default.with_title("Counter Example").with_size({ width: 640, height: 420 }),
	init!,
	view,
	update,
	measure_text!,
})
