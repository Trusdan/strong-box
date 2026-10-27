extends GutTest

## StrongboxCodec: lossless round trips, refusals with paths, escaping and limits.

const SAFE: int = 9007199254740992 # 2^53
const I64_MAX: int = 9223372036854775807
const I64_MIN: int = -9223372036854775807 - 1


## Encodes, writes real JSON text, parses it back and decodes.
func _through_json(value: Variant) -> StrongboxResult:
	var enc: StrongboxResult = StrongboxCodec.encode(value)
	if not enc.ok:
		return enc
	var text: String = JSON.stringify(enc.value, "", true, true)
	return StrongboxCodec.decode(JSON.parse_string(text))


## Exact comparison: same Variant type at every level, floats compared bit for bit.
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			var x: PackedByteArray = PackedFloat64Array([a]).to_byte_array()
			var y: PackedByteArray = PackedFloat64Array([b]).to_byte_array()
			return x == y
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i: int in a.size():
				if not _same(a[i], b[i]):
					return false
			return true
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key: Variant in a:
				if not b.has(key) or not _same(a[key], b[key]):
					return false
			for key: Variant in b:
				var found: bool = false
				for other: Variant in a:
					if typeof(other) == typeof(key) and other == key:
						found = true
				if not found:
					return false
			return true
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if a.size() != b.size():
				return false
			for i: int in a.size():
				if not _same(float(a[i]), float(b[i])):
					return false
			return true
	return a == b


func _assert_round_trip(value: Variant, label: String) -> void:
	var direct: StrongboxResult = StrongboxCodec.encode(value)
	assert_true(direct.ok, "%s: encode failed: %s" % [label, direct])
	if not direct.ok:
		return
	var back: StrongboxResult = StrongboxCodec.decode(direct.value)
	assert_true(back.ok, "%s: decode failed: %s" % [label, back])
	assert_true(_same(back.value, value), "%s: in-memory round trip changed the value: %s -> %s" % [label, value, back.value])
	var json: StrongboxResult = _through_json(value)
	assert_true(json.ok, "%s: JSON round trip failed: %s" % [label, json])
	assert_true(_same(json.value, value), "%s: JSON round trip changed the value: %s -> %s" % [label, value, json.value])


func _all_types() -> Dictionary:
	return {
		"null": null, "true": true, "false": false,
		"int 0": 0, "int -1": -1, "int 2^53": SAFE, "int -2^53": -SAFE,
		"int 2^53+1": SAFE + 1, "int -(2^53+1)": -SAFE - 1, "int 2^62": 1 << 62, "int -2^62": -(1 << 62),
		"int64 max": I64_MAX, "int64 min": I64_MIN,
		"float 0": 0.0, "float -0": -0.0, "float 1": 1.0, "float 0.1": 0.1, "float 1/3": 1.0 / 3.0,
		"float 17 digits": 123456789.123456789, "float 1e300": 1e300, "float min subnormal": 5e-324,
		"float nan": NAN, "float inf": INF, "float -inf": -INF,
		"empty string": "", "unicode": "Hub — Cellar ✓ 日本語 😀 ñ",
		"string name": &"cellar_chest", "node path": ^"Cellar/Chest:opened",
		"Vector2": Vector2(0.1, -2.5), "Vector2i": Vector2i(-2147483648, 2147483647),
		"Vector3": Vector3(1.0 / 3.0, -0.0, 1e30), "Vector3i": Vector3i(1, -2, 3),
		"Vector4": Vector4(0.25, 0.1, -7, 9), "Color": Color(0.1, 0.2, 0.3, 0.4),
		"Quaternion": Quaternion(0.1, 0.2, 0.3, 0.9), "Basis": Basis(Vector3.UP, 0.7),
		"Transform2D": Transform2D(0.3, Vector2(10.5, -3)), "Transform3D": Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(1, 2, 3)),
		"Rect2": Rect2(0.5, 1.5, 10, 20), "Rect2i": Rect2i(-1, 2, 30, 40), "AABB": AABB(Vector3(0.1, 0.2, 0.3), Vector3(1, 2, 3)),
		"empty array": [], "empty dict": {},
		"PackedByteArray": PackedByteArray([0, 1, 127, 128, 255]), "empty PackedByteArray": PackedByteArray(),
		"PackedInt32Array": PackedInt32Array([-2147483648, 0, 2147483647]),
		"PackedInt64Array": PackedInt64Array([I64_MIN, -SAFE - 1, 0, SAFE, I64_MAX]),
		"PackedFloat32Array": PackedFloat32Array([0.1, -0.0, 3.4e38]),
		"PackedFloat64Array": PackedFloat64Array([0.1, -0.0, NAN, INF, 5e-324]),
		"PackedStringArray": PackedStringArray(["Hub", "", "😀"]),
		"PackedVector2Array": PackedVector2Array([Vector2(0.1, 0.2), Vector2(-1, 1e20)]),
		"PackedVector3Array": PackedVector3Array([Vector3(0.1, 0.2, 0.3)]),
		"PackedColorArray": PackedColorArray([Color(0.1, 0.2, 0.3, 0.4), Color.BLACK]),
	}


