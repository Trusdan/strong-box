class_name StrongboxEnvelope
extends RefCounted

## Wraps an encoded save body with a versioned header and a checksum, as JSON text.
##
## @experimental
## A save file is one JSON object: [code]{"body": ..., "header": ...}[/code]. The body is
## written by [StrongboxCodec]. The header names the format and its version, carries the
## game's schema version and labels, and holds a SHA-256 checksum of the body's canonical
## JSON. [method unpack] checks the format, the version and the checksum before it decodes
## the body. See [code]docs/format.md[/code].

## The file is not valid JSON.
const E_JSON: StringName = &"E_JSON"
## The file is JSON but not a Strongbox save: wrong layout, missing or wrong header fields.
const E_FORMAT: StringName = &"E_FORMAT"
## The file was written by a newer Strongbox format than this version can read.
const E_FORMAT_TOO_NEW: StringName = &"E_FORMAT_TOO_NEW"
## The body does not match the header's checksum: the file was changed or damaged.
const E_CHECKSUM: StringName = &"E_CHECKSUM"

## The value of the header's [code]format[/code] field.
const FORMAT_NAME: String = "strongbox"
## The newest format version this code writes and reads. Owned by the addon.
const FORMAT_VERSION: int = 1
const _CHECKSUM_PREFIX: String = "sha256:"
const _SAFE_INT: float = 9007199254740992.0 # 2^53
## Raw JSON nesting allowed while computing the checksum (tags add a few levels).
const _MAX_RAW_DEPTH: int = 512


## Encodes [param body] and wraps it with a header. [param meta] holds game-supplied labels for
## a load menu (for example a location name). On success [member StrongboxResult.value] is the
## JSON text. [param saved_unix] defaults to the current time; pass a fixed value for
## reproducible output.
## @experimental
static func pack(body: Dictionary, meta: Dictionary, schema_version: int = 1, game_version: String = "", playtime_s: float = 0.0, saved_unix: int = -1) -> StrongboxResult:
	var encoded_body: StrongboxResult = StrongboxCodec.encode(body, "body")
	if not encoded_body.ok:
		return encoded_body
	if saved_unix < 0:
		saved_unix = int(Time.get_unix_time_from_system())
	var header: Dictionary = {
		"format": FORMAT_NAME,
		"format_version": FORMAT_VERSION,
		"schema_version": schema_version,
		"game_version": game_version,
		"saved_unix": saved_unix,
		"playtime_s": playtime_s,
		"meta": meta,
		"checksum": _CHECKSUM_PREFIX + _canonical(encoded_body.value).sha256_text(),
	}
	var encoded_header: StrongboxResult = StrongboxCodec.encode(header, "header")
	if not encoded_header.ok:
		return encoded_header
	var file: Dictionary = {"header": encoded_header.value, "body": encoded_body.value}
	return StrongboxResult.success(JSON.stringify(file, "", true, true))


