class_name StrongboxCodec
extends RefCounted

## Converts plain Godot values to JSON-safe data and back, losslessly and safely.
##
## @experimental
## [method encode] turns game state into data that [method JSON.stringify] can write.
## [method decode] turns parsed JSON back into the original values. Decoding never creates
## objects or runs code, so it is safe on untrusted save files.
## [br][br]
## Types JSON cannot hold are written as a tagged dictionary [code]{"$t": "<type>", "v": ...}[/code].
## Real numbers are written as plain JSON numbers when that is exact, and otherwise as the
## 16 hex digits of their IEEE-754 bits. See [code]docs/format.md[/code] for the full table.

## A value of an unsupported type (Object, Callable, Signal, RID, ...) was found while encoding.
const E_UNSUPPORTED_TYPE: StringName = &"E_UNSUPPORTED_TYPE"
## A Dictionary key is not a String, StringName or int.
const E_BAD_KEY: StringName = &"E_BAD_KEY"
## Nesting is deeper than the allowed maximum.
const E_TOO_DEEP: StringName = &"E_TOO_DEEP"
## The total size of strings is larger than the allowed maximum.
const E_TOO_LARGE: StringName = &"E_TOO_LARGE"
## A tagged value names a type the codec does not know.
const E_UNKNOWN_TAG: StringName = &"E_UNKNOWN_TAG"
## A tagged value has the wrong shape for its type.
const E_BAD_TAG: StringName = &"E_BAD_TAG"
## A plain value cannot be decoded (for example a fractional untagged number).
const E_BAD_VALUE: StringName = &"E_BAD_VALUE"

## Default maximum nesting depth of arrays and dictionaries.
const DEFAULT_MAX_DEPTH: int = 64
## Default maximum total size, in UTF-8 bytes, of all strings in a decoded value (32 MB).
const DEFAULT_MAX_STRING_BYTES: int = 32 * 1024 * 1024

const TAG_KEY: String = "$t"
const VALUE_KEY: String = "v"
const _SAFE_INT: int = 9007199254740992 # 2^53: larger ints are not exact as JSON numbers.
const _INT32_MIN: int = -2147483648
const _INT32_MAX: int = 2147483647
const _HEX_DIGITS: String = "0123456789abcdef"

## Types written as a flat list of real numbers, with the number of components.
const _REAL_TYPES: Dictionary = {
	TYPE_VECTOR2: 2, TYPE_VECTOR3: 3, TYPE_VECTOR4: 4, TYPE_COLOR: 4, TYPE_QUATERNION: 4,
	TYPE_RECT2: 4, TYPE_AABB: 6, TYPE_TRANSFORM2D: 6, TYPE_BASIS: 9, TYPE_TRANSFORM3D: 12,
}
## Types written as a flat list of 32-bit ints, with the number of components.
const _INT_TYPES: Dictionary = {TYPE_VECTOR2I: 2, TYPE_VECTOR3I: 3, TYPE_RECT2I: 4}
## Packed arrays of vectors, with the element type.
const _PACKED_VECTOR_TYPES: Dictionary = {
	TYPE_PACKED_VECTOR2_ARRAY: TYPE_VECTOR2,
	TYPE_PACKED_VECTOR3_ARRAY: TYPE_VECTOR3,
	TYPE_PACKED_COLOR_ARRAY: TYPE_COLOR,
}
## Tagged types other than the ones above.
const _OTHER_TAGGED: Array[int] = [
	TYPE_FLOAT, TYPE_INT, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_DICTIONARY,
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
]


## Running state of one encode or decode call.
class _Ctx extends RefCounted:
	var max_depth: int = 64
	var max_string_bytes: int = 0
	var string_bytes: int = 0
	var failed: bool = false
	var code: StringName = &""
	var message: String = ""

	func fail(error_code: StringName, error_message: String) -> void:
		if not failed:
			failed = true
			code = error_code
			message = error_message


## Encodes [param value] into JSON-safe data. On success, [member StrongboxResult.value] holds
## the data. On failure, the message names the path to the bad value, starting at [param root]
## (for example [code]body.player.weapon[/code]).
## @experimental
static func encode(value: Variant, root: String = "value", max_depth: int = DEFAULT_MAX_DEPTH) -> StrongboxResult:
	var ctx: _Ctx = _Ctx.new()
	ctx.max_depth = max_depth
	var data: Variant = _enc(value, root, 0, ctx)
	if ctx.failed:
		return StrongboxResult.failure(ctx.code, ctx.message)
	return StrongboxResult.success(data)