func test_round_trip_every_allowed_type() -> void:
	var cases: Dictionary = _all_types()
	for label: String in cases:
		_assert_round_trip(cases[label], label)


func test_round_trip_nested_mix() -> void:
	var cellar: Dictionary = {
		"chest": {"opened": true, "position": Vector3(1.5, 0, -2.25), "items": [&"coin", 3, 0.1]},
		"lever": {"on": false, "angle": -0.0},
		"coins": PackedVector2Array([Vector2(1, 2)]),
		"visits": {1: "first", 2: "second", SAFE + 5: "big"},
		&"name_key": "string name key",
		"$t": "a real key that looks like a tag",
		"deep": [[[{"x": [Color.RED, NodePath("Hub/Door")]}]]],
	}
	_assert_round_trip(cellar, "nested mix")
	_assert_round_trip({"Hub": cellar, "list": [cellar, [], {}]}, "nested twice")


func test_typed_array_saves_as_plain_array() -> void:
	var typed: Array[int] = [1, 2, 3]
	var result: StrongboxResult = _through_json(typed)
	assert_true(result.ok)
	assert_eq(typeof(result.value), TYPE_ARRAY)
	assert_eq(result.value, [1, 2, 3])


func test_user_dictionary_that_looks_like_a_tag_stays_a_dictionary() -> void:
	var fake: Dictionary = {"$t": "Vector2", "v": [1, 2]}
	var result: StrongboxResult = _through_json(fake)
	assert_true(result.ok)
	assert_eq(typeof(result.value), TYPE_DICTIONARY, "must not turn into a Vector2")
	assert_true(_same(result.value, fake))


func test_floats_are_always_tagged() -> void:
	var enc: StrongboxResult = StrongboxCodec.encode(1.0)
	assert_eq(enc.value, {"$t": "float", "v": 1.0})
	assert_eq(StrongboxCodec.encode(-0.0).value, {"$t": "float", "v": "8000000000000000"})
	assert_eq(StrongboxCodec.encode(SAFE).value, SAFE, "ints up to 2^53 stay plain numbers")
	assert_eq(StrongboxCodec.encode(SAFE + 1).value, {"$t": "int", "v": "20000000000001"})


func test_refuses_unsupported_types_with_path() -> void:
	var holder: RefCounted = RefCounted.new()
	var cases: Dictionary = {
		"Object": [{"player": {"weapon": holder}}, "body.player.weapon"],
		"Callable": [{"items": [1, 2, Callable(self, "_same")]}, "body.items[2]"],
		"Signal": [[{"s": Signal(self, "ready")}], "body[0].s"],
		"RID": [{"r": RID()}, "body.r"],
		"Vector4i": [Vector4i(1, 2, 3, 4), "body"],
		"Plane": [{"p": Plane()}, "body.p"],
		"PackedVector4Array": [{"a": PackedVector4Array()}, "body.a"],
	}
	for label: String in cases:
		var result: StrongboxResult = StrongboxCodec.encode(cases[label][0], "body")
		assert_false(result.ok, "%s should be refused" % label)
		assert_eq(result.code, StrongboxCodec.E_UNSUPPORTED_TYPE, label)
		assert_string_contains(result.message, cases[label][1], false)


func test_refuses_bad_dictionary_keys() -> void:
	var result: StrongboxResult = StrongboxCodec.encode({"room": {Vector2(1, 1): "tile"}}, "body")
	assert_false(result.ok)
	assert_eq(result.code, StrongboxCodec.E_BAD_KEY)
	assert_string_contains(result.message, "body.room", false)