## Parses save [param text] and returns [code]{"header": Dictionary, "body": Dictionary}[/code].
## Refuses invalid JSON ([constant E_JSON]), a wrong layout or header ([constant E_FORMAT]),
## a newer format ([constant E_FORMAT_TOO_NEW]) and a checksum mismatch ([constant E_CHECKSUM]),
## in that order, before the body is decoded. Codec errors from the body are passed on.
## @experimental
static func unpack(text: String, max_depth: int = StrongboxCodec.DEFAULT_MAX_DEPTH, max_string_bytes: int = StrongboxCodec.DEFAULT_MAX_STRING_BYTES) -> StrongboxResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return StrongboxResult.failure(E_JSON, "Not valid JSON (line %d): %s" % [json.get_error_line(), json.get_error_message()])
	var file: Variant = json.data
	if typeof(file) != TYPE_DICTIONARY or not file.has("header") or not file.has("body"):
		return StrongboxResult.failure(E_FORMAT, "Not a Strongbox save: expected an object with \"header\" and \"body\".")
	var header_result: StrongboxResult = StrongboxCodec.decode(file["header"], "header", max_depth, max_string_bytes)
	if not header_result.ok:
		return StrongboxResult.failure(E_FORMAT, "Bad header: %s" % header_result.message)
	if typeof(header_result.value) != TYPE_DICTIONARY:
		return StrongboxResult.failure(E_FORMAT, "Bad header: expected an object.")
	var header: Dictionary = header_result.value
	if header.get("format") is not String or header["format"] != FORMAT_NAME:
		return StrongboxResult.failure(E_FORMAT, "Not a Strongbox save: header.format must be \"%s\"." % FORMAT_NAME)
	if header.get("format_version") is not int or header["format_version"] < 1:
		return StrongboxResult.failure(E_FORMAT, "Bad header: format_version must be a whole number of at least 1.")
	if header["format_version"] > FORMAT_VERSION:
		return StrongboxResult.failure(E_FORMAT_TOO_NEW, "This save uses format version %d; this version of Strongbox reads up to %d." % [header["format_version"], FORMAT_VERSION])
	var problem: String = _check_header_fields(header)
	if problem != "":
		return StrongboxResult.failure(E_FORMAT, "Bad header: %s" % problem)

	var raw: Variant = _normalize(file["body"], 0)
	if raw == null and file["body"] != null:
		return StrongboxResult.failure(StrongboxCodec.E_TOO_DEEP, "body: nesting is deeper than %d levels." % _MAX_RAW_DEPTH)
	if _CHECKSUM_PREFIX + _canonical(raw).sha256_text() != header["checksum"]:
		return StrongboxResult.failure(E_CHECKSUM, "The save body does not match its checksum: the file was changed or damaged.")

	var body_result: StrongboxResult = StrongboxCodec.decode(file["body"], "body", max_depth, max_string_bytes)
	if not body_result.ok:
		return body_result
	if typeof(body_result.value) != TYPE_DICTIONARY:
		return StrongboxResult.failure(E_FORMAT, "Bad body: expected an object.")
	return StrongboxResult.success({"header": header, "body": body_result.value})


static func _check_header_fields(header: Dictionary) -> String:
	if header.get("schema_version") is not int:
		return "schema_version must be a whole number."
	if header.get("game_version") is not String:
		return "game_version must be a string."
	if header.get("saved_unix") is not int:
		return "saved_unix must be a whole number."
	if header.get("playtime_s") is not float:
		return "playtime_s must be a number."
	if header.get("meta") is not Dictionary:
		return "meta must be an object."
	var checksum: Variant = header.get("checksum")
	if checksum is not String or not checksum.begins_with(_CHECKSUM_PREFIX) or checksum.length() != _CHECKSUM_PREFIX.length() + 64:
		return "checksum must be \"sha256:\" followed by 64 hex digits."
	return ""


## The canonical JSON text of an encoded body: sorted keys, full float precision, and whole
## numbers written as integers. Parsing JSON turns every number into a float, so whole
## numbers are normalized on both sides to give the same text before and after a round trip.
static func _canonical(encoded: Variant) -> String:
	return JSON.stringify(_normalize(encoded, 0), "", true, true)


## Returns [param value] with whole floats up to 2^53 turned into ints, or null when nesting
## is deeper than the raw limit. Only arrays, dictionaries and numbers change.
static func _normalize(value: Variant, depth: int) -> Variant:
	if depth > _MAX_RAW_DEPTH:
		return null
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) <= _SAFE_INT:
				return int(f)
			return f
		TYPE_ARRAY:
			var out: Array = []
			for item: Variant in value:
				var n: Variant = _normalize(item, depth + 1)
				if n == null and item != null:
					return null
				out.append(n)
			return out
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value:
				var n: Variant = _normalize(value[key], depth + 1)
				if n == null and value[key] != null:
					return null
				out[key] = n
			return out
	return value
