class_name WyrdHash
extends RefCounted

## Stable FNV-1a 64-bit hash for [StringName] values and ints.
##
## @experimental
## Godot's [method @GlobalScope.hash] is not used. The engine does not promise that [code]hash()[/code]
## stays the same across versions or platforms, and a [StringName] hash can follow the intern table
## rather than the characters. Save keys, per-decision seeds, and determinism tests need a hash
## that is only a function of the bytes.
##
## The result is the unsigned 64-bit FNV-1a value stored in a signed 64-bit int (the GDScript
## [int] is signed, and arithmetic wraps modulo 2^64, which is the FNV step).
##
## Domain bytes keep the kinds of input apart:
## [code]0x01[/code] then the UTF-8 bytes of a [StringName] or of [method of_text],
## [code]0x02[/code] then an int as eight little-endian two's-complement bytes, or
## [code]0x03[/code] then those same eight bytes folded onto an existing hash by [method combine].
## [method of_text] does not intern the string and does not use the short-name memo.

const FNV_OFFSET: int = -3750763034362895579
const FNV_PRIME: int = 1099511628211
const _DOMAIN_STRING: int = 0x01
const _DOMAIN_INT: int = 0x02
const _DOMAIN_COMBINE: int = 0x03


static var _short_hash: Dictionary = {}


static func of_string_name(value: StringName) -> int:
	var text := String(value)
	var count := text.length()
	if count <= 16 and _short_hash.has(value):
		return int(_short_hash[value])
	var hash := (FNV_OFFSET ^ _DOMAIN_STRING) * FNV_PRIME
	var ascii := true
	for index in count:
		var code := text.unicode_at(index)
		if code > 127:
			ascii = false
			break
		hash = (hash ^ code) * FNV_PRIME
	if not ascii:
		hash = (FNV_OFFSET ^ _DOMAIN_STRING) * FNV_PRIME
		var body := text.to_utf8_buffer()
		for index in body.size():
			hash = (hash ^ (int(body[index]) & 0xFF)) * FNV_PRIME
	if count <= 16:
		_short_hash[value] = hash
	return hash


## Same bytes and domain as [method of_string_name]. Does not create a [StringName]
## and does not use the short-name memo.
static func of_text(value: String) -> int:
	var count := value.length()
	var hash := (FNV_OFFSET ^ _DOMAIN_STRING) * FNV_PRIME
	var ascii := true
	for index in count:
		var code := value.unicode_at(index)
		if code > 127:
			ascii = false
			break
		hash = (hash ^ code) * FNV_PRIME
	if not ascii:
		hash = (FNV_OFFSET ^ _DOMAIN_STRING) * FNV_PRIME
		var body := value.to_utf8_buffer()
		for index in body.size():
			hash = (hash ^ (int(body[index]) & 0xFF)) * FNV_PRIME
	return hash


static func of_int(value: int) -> int:
	var hash := _mix(FNV_OFFSET, _DOMAIN_INT)
	var bits := value
	for _i in 8:
		hash = _mix(hash, bits & 0xFF)
		bits >>= 8
	return hash


## Folds [param b] onto [param a]. Mixes domain byte [code]0x03[/code], then the eight
## little-endian two's-complement bytes of [param b], low byte first.
static func combine(a: int, b: int) -> int:
	var hash := _mix(a, _DOMAIN_COMBINE)
	var bits := b
	for _i in 8:
		hash = _mix(hash, bits & 0xFF)
		bits >>= 8
	return hash


static func _mix(hash: int, byte: int) -> int:
	return (hash ^ (byte & 0xFF)) * FNV_PRIME