## Decodes data produced by [method encode], usually after [method JSON.parse_string].
## Refuses unknown tags, badly shaped tags, nesting deeper than [param max_depth] and strings
## larger than [param max_string_bytes] in total, without pushing engine errors.
## @experimental
static func decode(value: Variant, root: String = "value", max_depth: int = DEFAULT_MAX_DEPTH, max_string_bytes: int = DEFAULT_MAX_STRING_BYTES) -> StrongboxResult:
	var ctx: _Ctx = _Ctx.new()
	ctx.max_depth = max_depth
	ctx.max_string_bytes = max_string_bytes
	var data: Variant = _dec(value, root, 0, ctx)
	if ctx.failed:
		return StrongboxResult.failure(ctx.code, ctx.message)
	return StrongboxResult.success(data)


## Returns the tag name written for values of Variant type [param type].
## @experimental
static func tag_for_type(type: int) -> String:
	return type_string(type)


# ---------------------------------------------------------------- encoding

static func _enc(value: Variant, path: String, depth: int, ctx: _Ctx) -> Variant:
	var type: int = typeof(value)
	match type:
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_INT:
			return _enc_int(value)
		TYPE_FLOAT:
			return _tag(type, _enc_real(value))
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _tag(type, str(value))
		TYPE_ARRAY:
			return _enc_array(value, path, depth, ctx)
		TYPE_DICTIONARY:
			return _enc_dict(value, path, depth, ctx)
		TYPE_PACKED_BYTE_ARRAY:
			# Marshalls reports an engine error on empty input, so handle it here.
			return _tag(type, "" if value.is_empty() else Marshalls.raw_to_base64(value))
		TYPE_PACKED_INT32_ARRAY:
			return _tag(type, Array(value))
		TYPE_PACKED_STRING_ARRAY:
			return _tag(type, Array(value))
		TYPE_PACKED_INT64_ARRAY:
			var ints: Array = []
			for item: int in value:
				ints.append(_enc_int(item))
			return _tag(type, ints)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var reals: Array = []
			for item: float in value:
				reals.append(_enc_real(item))
			return _tag(type, reals)
	if _REAL_TYPES.has(type):
		return _tag(type, _enc_reals(_components(value)))
	if _INT_TYPES.has(type):
		return _tag(type, _components(value))
	if _PACKED_VECTOR_TYPES.has(type):
		var rows: Array = []
		for item: Variant in value:
			rows.append(_enc_reals(_components(item)))
		return _tag(type, rows)
	ctx.fail(E_UNSUPPORTED_TYPE, "%s: values of type %s cannot be saved." % [path, type_string(type)])
	return null


static func _enc_array(value: Array, path: String, depth: int, ctx: _Ctx) -> Variant:
	if depth >= ctx.max_depth:
		ctx.fail(E_TOO_DEEP, "%s: nesting is deeper than %d levels." % [path, ctx.max_depth])
		return null
	var out: Array = []
	for i: int in value.size():
		out.append(_enc(value[i], "%s[%d]" % [path, i], depth + 1, ctx))
		if ctx.failed:
			return null
	return out


static func _enc_dict(value: Dictionary, path: String, depth: int, ctx: _Ctx) -> Variant:
	if depth >= ctx.max_depth:
		ctx.fail(E_TOO_DEEP, "%s: nesting is deeper than %d levels." % [path, ctx.max_depth])
		return null
	var plain: bool = true
	for key: Variant in value:
		var key_type: int = typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME and key_type != TYPE_INT:
			ctx.fail(E_BAD_KEY, "%s: dictionary keys must be String, StringName or int, not %s." % [path, type_string(key_type)])
			return null
		if key_type != TYPE_STRING or key == TAG_KEY:
			plain = false
	if plain:
		var out: Dictionary = {}
		for key: String in value:
			out[key] = _enc(value[key], "%s.%s" % [path, key], depth + 1, ctx)
			if ctx.failed:
				return null
		return out
	# Escaped form: a list of [key, value] pairs, so keys keep their type and a real
	# "$t" key can never be mistaken for a tag.
	var pairs: Array = []
	for key: Variant in value:
		var item: Variant = _enc(value[key], "%s.%s" % [path, str(key)], depth + 1, ctx)
		if ctx.failed:
			return null
		pairs.append([_enc(key, path, depth + 1, ctx), item])
	return _tag(TYPE_DICTIONARY, pairs)


static func _enc_int(value: int) -> Variant:
	if value >= -_SAFE_INT and value <= _SAFE_INT:
		return value
	return _tag(TYPE_INT, _int_to_hex(value))


