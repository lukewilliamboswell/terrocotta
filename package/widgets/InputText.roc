## Rendering for the controlled single-line text input widget.
import ../Color
import ../Element exposing [View, box, text, style]
import ../Event
import ../Theme
import unicode.ByteRange
import unicode.GeneralCategory
import unicode.Scalar

InputText :: [].{
	input_text : Theme,
	{
		id : Element.ElementId,
		state : { value : Str, cursor : U64 },
		placeholder : Str,
		on_change : { value : Str, cursor : U64 } -> msg,
	} -> View(msg)
	input_text = |theme, config| {
		state = config.state
		on_change = config.on_change
		is_empty = state.value.is_empty()
		surface = theme.palette.background.weak
		content_color = theme.palette.background.base.content

		font_color = if is_empty Color.mix(content_color, surface.fill, 112) else content_color
		content = if is_empty config.placeholder else state.value

		box(
			{
				id: config.id,
				events: [OnTextInput(Box.box(|event| on_change(InputText.update(state, event))))],
				style: |status| {
					border_color = if status.focused {
						theme.palette.primary.strong.fill
					} else {
						Color.mix(surface.fill, content_color, 70)
					}
					style
						.width(Grow({ min: theme.font_size * 6, max: 10000 }))
						.height(Fixed(theme.font_size + theme.gap))
						.background(surface.fill)
						.font_size(theme.font_size)
						.font_color(font_color)
						.text_wrap(None)
						.radius(theme.radius)
						.pad(theme.gap / 4, theme.gap / 2, theme.gap / 4, theme.gap / 2)
						.direction(Row)
						.child_align({ x: Start, y: Center })
						.overflow(Hidden, Hidden)
						.border({ color: border_color, left: 1, right: 1, top: 1, bottom: 1 })
				},
			},
			[text(content)],
		)
	}
}


## Update input text state.
update : { value : Str, cursor : U64 }, Event.TextInputEvent -> { value : Str, cursor : U64 }
update = |state, event| {
	var $next = normalize_state(state)
	for key in event.keys {
		$next = match key {
			KeyLeft => move_cursor_left($next)
			KeyRight => move_cursor_right($next)
			KeyHome => { ..$next, cursor: 0 }
			KeyEnd => { ..$next, cursor: $next.value.count_utf8_bytes() }
			KeyBackspace => backspace($next)
			KeyDelete => delete($next)
		}
	}

	appended = codepoints_to_str(event.codepoints)
	$next = if appended.is_empty() $next else insert_text($next, appended)
	$next
}

## Normalize the cursor to a valid UTF-8 scalar boundary.
normalize_state : { value : Str, cursor : U64 } -> { value : Str, cursor : U64 }
normalize_state = |state| {
	{ ..state, cursor: normalize_scalar_boundary(state.value, state.cursor) }
}

## Move the cursor to the previous Unicode scalar boundary.
move_cursor_left = |state| {
	{ ..state, cursor: previous_scalar_boundary(state.value, state.cursor) }
}

## Move the cursor to the next Unicode scalar boundary.
move_cursor_right = |state| {
	{ ..state, cursor: next_scalar_boundary(state.value, state.cursor) }
}

## Clamp a byte offset and move it backward to a Unicode scalar boundary.
normalize_scalar_boundary : Str, U64 -> U64
normalize_scalar_boundary = |value, cursor| {
	clamped = cursor.min(value.count_utf8_bytes())
	var $boundary = 0
	for located in Scalar.iter(value) {
		start = ByteRange.start(located.byte_range)
		end = ByteRange.end(located.byte_range)
		if end <= clamped {
			$boundary = end
		} else if start < clamped {
			$boundary = start
		}
	}
	$boundary
}

## Return the Unicode scalar boundary immediately before the cursor.
previous_scalar_boundary = |value, cursor| {
	normalized = normalize_scalar_boundary(value, cursor)
	var $previous = 0
	for located in Scalar.iter(value) {
		if ByteRange.end(located.byte_range) <= normalized {
			$previous = ByteRange.start(located.byte_range)
		}
	}
	$previous
}

## Return the Unicode scalar boundary immediately after the cursor.
next_scalar_boundary = |value, cursor| {
	normalized = normalize_scalar_boundary(value, cursor)
	var $next = normalized
	for located in Scalar.iter(value) {
		if ByteRange.start(located.byte_range) == normalized {
			$next = ByteRange.end(located.byte_range)
		}
	}
	$next
}

## Remove a byte range and place the cursor at the requested offset.
remove_bytes = |state, start, end, next_cursor| {
	bytes = state.value.to_utf8()
	before = bytes.sublist({ start: 0, len: start })
	after = bytes.sublist({ start: end, len: bytes.len() - end })
	{ value: Str.from_utf8_lossy(before.concat(after)), cursor: next_cursor }
}

## Remove the Unicode scalar immediately before the cursor.
backspace = |state| {
	if state.cursor == 0 {
		state
	} else {
		previous = previous_scalar_boundary(state.value, state.cursor)
		remove_bytes(state, previous, state.cursor, previous)
	}
}

## Remove the Unicode scalar immediately after the cursor.
delete = |state| {
	bytes = state.value.to_utf8()
	if state.cursor >= bytes.len() {
		state
	} else {
		next = next_scalar_boundary(state.value, state.cursor)
		remove_bytes(state, state.cursor, next, state.cursor)
	}
}

