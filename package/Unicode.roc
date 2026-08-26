## UTF-8 byte-boundary and Unicode scalar helpers.
import unicode.ByteRange
import unicode.GeneralCategory
import unicode.Scalar

Unicode := [].{

	## A cursor over Unicode scalar boundaries in a UTF-8 text value.
	ScalarCursor :: { source : Str, offset : U64 }.{

		## Create a cursor at the Nth scalar boundary. Clamps into [0, count].
		at : Str, U64 -> ScalarCursor
		at = |source, requested| {
			byte_count = source.count_utf8_bytes()
			var $offset = byte_count
			var $i = 0
			for located in Scalar.iter(source) {
				if $i == requested {
					$offset = ByteRange.start(located.byte_range)
				}
				$i = $i + 1
			}
			{ source, offset: $offset }
		}

		## Return the cursor's scalar ordinal position.
		position : ScalarCursor -> U64
		position = |cursor| {
			var $pos = 0
			for located in Scalar.iter(cursor.source) {
				if ByteRange.end(located.byte_range) <= cursor.offset {
					$pos = $pos + 1
				}
			}
			$pos
		}

		## Return the cursor's normalized UTF-8 byte offset.
		byte_offset : ScalarCursor -> U64
		byte_offset = |cursor| cursor.offset

		## Count the number of Unicode scalars in a string.
		count : Str -> U64
		count = |source| {
			var $n = 0
			for _ in Scalar.iter(source) {
				$n = $n + 1
			}
			$n
		}

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
