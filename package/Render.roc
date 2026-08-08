## Render command types for Roc-Clay layout commands.
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
	font : U64,
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
	texture : U64,
	source : RenderRect,
	dest : RenderRect,
	origin : RenderVector2,
	rotation : F32,
	tint : Color,
}

RenderCommandRaw := [
	Rectangle({ x : F32, y : F32, width : F32, height : F32, color : Color }),
	RoundedRectangle({ x : F32, y : F32, width : F32, height : F32, radius : F32, color : Color }),
	Border(RenderBorderRaw),
	Text(RenderTextRawConfig),
	Image(RenderImageRaw),
	ScissorStart({ x : F32, y : F32, width : F32, height : F32 }),
	ScissorEnd,
]

RenderBorderRaw := {
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

RenderTextRawConfig := {
	x : F32,
	y : F32,
	text : Str,
	font_size : F32,
	spacing : F32,
	color : Color,
	font : Element.Font,
}

RenderImageRaw := {
	x : F32,
	y : F32,
	width : F32,
	height : F32,
	texture : Assets.Texture,
}

RenderMeasureTextRaw : {
	text : Str,
	size : F32,
	spacing : F32,
	font : U64,
}

RenderTextSize : { width : F32, height : F32 }

Render := [].{
	Command : RenderCommandRaw
	BorderConfig : RenderBorderRaw
	TextConfig : RenderTextRawConfig
	Vector2 : RenderVector2
	Rect : RenderRect
	TextRaw : RenderTextRaw
	RectangleRaw : RenderRectangleRaw
	RoundedRectangleRaw : RenderRoundedRectangleRaw
	RoundedRectangleLinesRaw : RenderRoundedRectangleLinesRaw
	DrawTextureRaw : RenderDrawTextureRaw
	MeasureTextRaw : RenderMeasureTextRaw
	TextSize : RenderTextSize

	draw_commands! : frame, List(Render.Command) => Try({}, [Exit(I64), ..])
		where [
			frame.rectangle! : frame,
			{
				x : F32,
				y : F32,
				width : F32,
				height : F32,
				style : {
					fill : [NoFill, Fill({ r : U8, g : U8, b : U8, a : U8 })],
					stroke : [NoStroke, Stroke({ color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 })],
				},
			} => {},
			frame.rounded_rectangle! : frame,
			{
				x : F32,
				y : F32,
				width : F32,
				height : F32,
				radius : F32,
				segments : I32,
				style : {
					fill : [NoFill, Fill({ r : U8, g : U8, b : U8, a : U8 })],
					stroke : [NoStroke, Stroke({ color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 })],
				},
			} => {},
			frame.text_at! : frame, { pos : { x : F32, y : F32 }, text : Str, size : F32, color : { r : U8, g : U8, b : U8, a : U8 } } => {},
			frame.with_scissor! : frame, { x : F32, y : F32, width : F32, height : F32 }, (frame => Try({}, [ScopeLimit, ..errors])) => Try({}, [ScopeLimit, ..errors]),
		]
	draw_commands! = |frame, commands| {
		draw_region!(frame, commands, NoScissor)?

		Ok({})
	}
}

## Draw one contiguous command region, honoring the enclosing scissor bounds.
draw_region! : frame, List(Render.Command), [NoScissor, Scissor(RenderRect)] => Try({}, [Exit(I64), ..])
	where [
		frame.rectangle! : frame,
		{
			x : F32,
			y : F32,
			width : F32,
			height : F32,
			style : {
				fill : [NoFill, Fill({ r : U8, g : U8, b : U8, a : U8 })],
				stroke : [NoStroke, Stroke({ color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 })],
			},
		} => {},
		frame.rounded_rectangle! : frame,
		{
			x : F32,
			y : F32,
			width : F32,
			height : F32,
			radius : F32,
			segments : I32,
			style : {
				fill : [NoFill, Fill({ r : U8, g : U8, b : U8, a : U8 })],
				stroke : [NoStroke, Stroke({ color : { r : U8, g : U8, b : U8, a : U8 }, thickness : F32 })],
			},
		} => {},
		frame.text_at! : frame, { pos : { x : F32, y : F32 }, text : Str, size : F32, color : { r : U8, g : U8, b : U8, a : U8 } } => {},
		frame.with_scissor! : frame, { x : F32, y : F32, width : F32, height : F32 }, (frame => Try({}, [ScopeLimit, ..errors])) => Try({}, [ScopeLimit, ..errors]),
	]
draw_region! = |frame, commands, scissor| {
	match commands {
		[] => Ok({})
		[head, .. as rest] =>
			match head {
				Rectangle(r) => {
					frame.rectangle!({
						x: r.x,
						y: r.y,
						width: r.width,
						height: r.height,
						style: { fill: Fill(to_frame_color(r.color)), stroke: NoStroke },
					})
					draw_region!(frame, rest, scissor)
				}
				RoundedRectangle(r) => {
					frame.rounded_rectangle!({
						x: r.x,
						y: r.y,
						width: r.width,
						height: r.height,
						radius: r.radius,
						segments: 12,
						style: { fill: Fill(to_frame_color(r.color)), stroke: NoStroke },
					})
					draw_region!(frame, rest, scissor)
				}
				Border(b) => {
					uniform = b.left == b.right and b.left == b.top and b.left == b.bottom
					if b.radius > 0 and uniform and b.top > 0 {
						frame.rounded_rectangle!({
							x: b.x,
							y: b.y,
							width: b.width,
							height: b.height,
							radius: b.radius,
							segments: 12,
							style: {
								fill: NoFill,
								stroke: Stroke({ color: to_frame_color(b.color), thickness: b.top }),
							},
						})
					} else {
						if b.top > 0 {
							frame.rectangle!({
								x: b.x,
								y: b.y,
								width: b.width,
								height: b.top,
								style: { fill: Fill(to_frame_color(b.color)), stroke: NoStroke },
							})
						}
						if b.bottom > 0 {
							frame.rectangle!({
								x: b.x,
								y: b.y + b.height - b.bottom,
								width: b.width,
								height: b.bottom,
								style: { fill: Fill(to_frame_color(b.color)), stroke: NoStroke },
							})
						}
						if b.left > 0 {
							frame.rectangle!({
								x: b.x,
								y: b.y,
								width: b.left,
								height: b.height,
								style: { fill: Fill(to_frame_color(b.color)), stroke: NoStroke },
							})
						}
						if b.right > 0 {
							frame.rectangle!({
								x: b.x + b.width - b.right,
								y: b.y,
								width: b.right,
								height: b.height,
								style: { fill: Fill(to_frame_color(b.color)), stroke: NoStroke },
							})
						}
					}
					draw_region!(frame, rest, scissor)
				}
				Text(t) => {
					frame.text_at!({
						pos: { x: t.x, y: t.y },
						text: t.text,
						size: t.font_size,
						color: to_frame_color(t.color),
					})
					draw_region!(frame, rest, scissor)
				}
				Image(_) => draw_region!(frame, rest, scissor)
				ScissorStart(bounds) => {
					next = match scissor {
						NoScissor => bounds
						Scissor(parent) => intersection(parent, bounds)
					}
					{ inner, after } = split_scissor(rest)
					match frame.with_scissor!(
						next,
						|scissor_frame| {
							draw_region!(scissor_frame, inner, Scissor(next)).map_err(|_| ScopeLimit)?
							Ok({})
						},
					) {
						Ok(_) => draw_region!(frame, after, scissor)
						Err(_) => Err(Exit(1))
					}
				}
				ScissorEnd => Err(Exit(1))
			}
		}
}

## Split commands following a ScissorStart into the nested region up to the
## matching ScissorEnd and the commands after it.
split_scissor : List(Render.Command) -> { inner : List(Render.Command), after : List(Render.Command) }
split_scissor = |commands| split_scissor_at(commands, 0, [])

split_scissor_at : List(Render.Command), U64, List(Render.Command) -> { inner : List(Render.Command), after : List(Render.Command) }
split_scissor_at = |commands, depth, acc| {
	match commands {
		[] => { inner: acc, after: [] }
		[ScissorStart(s), .. as rest] => split_scissor_at(rest, depth + 1, acc.append(ScissorStart(s)))
		[ScissorEnd, .. as rest] =>
			if depth == 0 {
				{ inner: acc, after: rest }
			} else {
				split_scissor_at(rest, depth - 1, acc.append(ScissorEnd))
			}
		[head, .. as rest] => split_scissor_at(rest, depth, acc.append(head))
	}
}

## Intersect a nested scissor rectangle with its active parent.
intersection : { x : F32, y : F32, width : F32, height : F32 }, { x : F32, y : F32, width : F32, height : F32 } -> { x : F32, y : F32, width : F32, height : F32 }
intersection = |a, b| {
	x = F32.max(a.x, b.x)
	y = F32.max(a.y, b.y)
	right = F32.min(a.x + a.width, b.x + b.width)
	bottom = F32.min(a.y + a.height, b.y + b.height)
	{ x, y, width: F32.max(0, right - x), height: F32.max(0, bottom - y) }
}

## Project a package color to the structural RGBA record used by the frame
## where clauses.
to_frame_color : Color -> { r : U8, g : U8, b : U8, a : U8 }
to_frame_color = |color| { r: color.r, g: color.g, b: color.b, a: color.a }
