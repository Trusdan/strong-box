class_name WyrdAIValidator
extends RefCounted

## Five checks for one delivered string. Pure: no runtime and no resolver.
##
## @experimental
## [method check] returns the first failing rule, or an empty name when the
## text passes. The order is limits, names, banned, spoiler, classifier.
## The text is never edited.

## Case-insensitive whole words or phrases. Empty entries are ignored.
var banned_terms: PackedStringArray = PackedStringArray()
## Display name to entity ids. A name is checked only when it starts with an uppercase letter.
var entity_names: Dictionary = {}
## Forbidden forms, matched as whole words or phrases, case-insensitive.
var spoilers: PackedStringArray = PackedStringArray()
## [code]fn(text, kind, packet) -> bool[/code]. Called only when [member classifier_registered] is set.
var classifier: Callable = Callable()
## Set when a classifier was registered. A freed object then fails the classifier rule.
var classifier_registered: bool = false


func check(text: String, kind: StringName, packet: Dictionary, constraints: Dictionary = {}) -> StringName:
	if _over_limits(text, kind, packet, constraints):
		return &"limits"
	if _names_fail(text, packet):
		return &"names"
	if _phrase_hit(text, banned_terms, true):
		return &"banned"
	if _phrase_hit(text, spoilers, true):
		return &"spoiler"
	if _classifier_fails(text, kind, packet):
		return &"classifier"
	return &""


## The cap-free part of the limits rule. Used when a saved packet is not available.
static func safe_text(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	if text.length() > 240:
		return false
	return not _forbidden(text)


func _over_limits(text: String, kind: StringName, packet: Dictionary, constraints: Dictionary) -> bool:
	if text.strip_edges().is_empty():
		return true
	if text.length() > _cap(kind, packet, constraints):
		return true
	return _forbidden(text)


func _cap(kind: StringName, packet: Dictionary, constraints: Dictionary) -> int:
	var cap := 240
	var max_chars: Variant = constraints.get("max_chars", null)
	if typeof(max_chars) == TYPE_INT and int(max_chars) >= 1:
		cap = mini(cap, int(max_chars))
	var fallback := WyrdAIPacket.fallback_text(kind, packet)
	if not fallback.is_empty():
		cap = mini(cap, fallback.length() * 2)
	return cap


static func _forbidden(text: String) -> bool:
	var marks := "{}#[]<>"
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0x20:
			return true
		if code >= 0x7F and code <= 0x9F:
			return true
		if code >= 0x200B and code <= 0x200F:
			return true
		if code >= 0x2028 and code <= 0x202E:
			return true
		if code >= 0x2060 and code <= 0x2069:
			return true
		if code == 0xFEFF:
			return true
		if marks.contains(text.substr(i, 1)):
			return true
	return false


func _names_fail(text: String, packet: Dictionary) -> bool:
	var present := _packet_ids(packet)
	var labels: Array = entity_names.keys()
	labels.sort()
	for label in labels:
		var name := String(label)
		if not _starts_upper(name):
			continue
		if not _bounded(text, name, false):
			continue
		var ids: Variant = entity_names[label]
		var found := false
		if ids is Array:
			for id in ids:
				if present.has(String(id)):
					found = true
					break
		if not found:
			return true
	return false


func _packet_ids(packet: Dictionary) -> Dictionary:
	var ids := {}
	var rows: Variant = packet.get("entities", [])
	if not (rows is Array):
		return ids
	for item in rows:
		if item is Dictionary:
			var id := str((item as Dictionary).get("id", ""))
			if not id.is_empty():
				ids[id] = true
	return ids


func _phrase_hit(text: String, terms: PackedStringArray, ignore_case: bool) -> bool:
	for term in terms:
		if term.is_empty():
			continue
		if word_hit(text, term, ignore_case):
			return true
	return false


func _classifier_fails(text: String, kind: StringName, packet: Dictionary) -> bool:
	if not classifier_registered:
		return false
	if not classifier.is_valid():
		return true
	var result: Variant = classifier.call(text, kind, packet.duplicate(true))
	return typeof(result) != TYPE_BOOL or result != true


func _starts_upper(text: String) -> bool:
	if text.is_empty():
		return false
	var ch := text.substr(0, 1)
	return ch.to_lower() != ch.to_upper() and ch == ch.to_upper()


## Whole-word match. [param ignore_case] folds both sides. Empty [param needle] misses.
static func word_hit(text: String, needle: String, ignore_case: bool) -> bool:
	if needle.is_empty():
		return false
	var hay := text
	var pin := needle
	if ignore_case:
		hay = text.to_lower()
		pin = needle.to_lower()
	var from := 0
	while true:
		var at := hay.find(pin, from)
		if at < 0:
			return false
		var before := at == 0 or not _word_char(hay.unicode_at(at - 1))
		var after_at := at + pin.length()
		var after := after_at >= hay.length() or not _word_char(hay.unicode_at(after_at))
		if before and after:
			return true
		from = at + 1
	return false


func _bounded(text: String, needle: String, ignore_case: bool) -> bool:
	return word_hit(text, needle, ignore_case)


static func _word_char(code: int) -> bool:
	var ch := String.chr(code)
	if ch == "_" or (ch >= "0" and ch <= "9"):
		return true
	return ch.to_lower() != ch.to_upper()
