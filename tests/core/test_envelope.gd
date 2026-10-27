extends GutTest

## StrongboxEnvelope: header, checksum, determinism and refusals.

const FIXED_TIME: int = 1767225600 # 2026-01-01 00:00:00 UTC


func _body() -> Dictionary:
	return {
		"current_room": "Cellar",
		"rooms": {
			"Hub": {"lever": {"on": true}},
			"Cellar": {"chest": {"opened": true, "position": Vector3(1.5, 0, -2.25)}, "coins_left": 3},
		},
		"player": {"name": &"player", "health": 87.5},
	}


func _pack(body: Dictionary = _body()) -> String:
	var result: StrongboxResult = StrongboxEnvelope.pack(body, {"location": "Cellar", "kind": &"manual"}, 3, "0.1.0", 754.25, FIXED_TIME)
	assert_true(result.ok, str(result))
	return result.value


## Parses the file, applies [param change] to the parsed data and writes it back.
func _edit(text: String, change: Callable) -> String:
	var data: Dictionary = JSON.parse_string(text)
	change.call(data)
	return JSON.stringify(data, "", true, true)


func test_pack_then_unpack_returns_header_and_body() -> void:
	var result: StrongboxResult = StrongboxEnvelope.unpack(_pack())
	assert_true(result.ok, str(result))
	var header: Dictionary = result.value["header"]
	assert_eq(header["format"], "strongbox")
	assert_eq(header["format_version"], StrongboxEnvelope.FORMAT_VERSION)
	assert_eq(header["schema_version"], 3)
	assert_eq(header["game_version"], "0.1.0")
	assert_eq(header["saved_unix"], FIXED_TIME)
	assert_eq(typeof(header["saved_unix"]), TYPE_INT)
	assert_eq(header["playtime_s"], 754.25)
	assert_eq(header["meta"], {"location": "Cellar", "kind": &"manual"})
	assert_eq(typeof(header["meta"]["kind"]), TYPE_STRING_NAME)
	assert_true(header["checksum"].begins_with("sha256:"))
	assert_eq(result.value["body"], _body())
	assert_eq(typeof(result.value["body"]["rooms"]["Cellar"]["chest"]["position"]), TYPE_VECTOR3)


func test_saved_unix_defaults_to_now() -> void:
	var result: StrongboxResult = StrongboxEnvelope.unpack(StrongboxEnvelope.pack({}, {}).value)
	assert_almost_eq(float(result.value["header"]["saved_unix"]), Time.get_unix_time_from_system(), 5.0)


func test_pack_is_deterministic() -> void:
	var first: String = _pack()
	for i: int in 5:
		assert_eq(_pack(), first, "same input must give byte-identical text")
	var reordered: Dictionary = {"player": _body()["player"], "rooms": _body()["rooms"], "current_room": "Cellar"}
	assert_eq(_pack(reordered), first, "key order must not matter")


func test_pack_is_deterministic_with_both_real_forms() -> void:
	# 0.5, 100.25 and 1/3 survive Godot's JSON exactly, so they stay plain numbers.
	# 123456789.123456789, -0.0, NaN and INF do not, so they are written as IEEE-754 bits.
	# The text must still be byte-identical, and every value exact.
	var reals: Dictionary = {"plain": [0.5, 100.25, 2.0, 1.0 / 3.0], "bits": [0.1 + 0.2, 123456789.123456789, -0.0, NAN, INF], "mixed": Vector2(0.5, 0.1)}
	var encoded: Array = StrongboxCodec.encode(reals).value["bits"]
	assert_eq(typeof(encoded[1]["v"]), TYPE_STRING, "123456789.123456789 should use the bits form")
	assert_eq(encoded[1]["v"], "419d6f34547e6b75")
	assert_eq(typeof(StrongboxCodec.encode(0.5).value["v"]), TYPE_FLOAT, "0.5 should stay a plain number")
	var first: String = _pack(reals)
	assert_eq(_pack(reals), first)
	var back: Dictionary = StrongboxEnvelope.unpack(first).value["body"]
	assert_eq(back["plain"], [0.5, 100.25, 2.0, 1.0 / 3.0])
	assert_eq(back["bits"][1], 123456789.123456789)
	assert_true(is_nan(back["bits"][3]))
	assert_eq(PackedFloat64Array([back["bits"][2]]).to_byte_array(), PackedFloat64Array([-0.0]).to_byte_array())


