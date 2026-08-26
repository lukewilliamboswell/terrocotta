## Rendering for the controlled single-line text input widget.
import ../Color
import ../Element exposing [View, box, text, style]
import ../Event
import ../Theme
import ../Unicode exposing [TextCursor, codepoints_to_str]

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

	## Update controlled input state from one text-input event.
	update : { value : Str, cursor : U64 }, Event.TextInputEvent -> { value : Str, cursor : U64 }
	update = |state, event| update_text_input(state, event)
}

## Update input text state.
update_text_input : { value : Str, cursor : U64 }, Event.TextInputEvent -> { value : Str, cursor : U64 }
update_text_input = |state, event| {
	var $value = state.value
	var $cursor = TextCursor.at($value, state.cursor)
	for key in event.keys {
		$value, $cursor = match key {
			KeyLeft => ($value, $cursor.previous())
			KeyRight => ($value, $cursor.next())
			KeyHome => ($value, $cursor.start())
			KeyEnd => ($value, $cursor.end())
			KeyBackspace => backspace($value, $cursor)
			KeyDelete => delete($value, $cursor)
		}
	}

	appended = codepoints_to_str(event.codepoints)
	if !appended.is_empty() {
		result = insert_text($value, $cursor, appended)
		$value = result.value
		$cursor = result.cursor
	}
	{ value: $value, cursor: $cursor.byte_offset() }
}

## Remove a byte range from a string.
remove_bytes : Str, U64, U64 -> Str
remove_bytes = |value, start, end| {
	bytes = value.to_utf8()
	before = bytes.sublist({ start: 0, len: start })
	after = bytes.sublist({ start: end, len: bytes.len() - end })
	Str.from_utf8_lossy(before.concat(after))
}

## Remove the Unicode scalar immediately before the cursor.
backspace : Str, TextCursor -> (Str, TextCursor)
backspace = |value, cursor| {
	if cursor.byte_offset() == 0 {
		(value, cursor)
	} else {
		start = cursor.previous().byte_offset()
		end = cursor.byte_offset()
		next_value = remove_bytes(value, start, end)
		(next_value, TextCursor.at(next_value, start))
	}
}

## Remove the Unicode scalar immediately after the cursor.
delete : Str, TextCursor -> (Str, TextCursor)
delete = |value, cursor| {
	if cursor.byte_offset() >= value.count_utf8_bytes() {
		(value, cursor)
	} else {
		start = cursor.byte_offset()
		end = cursor.next().byte_offset()
		next_value = remove_bytes(value, start, end)
		(next_value, TextCursor.at(next_value, start))
	}
}

## Insert text at the cursor and advance it by the inserted UTF-8 byte length.
insert_text = |value, cursor, inserted| {
	bytes = value.to_utf8()
	inserted_bytes = inserted.to_utf8()
	offset = cursor.byte_offset()
	before = bytes.sublist({ start: 0, len: offset })
	after = bytes.sublist({ start: offset, len: bytes.len() - offset })
	next_value = Str.from_utf8_lossy(before.concat(inserted_bytes).concat(after))
	{ value: next_value, cursor: TextCursor.at(next_value, offset + inserted_bytes.len()) }
}

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
