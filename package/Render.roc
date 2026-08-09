## Platform-independent render commands and adapter.
##
## Terracotta owns layout and command generation. Application initialization
## supplies a pure text measurer separately from one command-rendering closure.
## That closure receives the compact frame data paired with commands, performs
## any pre-render writes, and then replays commands while retaining its opaque
## ARC-owned fonts, textures, shaders, and uniforms exactly once.
import Assets
import Color
import Element

RenderVector2 : { x : F32, y : F32 }

RenderRect : { x : F32, y : F32, width : F32, height : F32 }

RenderTextRaw : {
	pos : RenderVector2,
	text : Str,
	size : F32,
	spacing : F32,
	color : Color,
	font : Element.Font,
}

RenderRectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	color : Color,
}

RenderRoundedRectangleRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	segments : I32,
	color : Color,
}

RenderRoundedRectangleLinesRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	segments : I32,
	color : Color,
	thickness : F32,
}

RenderDrawTextureRaw : {
	texture : Assets.Texture,
	source : RenderRect,
	dest : RenderRect,
	origin : RenderVector2,
	rotation : F32,
	tint : Color,
}

RenderTextureQuadRaw : {
	texture : Assets.Texture,
	top_left : RenderVector2,
	bottom_left : RenderVector2,
	bottom_right : RenderVector2,
	top_right : RenderVector2,
	tint : Color,
}

RenderCanvasRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	view_width : F32,
	view_height : F32,
	texture_quads : List(Element.CanvasTextureQuad),
	underlay_lines : List(Element.CanvasLine),
	overlay_texture_quads : List(Element.CanvasTextureQuad),
	radial_gradients : List(Element.CanvasRadialGradient),
	lines : List(Element.CanvasLine),
	circles : List(Element.CanvasCircle),
}

RenderShadowRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	color : Color,
	offset_x : F32,
	offset_y : F32,
	blur : F32,
	spread : F32,
}

RenderCommandRaw : [
	Rectangle(RenderRectangleRaw),
	RoundedRectangle(RenderRoundedRectangleRaw),
	Shadow(RenderShadowRaw),
	Border(RenderBorderRaw),
	Text(RenderTextRawConfig),
	Image(RenderImageRaw),
	Canvas(RenderCanvasRaw),
	ScissorStart(RenderRect),
	ScissorEnd,
]

RenderBorderRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	radius : F32,
	color : Color,
	left : F32,
	right : F32,
	top : F32,
	bottom : F32,
}

RenderTextRawConfig : {
	x : F32,
	y : F32,
	text : Str,
	font_size : F32,
	spacing : F32,
	color : Color,
	font : Element.Font,
}

RenderImageRaw : {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	texture : Assets.Texture,
	tint : Color,
}

RenderMeasureTextRaw : {
	text : Str,
	size : F32,
	spacing : F32,
	font : Element.Font,
}

RenderTextSize : { width : F32, height : F32 }

## Scalar observations paired with one retained command list. This is plain
## data, so the renderer can use it without the UI runtime retaining an app
## model or a host capability.
RenderFrameRaw : {
	delta_seconds : F32,
	timestamp_nanos : U64,
	screen : { width : F32, height : F32 },
}

## Renderer whose draw callback receives a platform-owned per-frame capability.
## It owns both pre-render work and command replay so resource-heavy renderer
## state has one closure owner. Pure measurement belongs to a separate
## `MeasureText` value so layout never retains GPU resources.
RenderAdapter(draw_frame, data) : {
	render! : draw_frame, data, RenderFrameRaw, List(RenderCommandRaw) => {},
}