## Exact real numbers stay plain JSON numbers; anything else becomes its IEEE-754 bits.
static func _enc_real(value: float) -> Variant:
	if is_finite(value) and not (value == 0.0 and _sign_bit(value)):
		var round_trip: Variant = JSON.parse_string(JSON.stringify(value, "", false, true))
		if typeof(round_trip) == TYPE_FLOAT and round_trip == value:
			return value
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.reverse()
	return bytes.hex_encode()


static func _enc_reals(values: Array) -> Array:
	var out: Array = []
	for item: float in values:
		out.append(_enc_real(item))
	return out


static func _tag(type: int, payload: Variant) -> Dictionary:
	return {TAG_KEY: type_string(type), VALUE_KEY: payload}


static func _components(value: Variant) -> Array:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_QUATERNION:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_RECT2, TYPE_RECT2I:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_AABB:
			return _components(value.position) + _components(value.size)
		TYPE_TRANSFORM2D:
			return _components(value.x) + _components(value.y) + _components(value.origin)
		TYPE_BASIS:
			return _components(value.x) + _components(value.y) + _components(value.z)
		TYPE_TRANSFORM3D:
			return _components(value.basis) + _components(value.origin)
	return []


static func _build(type: int, c: Array) -> Variant:
	match type:
		TYPE_VECTOR2: return Vector2(c[0], c[1])
		TYPE_VECTOR2I: return Vector2i(c[0], c[1])
		TYPE_VECTOR3: return Vector3(c[0], c[1], c[2])
		TYPE_VECTOR3I: return Vector3i(c[0], c[1], c[2])
		TYPE_VECTOR4: return Vector4(c[0], c[1], c[2], c[3])
		TYPE_QUATERNION: return Quaternion(c[0], c[1], c[2], c[3])
		TYPE_COLOR: return Color(c[0], c[1], c[2], c[3])
		TYPE_RECT2: return Rect2(c[0], c[1], c[2], c[3])
		TYPE_RECT2I: return Rect2i(c[0], c[1], c[2], c[3])
		TYPE_AABB: return AABB(Vector3(c[0], c[1], c[2]), Vector3(c[3], c[4], c[5]))
		TYPE_TRANSFORM2D: return Transform2D(Vector2(c[0], c[1]), Vector2(c[2], c[3]), Vector2(c[4], c[5]))
		TYPE_BASIS: return Basis(Vector3(c[0], c[1], c[2]), Vector3(c[3], c[4], c[5]), Vector3(c[6], c[7], c[8]))
		TYPE_TRANSFORM3D:
			return Transform3D(Basis(Vector3(c[0], c[1], c[2]), Vector3(c[3], c[4], c[5]), Vector3(c[6], c[7], c[8])), Vector3(c[9], c[10], c[11]))
	return null


static func _sign_bit(value: float) -> bool:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return (bytes[7] & 0x80) != 0


static func _int_to_hex(value: int) -> String:
	if value == 0:
		return "0"
	var negative: bool = value < 0
	var digits: String = ""
	var rest: int = value
	while rest != 0:
		digits = _HEX_DIGITS[absi(rest % 16)] + digits
		@warning_ignore("integer_division")
		rest = rest / 16
	return ("-" + digits) if negative else digits


# ---------------------------------------------------------------- decoding

static func _dec(value: Variant, path: String, depth: int, ctx: _Ctx) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return value
		TYPE_STRING:
			_count(value, path, ctx)
			return value
		TYPE_INT:
			return value
		TYPE_FLOAT:
			if is_finite(value) and value == floorf(value) and absf(value) <= float(_SAFE_INT):
				return int(value)
			ctx.fail(E_BAD_VALUE, "%s: untagged numbers must be whole and at most 2^53; floats must be tagged." % path)
			return null
		TYPE_ARRAY:
			if depth >= ctx.max_depth:
				ctx.fail(E_TOO_DEEP, "%s: nesting is deeper than %d levels." % [path, ctx.max_depth])
				return null
			var out: Array = []
			for i: int in value.size():
				out.append(_dec(value[i], "%s[%d]" % [path, i], depth + 1, ctx))
				if ctx.failed:
					return null
			return out
		TYPE_DICTIONARY:
			if value.has(TAG_KEY):
				return _dec_tag(value, path, depth, ctx)
			if depth >= ctx.max_depth:
				ctx.fail(E_TOO_DEEP, "%s: nesting is deeper than %d levels." % [path, ctx.max_depth])
				return null
			var out: Dictionary = {}
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					ctx.fail(E_BAD_VALUE, "%s: plain dictionary keys must be strings." % path)
					return null
				_count(key, path, ctx)
				out[key] = _dec(value[key], "%s.%s" % [path, key], depth + 1, ctx)
				if ctx.failed:
					return null
			return out
	ctx.fail(E_BAD_VALUE, "%s: %s is not valid JSON data." % [path, type_string(typeof(value))])
	return null