func test_decode_refuses_unknown_and_bad_tags() -> void:
	var cases: Dictionary = {
		"unknown tag": [{"$t": "Object", "v": {}}, StrongboxCodec.E_UNKNOWN_TAG],
		"tag not a string": [{"$t": 5, "v": 1}, StrongboxCodec.E_BAD_TAG],
		"extra key": [{"$t": "Vector2", "v": [1, 2], "x": 1}, StrongboxCodec.E_BAD_TAG],
		"missing v": [{"$t": "Vector2"}, StrongboxCodec.E_BAD_TAG],
		"wrong count": [{"$t": "Vector3", "v": [1, 2]}, StrongboxCodec.E_BAD_TAG],
		"string component": [{"$t": "Vector2", "v": [1, "x"]}, StrongboxCodec.E_BAD_TAG],
		"bad float bits": [{"$t": "float", "v": "zz"}, StrongboxCodec.E_BAD_TAG],
		"float as object": [{"$t": "float", "v": {}}, StrongboxCodec.E_BAD_TAG],
		"bad base64": [{"$t": "PackedByteArray", "v": "@@@@"}, StrongboxCodec.E_BAD_TAG],
		"Vector2i out of int32": [{"$t": "Vector2i", "v": [2147483648, 0]}, StrongboxCodec.E_BAD_TAG],
		"Vector2i fraction": [{"$t": "Vector2i", "v": [1.5, 0]}, StrongboxCodec.E_BAD_TAG],
		"int tag overflow": [{"$t": "int", "v": "8000000000000000"}, StrongboxCodec.E_BAD_TAG],
		"int tag too long": [{"$t": "int", "v": "10000000000000000"}, StrongboxCodec.E_BAD_TAG],
		"int tag not hex": [{"$t": "int", "v": "12g"}, StrongboxCodec.E_BAD_TAG],
		"pairs not a list": [{"$t": "Dictionary", "v": {}}, StrongboxCodec.E_BAD_TAG],
		"pair wrong size": [{"$t": "Dictionary", "v": [[1]]}, StrongboxCodec.E_BAD_TAG],
		"pair bad key": [{"$t": "Dictionary", "v": [[true, 1]]}, StrongboxCodec.E_BAD_TAG],
		"untagged fraction": [1.5, StrongboxCodec.E_BAD_VALUE],
		"untagged huge number": [1e300, StrongboxCodec.E_BAD_VALUE],
		"non-JSON type": [Vector2(1, 2), StrongboxCodec.E_BAD_VALUE],
	}
	for label: String in cases:
		var result: StrongboxResult = StrongboxCodec.decode(cases[label][0])
		assert_false(result.ok, "%s should be refused" % label)
		assert_eq(result.code, cases[label][1], label)


func test_decode_accepts_int64_min_tag() -> void:
	var result: StrongboxResult = StrongboxCodec.decode({"$t": "int", "v": "-8000000000000000"})
	assert_true(result.ok)
	assert_eq(result.value, I64_MIN)


func _nested(levels: int) -> Variant:
	var value: Variant = 1
	for i: int in levels:
		value = [value] if i % 2 == 0 else {"k": value}
	return value


func test_depth_limit() -> void:
	assert_true(StrongboxCodec.encode(_nested(64)).ok, "64 levels are allowed")
	var too_deep: StrongboxResult = StrongboxCodec.encode(_nested(65))
	assert_eq(too_deep.code, StrongboxCodec.E_TOO_DEEP)
	assert_true(StrongboxCodec.decode(_nested(64)).ok)
	assert_eq(StrongboxCodec.decode(_nested(65)).code, StrongboxCodec.E_TOO_DEEP)
	assert_eq(StrongboxCodec.decode(_nested(5), "value", 4).code, StrongboxCodec.E_TOO_DEEP, "limit is configurable")


func test_self_containing_array_is_refused_not_a_crash() -> void:
	var loop: Array = []
	loop.append(loop)
	assert_eq(StrongboxCodec.encode(loop).code, StrongboxCodec.E_TOO_DEEP)
	loop.clear()


func test_string_size_limit() -> void:
	var data: Dictionary = {"note": "x".repeat(600), "names": PackedStringArray(["y".repeat(600)])}
	var encoded: Variant = StrongboxCodec.encode(data).value
	assert_true(StrongboxCodec.decode(encoded, "value", 64, 2000).ok)
	var result: StrongboxResult = StrongboxCodec.decode(encoded, "value", 64, 1000)
	assert_eq(result.code, StrongboxCodec.E_TOO_LARGE, "limit is configurable and counts all strings")
	var multibyte: StrongboxResult = StrongboxCodec.decode("😀".repeat(300), "value", 64, 1000)
	assert_eq(multibyte.code, StrongboxCodec.E_TOO_LARGE, "the limit counts UTF-8 bytes, not characters")
