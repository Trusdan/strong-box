class_name WyrdRng
extends RefCounted

## In-script PCG32 (XSH-RR 64/32).
##
## @experimental
## This is the minimal generator in pcg-c-basic [code]pcg_basic.c[/code]
## (commit [code]bc39cd76ac3d541e618606bcc6e1e5ba5e5e6aa3[/code]): multiplier
## [code]6364136223846793005[/code], [code]inc = (stream << 1) | 1[/code], then
## the XSH-RR output. The demo [code]pcg32-demo.c[/code] in that commit, seeded
## [code]pcg32_srandom_r(&rng, 42u, 54u)[/code], prints round 1 of pcg-c
## [code]test-high/expected/check-pcg32.out[/code] (commit
## [code]89b7dfbc5a50e5bf272cfac29dc435e81d2080d3[/code]). Wyrd does not call
## Godot's built-in generator. A seed and stream produce the same sequence
## on every Godot version.
##
## State and the increment are 64-bit. GDScript [code]>>[/code] sign-extends, so
## every right shift of state is logical: [code](v >> n) & ((1 << (64 - n)) - 1)[/code]
## ([method _lsr]). The step is one wrapping multiply-add, the same 64-bit wrap
## [WyrdHash] already uses. Seed and stream are the 64 bits of a GDScript [int].
##
## [method stream_id] is [method WyrdHash.of_string_name], so a named stream stays
## put across versions. [method for_decision] builds its seed by folding, in
## order, [code]game_seed[/code], the stream name, [code]decision_key[/code], and
## [code]time_bucket[/code] through [method WyrdHash.combine], then uses
## [method stream_id] as the PCG stream. Drawing from one decision does not
## advance another.
##
## [method to_state] is version [code]1[/code]. [code]state[/code], [code]inc[/code],
## and [code]seed[/code] are 16-digit lowercase hex strings, because JSON numbers
## are floats and would drop bits above 2^53. [code]inc[/code] is always odd.
## S2 saves each named stream's [method to_state]. This class does not register streams.

const _MUL: int = 6364136223846793005
const _TWO32: int = 4294967296

var _state: int = 0
var _inc: int = 1
var _seed: int = 0


func _init(seed_value: int = 0, stream: int = 0) -> void:
	seed_with(seed_value, stream)


func get_seed() -> int:
	return _seed


func set_seed(seed_value: int) -> void:
	_seed = seed_value
	_state = 0
	_step()
	_state += seed_value
	_step()


func seed_with(seed_value: int, stream: int = 0) -> void:
	_inc = (stream << 1) | 1
	set_seed(seed_value)


func next_u32() -> int:
	return _step()


func randi() -> int:
	return next_u32()


func randi_bounded(bound: int) -> int:
	assert(bound >= 1 and bound <= _TWO32, "WyrdRng.randi_bounded bound must be in 1..2^32")
	var threshold := (_TWO32 - bound) % bound
	while true:
		var roll := next_u32()
		if roll >= threshold:
			return roll % bound
	return 0


func randi_range(from_value: int, to_value: int) -> int:
	var low := from_value
	var high := to_value
	if low > high:
		var swapped := low
		low = high
		high = swapped
	if low == high:
		return low
	var span := high - low
	assert(span >= 0 and span < _TWO32, "WyrdRng.randi_range span must fit in 32 bits")
	return low + randi_bounded(span + 1)


func randf() -> float:
	return next_u32() * (1.0 / 4294967296.0)


func randf_range(from_value: float, to_value: float) -> float:
	return from_value + (to_value - from_value) * self.randf()


static func stream_id(name: StringName) -> int:
	return WyrdHash.of_string_name(name)


static func for_decision(game_seed: int, stream: StringName, decision_key: StringName, time_bucket: int) -> WyrdRng:
	return WyrdRng.new(_decision_seed(game_seed, stream, decision_key, time_bucket), stream_id(stream))


## First [method randf] of [method for_decision] without allocating a generator.
static func decision_unit(game_seed: int, stream: StringName, decision_key: StringName, time_bucket: int) -> float:
	var mixed := _decision_seed(game_seed, stream, decision_key, time_bucket)
	var inc := (stream_id(stream) << 1) | 1
	var state := _advance(0, inc)
	state += mixed
	state = _advance(state, inc)
	return float(_output(state)) * (1.0 / 4294967296.0)


