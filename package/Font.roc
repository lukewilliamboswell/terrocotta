## Platform-independent font resources and operations.
import Color

Font := [].{

	FontMeasure : { text : Str, size : F32, spacing : F32 }

	FontDraw : {
		pos : { x : F32, y : F32 },
		text : Str,
		size : F32,
		spacing : F32,
		color : Color,
	}

	FontResource :: {
		key : U64,
		measure : Box(FontMeasure => { width : F32, height : F32 }),
		draw : Box(FontDraw => {}),
	}

	Font : [DefaultFont, CustomFont(FontResource)]

	font_key : Font.Font -> U64
	font_key = |font| match font {
		DefaultFont => 0
		CustomFont(FontResource.(resource)) => resource.key
	}

	custom_font : { key : U64, measure! : FontMeasure => { width : F32, height : F32 }, draw! : FontDraw => {} } -> Font.Font
	custom_font = |config| CustomFont(FontResource.({ key: config.key, measure: Box.box(config.measure!), draw: Box.box(config.draw!) }))

	measure_font! : FontResource, FontMeasure => { width : F32, height : F32 }
	measure_font! = |FontResource.(resource), config| (Box.unbox(resource.measure))(config)

	draw_font! : FontResource, FontDraw => {}
	draw_font! = |FontResource.(resource), config| (Box.unbox(resource.draw))(config)
}
