extends GutTest

## Cross-platform golden saves: pack() must give the committed bytes on every platform, and the
## committed files must unpack to the dataset exactly, with reals compared bit for bit.
## Fixtures are only rewritten on purpose, by tools/regenerate_golden_fixtures.gd.

const Dataset: GDScript = preload("res://tests/fixtures/golden/golden_dataset.gd")
const BITS_FORM: String = "\"\\$t\":\"float\",\"v\":\"[0-9a-f]{16}\""
const PLAIN_FORM: String = "\"\\$t\":\"float\",\"v\":-?[0-9]"


func _fixture(file_name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Dataset.FOLDER + file_name)


func test_pack_gives_the_fixture_bytes_exactly() -> void:
	for file_name: String in Dataset.FIXTURES:
		var packed: StrongboxResult = Dataset.pack_fixture(file_name)
		assert_true(packed.ok, str(packed))
		var expected: PackedByteArray = _fixture(file_name)
		var actual: PackedByteArray = (packed.value as String).to_utf8_buffer()
		assert_gt(expected.size(), 0, "%s exists" % file_name)
		assert_eq(actual.size(), expected.size(), "%s: same length" % file_name)
		assert_eq(_first_difference(actual, expected), -1, "%s: first differing byte" % file_name)


func test_fixtures_unpack_to_the_dataset_with_exact_types_and_bits() -> void:
	for file_name: String in Dataset.FIXTURES:
		var unpacked: StrongboxResult = StrongboxEnvelope.unpack(_fixture(file_name).get_string_from_utf8())
		assert_true(unpacked.ok, "%s: %s" % [file_name, unpacked])
		if not unpacked.ok:
			continue
		assert_eq(_difference(unpacked.value["body"], Dataset.build(), "body"), "", file_name)
		var header: Dictionary = unpacked.value["header"]
		var wanted: Dictionary = Dataset.FIXTURES[file_name]
		for key: String in wanted:
			assert_eq(_difference(header[key], wanted[key], "header." + key), "", file_name)
		assert_eq(header["saved_unix"], Dataset.SAVED_UNIX)


func test_fixture_checksums_validate_and_a_changed_body_is_caught() -> void:
	for file_name: String in Dataset.FIXTURES:
		var text: String = _fixture(file_name).get_string_from_utf8()
		assert_true(StrongboxEnvelope.unpack(text).ok, "%s: checksum validates" % file_name)
		var tampered: String = text.replace("\"word\":\"Hub\"", "\"word\":\"Hut\"")
		assert_ne(tampered, text)
		assert_eq(StrongboxEnvelope.unpack(tampered).code, StrongboxEnvelope.E_CHECKSUM, file_name)


func test_both_real_forms_appear_at_least_five_times() -> void:
	var text: String = _fixture("dataset.sbgolden").get_string_from_utf8()
	var bits: int = RegEx.create_from_string(BITS_FORM).search_all(text).size()
	var plain: int = RegEx.create_from_string(PLAIN_FORM).search_all(text).size()
	assert_gte(bits, 5, "tagged floats in the bits form")
	assert_gte(plain, 5, "tagged floats in the plain form")
	for hex: String in ["8000000000000000", "7ff0000000000000", "fff0000000000000", "7ff8000000000123", "0000000000000001"]:
		assert_string_contains(text, "\"%s\"" % hex)
	assert_string_contains(text, "\"negative_zero\":{\"$t\":\"float\",\"v\":\"8000000000000000\"}", "a real -0.0, not a merged constant")


func test_typed_arrays_come_back_untyped_as_documented() -> void:
	var body: Dictionary = StrongboxEnvelope.unpack(_fixture("dataset.sbgolden").get_string_from_utf8()).value["body"]
	assert_false((body["containers"]["typed_ints"] as Array).is_typed(), "docs/format.md: typed arrays come back untyped")
	assert_true((Dataset.build()["containers"]["typed_ints"] as Array).is_typed(), "the dataset itself uses a typed array")


func test_the_bit_comparison_tells_negative_zero_and_nan_payloads_apart() -> void:
	# -0.0 is built from bits: GDScript merges a literal -0.0 with a literal 0.0 in one function.
	var neg_zero: float = Dataset.from_bits("8000000000000000")
	assert_ne(_difference(neg_zero, 0.0, "x"), "")
	assert_ne(_difference(NAN, Dataset.from_bits("7ff8000000000123"), "x"), "")
	assert_eq(_difference(NAN, NAN, "x"), "")
	assert_ne(_difference(Vector3(neg_zero, 1, 2), Vector3(0.0, 1, 2), "x"), "")
	assert_ne(_difference(1, 1.0, "x"), "", "an int is not a float")
	assert_ne(_difference({&"a": 1}, {"a": 1}, "x"), "", "a StringName key is not a String key")


func _first_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


## Returns "" when [param actual] matches [param expected] exactly (same types, reals equal bit
## for bit), otherwise the path and both values. Typed arrays may come back untyped.
func _difference(actual: Variant, expected: Variant, path: String) -> String:
	if typeof(actual) != typeof(expected):
		return "%s: type %s, expected %s" % [path, type_string(typeof(actual)), type_string(typeof(expected))]
	match typeof(expected):
		TYPE_FLOAT:
			if _bits(actual) != _bits(expected):
				return "%s: bits %s, expected %s" % [path, _bits(actual), _bits(expected)]
			return ""
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if actual.size() != expected.size():
				return "%s: size %d, expected %d" % [path, actual.size(), expected.size()]
			for i: int in expected.size():
				var inner: String = _difference(actual[i], expected[i], "%s[%d]" % [path, i])
				if inner != "":
					return inner
			return ""
		TYPE_DICTIONARY:
			if actual.size() != expected.size():
				return "%s: %d keys, expected %d" % [path, actual.size(), expected.size()]
			for key: Variant in expected:
				var match_key: Variant = _same_key(actual, key)
				if match_key == null:
					return "%s: missing key %s (%s)" % [path, key, type_string(typeof(key))]
				var inner: String = _difference(actual[match_key], expected[key], "%s.%s" % [path, key])
				if inner != "":
					return inner
			return ""
	var reals: Array = _real_parts(expected)
	if not reals.is_empty():
		return _difference(_real_parts(actual), reals, path)
	if actual != expected:
		return "%s: %s, expected %s" % [path, actual, expected]
	return ""


func _same_key(dict: Dictionary, key: Variant) -> Variant:
	for candidate: Variant in dict:
		if typeof(candidate) == typeof(key) and candidate == key:
			return candidate
	return null


func _bits(value: float) -> String:
	var bytes: PackedByteArray = PackedFloat64Array([value]).to_byte_array()
	bytes.reverse()
	return bytes.hex_encode()


## The real components of a struct, in the codec's order, or [] for other types.
func _real_parts(value: Variant) -> Array:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION:
			var parts: Array = []
			for i: int in {TYPE_VECTOR2: 2, TYPE_VECTOR3: 3}.get(typeof(value), 4):
				parts.append(float(value[i]))
			return parts
		TYPE_RECT2, TYPE_AABB:
			return _real_parts(value.position) + _real_parts(value.size)
		TYPE_TRANSFORM2D:
			return _real_parts(value.x) + _real_parts(value.y) + _real_parts(value.origin)
		TYPE_BASIS:
			return _real_parts(value.x) + _real_parts(value.y) + _real_parts(value.z)
		TYPE_TRANSFORM3D:
			return _real_parts(value.basis) + _real_parts(value.origin)
	return []
