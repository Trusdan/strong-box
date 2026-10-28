extends RefCounted

## Test helper: the deterministic dataset behind the cross-platform golden save fixtures.
##
## The same code builds the same values on every platform. tests/test_cross_platform_fixtures.gd
## checks pack() against the committed files, and tools/regenerate_golden_fixtures.gd rewrites
## them. Change the dataset only together with a deliberate regeneration.

const FOLDER: String = "res://tests/fixtures/golden/"
const SAVED_UNIX: int = 1767225600 # 2026-01-01T00:00:00Z
const SEED: int = 20261027
## Fixture file name -> the optional header values it is packed with.
const FIXTURES: Dictionary = {
	"dataset.sbgolden": {"meta": {}, "schema_version": 1, "game_version": "", "playtime_s": 0.0},
	"dataset_header.sbgolden": {
		"meta": {"location": "Cellar", "label": "Cellar — next to the chest"},
		"schema_version": 3,
		"game_version": "1.2.0-rc.1",
		"playtime_s": 3723.123456789,
	},
}


## Returns the pack() output for the fixture [param file_name], as text.
static func pack_fixture(file_name: String) -> StrongboxResult:
	var header: Dictionary = FIXTURES[file_name]
	return StrongboxEnvelope.pack(build(), header["meta"], header["schema_version"], header["game_version"], header["playtime_s"], SAVED_UNIX)


## Returns a double from its IEEE-754 bits, most significant byte first.
static func from_bits(hex: String) -> float:
	var bytes: PackedByteArray = hex.hex_decode()
	bytes.reverse()
	return bytes.decode_double(0)


## Builds the dataset: every type the codec allows, tricky reals, and fixed-seed random doubles.
static func build() -> Dictionary:
	# Built from bits: GDScript merges constants that compare equal, so a literal -0.0 next to a
	# literal 0.0 in one function silently becomes 0.0.
	var neg_zero: float = from_bits("8000000000000000")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	# Dyadic fractions: exact in JSON, so they use the plain-number form.
	var dyadic: Array = []
	for i: int in 12:
		dyadic.append(float(rng.randi_range(-1000000, 1000000)) / 64.0)
	# Full 52-bit mantissas between about 1e-6 and 1e6: many need the bits form.
	var mantissas: Array = []
	for i: int in 24:
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(8)
		bytes.encode_u32(0, rng.randi())
		bytes.encode_u32(4, (rng.randi() & 0x000fffff) | ((1003 + rng.randi_range(0, 40)) << 20) | ((i % 2) << 31))
		mantissas.append(bytes.decode_double(0))
	var typed_ints: Array[int] = [3, 1, 2]
	var typed_vectors: Array[Vector3] = [Vector3(1, 2, 3), Vector3(-0.5, 0.25, 0.0)]
	return {
		"plain": {"null": null, "true": true, "false": false, "empty_string": "", "word": "Hub"},
		"reals": {
			"zero": 0.0,
			"negative_zero": neg_zero,
			"tenth": 0.1,
			"third": 1.0 / 3.0,
			"huge": 1e308,
			"smallest_subnormal": from_bits("0000000000000001"),
			"largest_double": from_bits("7fefffffffffffff"),
			"inf": INF,
			"negative_inf": -INF,
			"nan": NAN,
			"nan_with_payload": from_bits("7ff8000000000123"),
			"pi_ish": 123456789.123456789,
			"dyadic_randoms": dyadic,
			"mantissa_randoms": mantissas,
		},
		"ints": [0, -1, 1, 9007199254740992, 9007199254740993, -9007199254740993, -9223372036854775808, 9223372036854775807],
		"strings": [
			"Cellar — ünïcödé",
			"日本語のテキスト",
			"non-BMP: 🗝 𝄞 😀",
			"escapes: tab\t newline\n quote\" backslash\\ nul-free",
			"$t",
		],
		"names": [&"coin", &"", ^"Cellar/Props/Chest01", ^"../Hub:position"],
		"structs": [
			Vector2(1.5, neg_zero), Vector2i(-3, 2147483647), Vector3(0.1, -2.25, 1e30), Vector3i(-2147483648, 0, 7),
			Vector4(0.5, neg_zero, INF, 3.0), Color(1.0, 0.5, 0.1, 1.0), Quaternion(0.0, 0.0, 0.70710677, 0.70710677),
			Rect2(0.0, -8.0, 16.0, 0.3), Rect2i(0, 0, 16, 8), AABB(Vector3(-1, -2, -3), Vector3(0.2, 4, 6)),
			Basis(Vector3.UP, 0.7), Transform2D(0.3, Vector2(4, 5)), Transform3D(Basis(Vector3.RIGHT, -1.1), Vector3(1.25, 0.0, -3.5)),
		],
		"containers": {
			"empty_array": [],
			"empty_dict": {},
			"nested": [[], {}, [1, [2, [3, [4.5]]]], {"a": {"b": {"c": [true]}}}],
			"escaped_keys": {1: "Hub", &"room": "Cellar", -7: [0.1], 9007199254740993: "big key"},
			"dollar_key": {"$t": "not a tag", "v": 1},
			"typed_ints": typed_ints,
			"typed_vectors": typed_vectors,
		},
		"packed": {
			"bytes": PackedByteArray([0, 1, 127, 128, 255]),
			"empty_bytes": PackedByteArray(),
			"int32": PackedInt32Array([-2147483648, 0, 2147483647]),
			"int64": PackedInt64Array([-9223372036854775808, 1, 9007199254740993]),
			"float32": PackedFloat32Array([0.5, neg_zero, 0.1, 3.4e38, INF]),
			"float64": PackedFloat64Array([0.5, neg_zero, 0.1, NAN, -INF, from_bits("0000000000000001")]),
			"strings": PackedStringArray(["Hub", "", "😀"]),
			"vector2": PackedVector2Array([Vector2(1, 2), Vector2(neg_zero, 0.1)]),
			"vector3": PackedVector3Array([Vector3(1, 2, 3), Vector3(0.1, neg_zero, 1e-7)]),
			"colors": PackedColorArray([Color(1, 0, 0, 1), Color(0.1, 0.2, 0.3, 0.4)]),
		},
	}