static func _dec_tag(tagged: Dictionary, path: String, depth: int, ctx: _Ctx) -> Variant:
	var tag: Variant = tagged[TAG_KEY]
	if tagged.size() != 2 or not tagged.has(VALUE_KEY) or typeof(tag) != TYPE_STRING:
		ctx.fail(E_BAD_TAG, "%s: a tagged value must have exactly the keys \"$t\" (a string) and \"v\"." % path)
		return null
	var type: int = _type_for_tag(tag)
	if type == TYPE_NIL:
		ctx.fail(E_UNKNOWN_TAG, "%s: unknown tag \"%s\"." % [path, tag])
		return null
	var v: Variant = tagged[VALUE_KEY]
	var bad: String = "%s: bad payload for tag \"%s\"." % [path, tag]
	match type:
		TYPE_FLOAT:
			return _dec_real(v, bad, ctx)
		TYPE_INT:
			return _dec_int(v, bad, ctx)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			if typeof(v) != TYPE_STRING:
				ctx.fail(E_BAD_TAG, bad)
				return null
			_count(v, path, ctx)
			if type == TYPE_STRING_NAME:
				return StringName(v)
			return NodePath(v)
		TYPE_DICTIONARY:
			return _dec_pairs(v, path, depth, ctx)
		TYPE_PACKED_BYTE_ARRAY:
			if typeof(v) != TYPE_STRING or v.length() % 4 != 0 or not _matches(v, "^[A-Za-z0-9+/]*={0,2}$"):
				ctx.fail(E_BAD_TAG, bad)
				return null
			_count(v, path, ctx)
			return PackedByteArray() if v == "" else Marshalls.base64_to_raw(v)
	if typeof(v) != TYPE_ARRAY:
		ctx.fail(E_BAD_TAG, bad)
		return null
	if _REAL_TYPES.has(type) or _INT_TYPES.has(type):
		var parts: Variant = _dec_parts(v, type, bad, ctx)
		return null if ctx.failed else _build(type, parts)
	var items: Array = v
	match type:
		TYPE_PACKED_INT32_ARRAY:
			var out32: PackedInt32Array = PackedInt32Array()
			for item: Variant in items:
				var n: Variant = _dec_int32(item, bad, ctx)
				if ctx.failed:
					return null
				out32.append(n)
			return out32
		TYPE_PACKED_INT64_ARRAY:
			var out64: PackedInt64Array = PackedInt64Array()
			for item: Variant in items:
				var n: Variant = _dec_int_any(item, bad, ctx)
				if ctx.failed:
					return null
				out64.append(n)
			return out64
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var reals: Array = []
			for item: Variant in items:
				var f: Variant = _dec_real(item, bad, ctx)
				if ctx.failed:
					return null
				reals.append(f)
			if type == TYPE_PACKED_FLOAT32_ARRAY:
				return PackedFloat32Array(reals)
			return PackedFloat64Array(reals)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = PackedStringArray()
			for item: Variant in items:
				if typeof(item) != TYPE_STRING:
					ctx.fail(E_BAD_TAG, bad)
					return null
				_count(item, path, ctx)
				strings.append(item)
			return strings
	# Packed vector arrays: a list of component lists.
	var element: int = _PACKED_VECTOR_TYPES[type]
	var out: Array = []
	for item: Variant in items:
		if typeof(item) != TYPE_ARRAY:
			ctx.fail(E_BAD_TAG, bad)
			return null
		var parts: Variant = _dec_parts(item, element, bad, ctx)
		if ctx.failed:
			return null
		out.append(_build(element, parts))
	match type:
		TYPE_PACKED_VECTOR2_ARRAY: return PackedVector2Array(out)
		TYPE_PACKED_VECTOR3_ARRAY: return PackedVector3Array(out)
	return PackedColorArray(out)