static var _prefix_ready := false
static var _prefix_seed := 0
static var _prefix_stream: StringName = &""
static var _prefix_value := 0


static func _decision_seed(game_seed: int, stream: StringName, decision_key: StringName, time_bucket: int) -> int:
	var mixed := WyrdHash.combine(_seed_prefix(game_seed, stream), WyrdHash.of_string_name(decision_key))
	return WyrdHash.combine(mixed, WyrdHash.of_int(time_bucket))


static func _seed_prefix(game_seed: int, stream: StringName) -> int:
	if _prefix_ready and _prefix_seed == game_seed and _prefix_stream == stream:
		return _prefix_value
	var mixed := WyrdHash.combine(WyrdHash.of_int(game_seed), WyrdHash.of_string_name(stream))
	_prefix_ready = true
	_prefix_seed = game_seed
	_prefix_stream = stream
	_prefix_value = mixed
	return mixed


static func _advance(state: int, inc: int) -> int:
	return state * _MUL + inc


func to_state() -> Dictionary:
	return {
		"v": 1,
		"state": _hex64(_state),
		"inc": _hex64(_inc),
		"seed": _hex64(_seed),
	}


static func format_u64(value: int) -> String:
	return _hex64(value)


static func parse_u64(text: String) -> Dictionary:
	return _parse_hex(text, "value")


static func from_state(data: Dictionary) -> WyrdRng:
	var parsed := _decode(data)
	if parsed.is_empty():
		return null
	var rng := WyrdRng.new()
	rng._apply(parsed)
	return rng


func restore(data: Dictionary) -> bool:
	var parsed := _decode(data)
	if parsed.is_empty():
		return false
	_apply(parsed)
	return true


func _apply(parsed: Dictionary) -> void:
	_state = int(parsed["state"])
	_inc = int(parsed["inc"])
	_seed = int(parsed["seed"])


func _step() -> int:
	var old := _state
	_state = _advance(old, _inc)
	return _output(old)


static func _output(old: int) -> int:
	var xorshifted := _lsr(_lsr(old, 18) ^ old, 27) & 0xFFFFFFFF
	var rot := _lsr(old, 59)
	return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & 0xFFFFFFFF


static func _lsr(value: int, n: int) -> int:
	return (value >> n) & ((1 << (64 - n)) - 1)


static func _hex64(value: int) -> String:
	var digits := "0123456789abcdef"
	var chars := PackedStringArray()
	chars.resize(16)
	var bits := value
	for i in 16:
		chars[15 - i] = digits[bits & 0xF]
		bits >>= 4
	return "".join(chars)


static func _decode(data: Dictionary) -> Dictionary:
	var version: Variant = data.get("v", null)
	var version_ok := (typeof(version) == TYPE_INT and int(version) == 1) or (typeof(version) == TYPE_FLOAT and float(version) == 1.0)
	if not version_ok:
		push_error("WyrdRng state rejected: version must be 1")
		return {}
	var state := _parse_hex(data.get("state", null), "state")
	if state.is_empty():
		return {}
	var inc := _parse_hex(data.get("inc", null), "inc")
	if inc.is_empty():
		return {}
	var seed := _parse_hex(data.get("seed", null), "seed")
	if seed.is_empty():
		return {}
	if (int(inc["n"]) & 1) == 0:
		push_error("WyrdRng state rejected: increment must be odd")
		return {}
	return {"state": int(state["n"]), "inc": int(inc["n"]), "seed": int(seed["n"])}


static func _parse_hex(text: Variant, field: String) -> Dictionary:
	if typeof(text) != TYPE_STRING:
		push_error("WyrdRng state rejected: \"%s\" must be 16 hex digits" % field)
		return {}
	var hex := str(text)
	if hex.length() != 16:
		push_error("WyrdRng state rejected: \"%s\" must be 16 hex digits" % field)
		return {}
	var value := 0
	for i in 16:
		var code := hex.unicode_at(i)
		var nibble := -1
		if code >= 48 and code <= 57:
			nibble = code - 48
		elif code >= 97 and code <= 102:
			nibble = code - 87
		elif code >= 65 and code <= 70:
			nibble = code - 55
		if nibble < 0:
			push_error("WyrdRng state rejected: \"%s\" must be 16 hex digits" % field)
			return {}
		value = (value << 4) | nibble
	return {"n": value}
