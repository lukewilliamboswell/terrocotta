## Settled post-solve rendering context and direct semantic host operations.
import Color
import Element
import Floating exposing [Clip.*, ZOrder.*]
import Identity exposing [NodeId]
import Layout
import LayoutTypes exposing [Bounds, LayoutNode, LayoutNodeKind.*, Placement.*, Size, VisibleRegion.*]
import Text
import rrt.Drawing
import rrt.Font
import rrt.Math

Renderer := [].{
	Bounds : LayoutTypes.Bounds

	Clip : Floating.Clip

	Placement : {
		id : NodeId,
		bounds : Bounds,
		clip : Clip,
	}

	ClipStart : {
		bounds : Bounds,
	}

	ClipEnd : {}

	BoxContext : {
		config : LayoutTypes.BoxNodeData,
		clip_scope : [
			ClipScope({
				start : ClipStart,
				end : ClipEnd,
			}),
			NoClip,
		],
	}

	TextContext : {
		config : Text.Config,
		line_count : U64,
	}

	Node : [
		Box(BoxContext),
		Text(TextContext),
		Image(LayoutTypes.ImageNodeData),
	]

	Context : {
		placement : Placement,
		paint_bounds : Bounds,
		node : Node,
	}

	Data : {
		nodes : List(LayoutNode),
		text_contents : List(Str),
		text_lines : List(Text.Line),
		child_indices : List(U64),
		node_ids : Dict(NodeId, U64),
		root_indices : List(U64),
	}

	## Draw a solved layout directly to the host frame.
	draw! : frame, Layout, Size => Try({}, [Exit(I64), ..])
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
			frame.text! : frame, Drawing.Text => {},
			frame.texture! : frame, Drawing.TextureDraw => {},
			frame.with_scissor! : frame, Math.Rect, (frame => Try({}, [ScopeLimit])) => Try({}, [ScopeLimit]),
		]
	draw! = |frame, layout, screen| draw_layout!(frame, layout, screen)

	## Draw one semantic background operation directly to the host frame.
	draw_background! : frame, Placement, LayoutTypes.BoxNodeData => {}
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		]
	draw_background! = |frame, placement, box| {
		if box.background.a > 0 {
			bounds = placement.bounds
			if box.radius > 0 {
				frame.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: box.radius,
					segments: 12,
					style: { fill: Fill(Color.to_rrt(box.background)), stroke: NoStroke },
				})
			} else {
				frame.rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					style: { fill: Fill(Color.to_rrt(box.background)), stroke: NoStroke },
				})
			}
		}
	}

	draw_text_line! : frame, Placement, Str, Text.Config, Font => {}
		where [
			frame.text! : frame, Drawing.Text => {},
		]
	draw_text_line! = |frame, placement, content, config, font| {
		draw_text : Drawing.Text
		draw_text = {
			pos: { x: placement.bounds.position.x, y: placement.bounds.position.y },
			text: content,
			size: config.font_size,
			spacing: config.spacing,
			color: Color.to_rrt(config.color),
			font,
		}
		frame.text!(draw_text)
	}

	draw_image! : frame, Placement, LayoutTypes.ImageNodeData => {}
		where [
			frame.texture! : frame, Drawing.TextureDraw => {},
		]
	draw_image! = |frame, placement, image_config| {
		bounds = placement.bounds
		texture = image_config.texture
		frame.texture!({
			texture,
			source: { x: 0, y: 0, width: texture.width, height: texture.height },
			dest: { x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: bounds.size.h },
			origin: { x: 0, y: 0 },
			rotation: 0,
			tint: Color.to_rrt(Color.white),
		})
	}

	draw_border! : frame, Placement, LayoutTypes.BoxNodeData => {}
		where [
			frame.rectangle! : frame, Drawing.Rectangle => {},
			frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		]
	draw_border! = |frame, placement, box| {
		border_config = box.border
		border_total = border_config.left + border_config.right + border_config.top + border_config.bottom
		if border_config.color.a > 0 and border_total > 0 {
			bounds = placement.bounds
			uniform = border_config.left == border_config.right and border_config.left == border_config.top and border_config.left == border_config.bottom
			if box.radius > 0 and uniform and border_config.top > 0 {
				frame.rounded_rectangle!({
					x: bounds.position.x,
					y: bounds.position.y,
					width: bounds.size.w,
					height: bounds.size.h,
					radius: box.radius,
					segments: 12,
					style: { fill: NoFill, stroke: Stroke({ color: Color.to_rrt(border_config.color), thickness: border_config.top }) },
				})
			} else {
				if border_config.top > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: bounds.size.w, height: border_config.top, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.bottom > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y + bounds.size.h - border_config.bottom, width: bounds.size.w, height: border_config.bottom, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.left > 0 {
					frame.rectangle!({ x: bounds.position.x, y: bounds.position.y, width: border_config.left, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
				if border_config.right > 0 {
					frame.rectangle!({ x: bounds.position.x + bounds.size.w - border_config.right, y: bounds.position.y, width: border_config.right, height: bounds.size.h, style: { fill: Fill(Color.to_rrt(border_config.color)), stroke: NoStroke } })
				}
			}
		}
	}
}

draw_layout! : frame, Layout, Size => Try({}, [Exit(I64), ..])
	where [
		frame.rectangle! : frame, Drawing.Rectangle => {},
		frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		frame.text! : frame, Drawing.Text => {},
		frame.texture! : frame, Drawing.TextureDraw => {},
		frame.with_scissor! : frame, Math.Rect, (frame => Try({}, [ScopeLimit])) => Try({}, [ScopeLimit]),
	]
draw_layout! = |frame, layout, screen| {
	paint_bounds = layout.compute_paint_bounds().map_err(|_| Exit(1))?
	data = layout.render_data()
	roots = Floating.roots_in_z_order(data.nodes, data.node_ids, data.root_indices, BackToFront).map_err(|_| Exit(1))?
	for root in roots {
		match root.clip {
			Unclipped => draw_node!(frame, data, root.index, screen, Unclipped, paint_bounds)?
			Clipped(bounds) => {
				scope_result = frame.with_scissor!(
					bounds_to_scissor(bounds),
					|scissor_frame| {
						draw_node!(scissor_frame, data, root.index, screen, Clipped(bounds), paint_bounds).map_err(|_| ScopeLimit)?
						Ok({})
					},
				)
				match scope_result {
					Ok(_) => {}
					Err(_) => Err(Exit(1))?
				}
			}
		}
	}
	Ok({})
}

draw_node! : frame, Renderer.Data, U64, Size, Floating.Clip, List(Bounds) => Try({}, [Exit(I64), ..])
	where [
		frame.rectangle! : frame, Drawing.Rectangle => {},
		frame.rounded_rectangle! : frame, Drawing.RoundedRectangle => {},
		frame.text! : frame, Drawing.Text => {},
		frame.texture! : frame, Drawing.TextureDraw => {},
		frame.with_scissor! : frame, Math.Rect, (frame => Try({}, [ScopeLimit])) => Try({}, [ScopeLimit]),
	]
draw_node! = |frame, data, index, screen, clip, paint_bounds| {
	node = data.nodes.get(index).map_err(|_| Exit(1))?
	subtree_paint_bounds = paint_bounds.get(index).map_err(|_| Exit(1))?
	viewport = { position: { x: 0, y: 0 }, size: screen }
	if LayoutTypes.visible_region(subtree_paint_bounds, viewport, clip) == Culled {
		Ok({})
	} else {
		context = renderer_context(data, node, clip, subtree_paint_bounds).map_err(|_| Exit(1))?
		match context.node {
			Box(box) => {
				Renderer.draw_background!(frame, context.placement, box.config)
				child_clip = effective_child_clip(context, box)
				draw_inner! = |inner_frame| {
					parent = data.nodes.get(index).map_err(|_| Exit(1))?
					for offset in 0..<parent.child_count {
						child_index = data.child_indices.get(parent.child_start + offset).map_err(|_| Exit(1))?
						draw_node!(inner_frame, data, child_index, screen, child_clip, paint_bounds)?
					}
					Renderer.draw_border!(inner_frame, context.placement, box.config)
					Ok({})
				}
				match box.clip_scope {
					NoClip => draw_inner!(frame)?
					ClipScope(_) => {
						clip_bounds = match child_clip {
							Clipped(bounds) => bounds
							Unclipped => context.placement.bounds
						}
						scope_result = frame.with_scissor!(
							bounds_to_scissor(clip_bounds),
							|scissor_frame| {
								draw_inner!(scissor_frame).map_err(|_| ScopeLimit)?
								Ok({})
							},
						)
						match scope_result {
							Ok(_) => {}
							Err(_) => Err(Exit(1))?
						}
					}
				}
			}
			Text(text) => {
				text_data_result = match node.kind {
					TextNode(text_data) => Ok(text_data)
					_ => Err(Exit(1))
				}
				text_data = text_data_result?
				content = data.text_contents.get(text_data.content_index).map_err(|_| Exit(1))?
				for line_offset in 0..<text.line_count {
					line = data.text_lines.get(text_data.lines_start + line_offset).map_err(|_| Exit(1))?
					placement = text_line_placement(context.placement, text.config, line, line_offset)
					Renderer.draw_text_line!(frame, placement, Text.line_text(content, line), text.config, text_data.font)
				}
			}
			Image(image) => Renderer.draw_image!(frame, context.placement, image)
		}
		Ok({})
	}
}

bounds_to_scissor : Bounds -> { x : F32, y : F32, width : F32, height : F32 }
bounds_to_scissor = |bounds| {
	x: bounds.position.x,
	y: bounds.position.y,
	width: bounds.size.w,
	height: bounds.size.h,
}

text_align_offset : Element.TextAlign, F32, F32 -> F32
text_align_offset = |align, box_width, text_width| match align {
	Left => 0
	Center => (box_width - text_width) * 0.5
	Right => box_width - text_width
}

text_line_placement : Renderer.Placement, Text.Config, Text.Line, U64 -> Renderer.Placement
text_line_placement = |placement, config, line, line_offset| {
	..placement,
	bounds: {
		position: {
			x: placement.bounds.position.x + text_align_offset(config.align, placement.bounds.size.w, line.width),
			y: placement.bounds.position.y + line_offset.to_f32() * line.height,
		},
		size: { w: line.width, h: line.height },
	},
}

renderer_context : Renderer.Data, LayoutNode, Floating.Clip, Bounds -> Try(Renderer.Context, Layout.LayoutError)
renderer_context = |data, node, clip, paint_bounds| {
	bounds = node_own_paint_bounds(node)
	context_node = match node.kind {
		BoxNode(box) => {
			clips = (box.overflow.x != Visible or box.overflow.y != Visible)
				and children_escape_bounds(data, node, bounds)?
			clip_scope = if clips {
				ClipScope({ start: { bounds }, end: {} })
			} else {
				NoClip
			}
			Box({ config: box, clip_scope })
		}
		TextNode(text) => Text({ config: text.config, line_count: text.lines_count })
		ImageNode(image) => Image(image)
	}
	Ok({
		placement: { id: node.id, bounds, clip },
		paint_bounds,
		node: context_node,
	})
}

effective_child_clip : Renderer.Context, Renderer.BoxContext -> Floating.Clip
effective_child_clip = |context, box| {
	if box.config.overflow.x != Visible or box.config.overflow.y != Visible {
		match context.placement.clip {
			Unclipped => Clipped(context.placement.bounds)
			Clipped(ancestor_bounds) => Clipped(ancestor_bounds.intersection(context.placement.bounds))
		}
	} else {
		context.placement.clip
	}
}

node_own_paint_bounds : LayoutNode -> Bounds
node_own_paint_bounds = |node| {
	bounds = { position: node.position, size: node.size }
	match node.placement {
		Normal => bounds
		Floating(config) => bounds.expand(config.expand)
	}
}

children_escape_bounds : Renderer.Data, LayoutNode, Bounds -> Try(Bool, Layout.LayoutError)
children_escape_bounds = |data, box_node, bounds| {
	var $escapes = Bool.False
	for offset in 0..<box_node.child_count {
		child_index = data.child_indices.get(box_node.child_start + offset)?
		if sublayout_escapes_bounds(data, child_index, bounds)? {
			$escapes = Bool.True
		}
	}
	Ok($escapes)
}

sublayout_escapes_bounds : Renderer.Data, U64, Bounds -> Try(Bool, Layout.LayoutError)
sublayout_escapes_bounds = |data, index, bounds| {
	node = data.nodes.get(index)?
	node_bounds = { position: node.position, size: node.size }
	outside = !bounds.contains_bounds(node_bounds)
	if outside {
		Ok(Bool.True)
	} else {
		match node.kind {
			BoxNode(box) => {
				child_clips = box.overflow.x != Visible or box.overflow.y != Visible
				if child_clips {
					Ok(Bool.False)
				} else {
					children_escape_bounds(data, node, bounds)
				}
			}
			_ => Ok(Bool.False)
		}
	}
}
