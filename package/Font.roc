## A stable cache identity paired with an opaque, structurally measurable font.
import rrt.Font as RrtFont

Font := [].{
	font.Measurable :
		where [
			font.base_size : font -> F32,
			font.line_spacing : font -> F32,
			font.glyphs : font -> List(RrtFont.GlyphMetrics),
			font.get_glyph_index : font, U32 -> U64,
		]

	Handle(font) :: {
		key : U64,
		value : font,
	}.{
		key : Handle(font) -> U64
		key = |Handle.(font_handle)| font_handle.key

		value : Handle(font) -> font
		value = |Handle.(font_handle)| font_handle.value
	}

	handle : U64, font -> Handle(font)
	handle = |key, value| Handle.({ key, value })

	measure : Handle(font), RrtFont.Measure -> RrtFont.Size
		where [font.Measurable]
	measure = |font_handle, config| RrtFont.measure(font_handle.value(), config)
}
