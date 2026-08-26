## UTF-8 byte-boundary and Unicode scalar helpers.
import unicode.ByteRange
import unicode.GeneralCategory
import unicode.Scalar

Unicode := [].{

	## A cursor over Unicode scalar boundaries in a UTF-8 text value.
	ScalarCursor :: { source : Str, offset : U64 }.{

		## Create a cursor at or immediately before the requested byte offset.
		at : Str, U64 -> ScalarCursor
		at = |source, requested| {
			clamped = requested.min(source.count_utf8_bytes())
			var $offset = 0
			for located in Scalar.iter(source) {
				start = ByteRange.start(located.byte_range)
				end = ByteRange.end(located.byte_range)
				if end <= clamped {
					$offset = end
				} else if start < clamped {
					$offset = start
				}
			}
			{ source, offset: $offset }
		}

		## Return the cursor's normalized UTF-8 byte offset.
		byte_offset : ScalarCursor -> U64
		byte_offset = |cursor| cursor.offset

		## Move to the previous Unicode scalar boundary.
		previous : ScalarCursor -> ScalarCursor
		previous = |cursor| {
			var $offset = 0
			for located in Scalar.iter(cursor.source) {
				if ByteRange.end(located.byte_range) <= cursor.offset {
					$offset = ByteRange.start(located.byte_range)
				}
			}
			{ ..cursor, offset: $offset }
		}

		## Move to the next Unicode scalar boundary.
		next : ScalarCursor -> ScalarCursor
		next = |cursor| {
			var $offset = cursor.offset
			for located in Scalar.iter(cursor.source) {
				if ByteRange.start(located.byte_range) == cursor.offset {
					$offset = ByteRange.end(located.byte_range)
				}
			}
			{ ..cursor, offset: $offset }
		}

		## Move to the start of the text.
		start : ScalarCursor -> ScalarCursor
		start = |cursor| { ..cursor, offset: 0 }

		## Move to the end of the text.
		end : ScalarCursor -> ScalarCursor
		end = |cursor| { ..cursor, offset: cursor.source.count_utf8_bytes() }
	}

	## Convert valid, non-control Unicode codepoints to a string.
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

}