static func _dec_pairs(v: Variant, path: String, depth: int, ctx: _Ctx) -> Variant:
	if depth >= ctx.max_depth:
		ctx.fail(E_TOO_DEEP, "%s: nesting is deeper than %d levels." % [path, ctx.max_depth])
		return null
	if typeof(v) != TYPE_ARRAY:
		ctx.fail(E_BAD_TAG, "%s: an escaped Dictionary must hold a list of [key, value] pairs." % path)
		return null
	var out: Dictionary = {}
	for pair: Variant in v:
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			ctx.fail(E_BAD_TAG, "%s: an escaped Dictionary must hold a list of [key, value] pairs." % path)
			return null
		var key: Variant = _dec(pair[0], path, depth + 1, ctx)
		if ctx.failed:
			return null
		var key_type: int = typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME and key_type != TYPE_INT:
			ctx.fail(E_BAD_TAG, "%s: dictionary keys must be String, StringName or int." % path)
			return null
		out[key] = _dec(pair[1], "%s.%s" % [path, str(key)], depth + 1, ctx)
		if ctx.failed:
			return null
	return out


static func _dec_parts(v: Array, type: int, bad: String, ctx: _Ctx) -> Variant:
	var is_int: bool = _INT_TYPES.has(type)
	var count: int = _INT_TYPES[type] if is_int else _REAL_TYPES[type]
	if v.size() != count:
		ctx.fail(E_BAD_TAG, bad)
		return null
	var parts: Array = []
	for item: Variant in v:
		parts.append(_dec_int32(item, bad, ctx) if is_int else _dec_real(item, bad, ctx))
		if ctx.failed:
			return null
	return parts


static func _dec_real(v: Variant, bad: String, ctx: _Ctx) -> Variant:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			return float(v)
		TYPE_STRING:
			if _matches(v, "^[0-9a-f]{16}$"):
				var bytes: PackedByteArray = v.hex_decode()
				bytes.reverse()
				return bytes.decode_double(0)
	ctx.fail(E_BAD_TAG, bad)
	return null


## A plain whole number, as written for ints up to 2^53.
static func _dec_plain_int(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v) and absf(v) <= float(_SAFE_INT):
		return int(v)
	return null


static func _dec_int32(v: Variant, bad: String, ctx: _Ctx) -> Variant:
	var n: Variant = _dec_plain_int(v)
	if n == null or n < _INT32_MIN or n > _INT32_MAX:
		ctx.fail(E_BAD_TAG, bad)
		return null
	return n


## A PackedInt64Array element: a plain whole number or an "int" tag.
static func _dec_int_any(v: Variant, bad: String, ctx: _Ctx) -> Variant:
	var n: Variant = _dec_plain_int(v)
	if n != null:
		return n
	if typeof(v) == TYPE_DICTIONARY and v.size() == 2 and v.has(VALUE_KEY):
		var tag: Variant = v.get(TAG_KEY)
		if typeof(tag) == TYPE_STRING and tag == "int":
			return _dec_int(v[VALUE_KEY], bad, ctx)
	ctx.fail(E_BAD_TAG, bad)
	return null


## Parses a signed hex string into an int, refusing anything outside the 64-bit range.
static func _dec_int(v: Variant, bad: String, ctx: _Ctx) -> Variant:
	if typeof(v) != TYPE_STRING or not _matches(v, "^-?[0-9a-f]{1,16}$"):
		ctx.fail(E_BAD_TAG, bad)
		return null
	var text: String = v
	var negative: bool = text.begins_with("-")
	var digits: String = text.substr(1) if negative else text
	# Accumulate as a negative number so the minimum int64 does not overflow.
	var acc: int = 0
	var limit: int = -9223372036854775807 - 1
	for ch: String in digits:
		var d: int = _HEX_DIGITS.find(ch)
		@warning_ignore("integer_division")
		if acc < (limit + d) / 16:
			ctx.fail(E_BAD_TAG, bad)
			return null
		acc = acc * 16 - d
	if not negative:
		if acc == limit:
			ctx.fail(E_BAD_TAG, bad)
			return null
		return -acc
	return acc


static var _tag_types: Dictionary = {}


static func _type_for_tag(tag: String) -> int:
	if _tag_types.is_empty():
		for type: int in _REAL_TYPES.keys() + _INT_TYPES.keys() + _PACKED_VECTOR_TYPES.keys() + _OTHER_TAGGED:
			_tag_types[type_string(type)] = type
	return _tag_types.get(tag, TYPE_NIL)


static func _count(text: String, path: String, ctx: _Ctx) -> void:
	ctx.string_bytes += text.to_utf8_buffer().size()
	if ctx.string_bytes > ctx.max_string_bytes:
		ctx.fail(E_TOO_LARGE, "%s: strings are larger than %d bytes in total." % [path, ctx.max_string_bytes])


static func _matches(text: String, pattern: String) -> bool:
	var regex: RegEx = RegEx.create_from_string(pattern)
	return regex.search(text) != null