## Insert text at the cursor and advance it by the inserted UTF-8 byte length.
insert_text = |state, inserted| {
	bytes = state.value.to_utf8()
	inserted_bytes = inserted.to_utf8()
	before = bytes.sublist({ start: 0, len: state.cursor })
	after = bytes.sublist({ start: state.cursor, len: bytes.len() - state.cursor })
	{
		value: Str.from_utf8_lossy(before.concat(inserted_bytes).concat(after)),
		cursor: state.cursor + inserted_bytes.len(),
	}
}

codepoints_to_str : List(U32) -> Str
codepoints_to_str = |codepoints| codepoints.fold(
	"",
	|current, codepoint| {
		match Scalar.from_u32(codepoint) {
			Ok(scalar) => {
				if GeneralCategory.of_scalar(scalar) != Cc {
					match scalar.to_str() {
						Ok(value) => current.concat(value)
						Err(_) => current
					}
				} else {
					current
				}
			}
			Err(_) => current
		}
	},
)

text_input_event : List(U32), List(Event.TextControlKey) -> Event.TextInputEvent
text_input_event = |codepoints, keys| { codepoints, keys }

state_is = |state, value, cursor| state.value == value and state.cursor == cursor

## A batch preserves committed-codepoint order and inserts at the cursor.
expect {
	next = InputText.update(
		{ value: "ab", cursor: 1 },
		text_input_event([0xE9, 0x1F426, 99], []),
	)
	state_is(next, "aé🐦cb", 8)
}

## Movement crosses Unicode scalar boundaries rather than individual bytes.
expect {
	left = InputText.update(
		{ value: "aé🐦", cursor: 7 },
		text_input_event([], [KeyLeft]),
	)
	right = InputText.update(left, text_input_event([], [KeyRight]))
	state_is(left, "aé🐦", 3) and state_is(right, "aé🐦", 7)
}

## Backspace and Delete remove exactly one adjacent scalar.
expect {
	backspaced = InputText.update(
		{ value: "aé🐦b", cursor: 7 },
		text_input_event([], [KeyBackspace]),
	)
	deleted = InputText.update(
		{ value: "aé🐦b", cursor: 1 },
		text_input_event([], [KeyDelete]),
	)
	state_is(backspaced, "aéb", 3) and state_is(deleted, "a🐦b", 1)
}

## Boundary deletions are no-ops; Home and End set exact byte boundaries.
expect {
	at_start = { value: "é", cursor: 0 }
	at_end = { value: "é", cursor: 2 }
	backspace_start = InputText.update(at_start, text_input_event([], [KeyBackspace]))
	delete_end = InputText.update(at_end, text_input_event([], [KeyDelete]))
	home = InputText.update(at_end, text_input_event([], [KeyHome]))
	end = InputText.update(at_start, text_input_event([], [KeyEnd]))
	state_is(backspace_start, "é", 0)
		and state_is(delete_end, "é", 2)
			and home.cursor == 0
				and end.cursor == 2
}

## Single-line controls and invalid Unicode scalars are ignored.
expect {
	next = InputText.update(
		{ value: "", cursor: 0 },
		text_input_event([9, 10, 13, 0x7F, 0xD800, 0x110000, 65], []),
	)
	state_is(next, "A", 1)
}

## Stale and mid-scalar cursors normalize backward to a valid boundary.
expect {
	out_of_range = InputText.update({ value: "é", cursor: 99 }, text_input_event([], []))
	mid_scalar = InputText.update({ value: "aéb", cursor: 2 }, text_input_event([], []))
	state_is(out_of_range, "é", 2) and state_is(mid_scalar, "aéb", 1)
}

## An idle batch preserves an already valid state exactly.
expect {
	next = InputText.update({ value: "hello", cursor: 2 }, text_input_event([], []))
	state_is(next, "hello", 2)
}

InputTextTestMsg : [InputChanged({ value : Str, cursor : U64 })]

test_status : Bool -> Element.BoxStatus
test_status = |focused| { hovered: Bool.False, pressed: Bool.False, focused, disabled: Bool.False }

## Enabled inputs own the stable ID and one batched handler, and render the value.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("name"),
			state: { value: "aéb", cursor: 3 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[
			OpenBox(Id("name"), _, [OnTextInput(_)]),
			Text("aéb"),
			CloseBox,
		] => Bool.True
		_ => Bool.False
	}
}

## Focus styling changes the outer border.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("styled-name"),
			state: { value: "Roc", cursor: 3 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[OpenBox(_, outer_style, _), ..] => {
			unfocused = test_status(False)
			focused = test_status(True)
			(outer_style(unfocused)).border.color != (outer_style(focused)).border.color
		}
		_ => Bool.False
	}
}

## Empty inputs render their placeholder and retain input handling.
expect {
	view = InputText.input_text(
		Theme.dark,
		{
			id: Id("empty-name"),
			state: { value: "", cursor: 0 },
			placeholder: "Name",
			on_change: |state| InputChanged(state),
		},
	)
	match view.collect() {
		[
			OpenBox(Id("empty-name"), _, [OnTextInput(_)]),
			Text("Name"),
			CloseBox,
		] => Bool.True
		_ => Bool.False
	}
}