Render := [].{
	Command : RenderCommandRaw
	BorderConfig : RenderBorderRaw
	TextConfig : RenderTextRawConfig
	ImageConfig : RenderImageRaw
	Vector2 : RenderVector2
	Rect : RenderRect
	TextRaw : RenderTextRaw
	RectangleRaw : RenderRectangleRaw
	RoundedRectangleRaw : RenderRoundedRectangleRaw
	RoundedRectangleLinesRaw : RenderRoundedRectangleLinesRaw
	DrawTextureRaw : RenderDrawTextureRaw
	TextureQuadRaw : RenderTextureQuadRaw
	CanvasRaw : RenderCanvasRaw
	ShadowRaw : RenderShadowRaw
	MeasureTextRaw : RenderMeasureTextRaw
	TextSize : RenderTextSize
	Frame : RenderFrameRaw

	## Pure text measurer retained by `Layout` and its cache. Keep its captures
	## limited to metrics/data, never the renderer or its host resources.
	MeasureText : RenderMeasureTextRaw -> RenderTextSize
	Adapter(draw_frame, data) : RenderAdapter(draw_frame, data)

	rectangle : { x : F32, y : F32, width : F32, height : F32, color : Color } -> Command
	rectangle = |config| {
		payload : RenderRectangleRaw
		payload = config
		Rectangle(payload)
	}

	rounded_rectangle : { x : F32, y : F32, width : F32, height : F32, radius : F32, color : Color } -> Command
	rounded_rectangle = |config| {
		payload : RenderRoundedRectangleRaw
		payload = {
			x: config.x,
			y: config.y,
			width: config.width,
			height: config.height,
			radius: config.radius,
			segments: 12,
			color: config.color,
		}
		RoundedRectangle(payload)
	}

	border : { x : F32, y : F32, width : F32, height : F32, radius : F32, color : Color, left : F32, right : F32, top : F32, bottom : F32 } -> Command
	border = |config| {
		payload : RenderBorderRaw
		payload = config
		Border(payload)
	}

	text : { x : F32, y : F32, text : Str, font_size : F32, spacing : F32, color : Color, font : Element.Font } -> Command
	text = |config| {
		payload : RenderTextRawConfig
		payload = config
		Text(payload)
	}

	image : { x : F32, y : F32, width : F32, height : F32, texture : Assets.Texture, tint : Color } -> Command
	image = |config| {
		payload : RenderImageRaw
		payload = config
		Image(payload)
	}

	canvas : { x : F32, y : F32, width : F32, height : F32, view_width : F32, view_height : F32, texture_quads : List(Element.CanvasTextureQuad), underlay_lines : List(Element.CanvasLine), overlay_texture_quads : List(Element.CanvasTextureQuad), radial_gradients : List(Element.CanvasRadialGradient), lines : List(Element.CanvasLine), circles : List(Element.CanvasCircle) } -> Command
	canvas = |config| {
		payload : RenderCanvasRaw
		payload = config
		Canvas(payload)
	}

	shadow : RenderShadowRaw -> Command
	shadow = |config| {
		Shadow(config)
	}

	scissor_start : { x : F32, y : F32, width : F32, height : F32 } -> Command
	scissor_start = |bounds| {
		payload : RenderRect
		payload = bounds
		ScissorStart(payload)
	}

	scissor_end : Command
	scissor_end = ScissorEnd

	adapter : RenderAdapter(draw_frame, data) -> Adapter(draw_frame, data)
	adapter = |value| value

	render! : Adapter(draw_frame, data), draw_frame, data, Frame, List(Command) => {}
	render! = |adapter_value, draw_frame_value, data_value, frame_value, commands| {
		raw_adapter : RenderAdapter(draw_frame, data)
		raw_adapter = adapter_value
		render_commands! = raw_adapter.render!
		render_commands!(draw_frame_value, data_value, frame_value, commands)
	}

	intersect : Rect, Rect -> Rect
	intersect = |a, b| intersection(a, b)
}

## Intersect a nested scissor rectangle with its active parent.
intersection : RenderRect, RenderRect -> RenderRect
intersection = |a, b| {
	x = F32.max(a.x, b.x)
	y = F32.max(a.y, b.y)
	right = F32.min(a.x + a.width, b.x + b.width)
	bottom = F32.min(a.y + a.height, b.y + b.height)
	width = F32.max(0, right - x)
	height = F32.max(0, bottom - y)
	{ x, y, width, height }
}