func test_reformatted_file_still_loads() -> void:
	var pretty: String = JSON.stringify(JSON.parse_string(_pack()), "\t", false, true)
	var result: StrongboxResult = StrongboxEnvelope.unpack(pretty)
	assert_true(result.ok, "whitespace and key order are not part of the checksum: %s" % result)
	assert_eq(result.value["body"], _body())


func test_one_character_change_fails_checksum() -> void:
	var text: String = _pack()
	assert_eq(text.count("\"coins_left\":3"), 1)
	var changed_number: StrongboxResult = StrongboxEnvelope.unpack(text.replace("\"coins_left\":3", "\"coins_left\":4"))
	assert_eq(changed_number.code, StrongboxEnvelope.E_CHECKSUM)
	assert_eq(text.count("\"current_room\":\"Cellar\""), 1)
	var changed_letter: StrongboxResult = StrongboxEnvelope.unpack(text.replace("\"current_room\":\"Cellar\"", "\"current_room\":\"Cellas\""))
	assert_eq(changed_letter.code, StrongboxEnvelope.E_CHECKSUM)
	var changed_checksum: String = _edit(text, func(d: Dictionary) -> void:
		d["header"]["checksum"] = "sha256:" + "0".repeat(64))
	assert_eq(StrongboxEnvelope.unpack(changed_checksum).code, StrongboxEnvelope.E_CHECKSUM)


func test_refuses_newer_format() -> void:
	var newer: String = _edit(_pack(), func(d: Dictionary) -> void:
		d["header"]["format_version"] = StrongboxEnvelope.FORMAT_VERSION + 1)
	var result: StrongboxResult = StrongboxEnvelope.unpack(newer)
	assert_eq(result.code, StrongboxEnvelope.E_FORMAT_TOO_NEW)
	assert_string_contains(result.message, str(StrongboxEnvelope.FORMAT_VERSION + 1))


func test_refuses_bad_json() -> void:
	for text: String in ["", "{oops", "{\"header\": {", "not json at all"]:
		assert_eq(StrongboxEnvelope.unpack(text).code, StrongboxEnvelope.E_JSON, "'%s'" % text)


func test_refuses_wrong_layout_and_header() -> void:
	var cases: Dictionary = {
		"array": "[]",
		"no header": "{\"body\": {}}",
		"no body": "{\"header\": {}}",
		"wrong format": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["format"] = "other"),
		"missing format": _edit(_pack(), func(d: Dictionary) -> void: d["header"].erase("format")),
		"version zero": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["format_version"] = 0),
		"version text": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["format_version"] = "1"),
		"schema text": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["schema_version"] = "3"),
		"meta not object": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["meta"] = []),
		"bad checksum shape": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["checksum"] = "md5:abc"),
		"header bad tag": _edit(_pack(), func(d: Dictionary) -> void: d["header"]["meta"] = {"$t": "Object", "v": 1}),
	}
	for label: String in cases:
		assert_eq(StrongboxEnvelope.unpack(cases[label]).code, StrongboxEnvelope.E_FORMAT, label)


func test_pack_reports_codec_errors_with_body_path() -> void:
	var result: StrongboxResult = StrongboxEnvelope.pack({"rooms": {"Cellar": {"chest": RefCounted.new()}}}, {})
	assert_eq(result.code, StrongboxCodec.E_UNSUPPORTED_TYPE)
	assert_string_contains(result.message, "body.rooms.Cellar.chest")


func test_unpack_passes_on_body_limits() -> void:
	var text: String = _pack({"note": "x".repeat(5000)})
	assert_true(StrongboxEnvelope.unpack(text).ok)
	assert_eq(StrongboxEnvelope.unpack(text, 64, 1000).code, StrongboxCodec.E_TOO_LARGE)
