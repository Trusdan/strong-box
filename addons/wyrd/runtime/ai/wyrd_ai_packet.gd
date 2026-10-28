class_name WyrdAIPacket
extends RefCounted

## Context packet for one opted-in line. Static builders only.
##
## @experimental
## Facts are the [code]ai_context[/code] keys the player knows, with the known
## value. A fact the player has not learned is left out, including every
## resolved fact. Facts carry no secrecy name and no public marker, so a
## world value the player does not know never enters the packet.


## Empty, with a warning, when [param line_id] is not an opted-in line.
static func for_line(runtime: WyrdRuntime, line_id: String, kind: StringName, speaker: StringName = &"") -> Dictionary:
	if runtime == null or runtime.content() == null or not runtime.content().ai_lines.has(line_id):
		push_warning("WyrdAIPacket.for_line: \"%s\" is not an opted-in line" % line_id)
		return {}
	var content := runtime.content()
	var entry: Dictionary = content.ai_lines[line_id]
	var line_def := content.lines.get(line_id) as WyrdLineDef
	var text := ""
	if line_def != null:
		text = str(runtime.resolve_line(line_def).get("text", ""))
	var packet := {
		"entities": [],
		"facts": {},
		"kind": String(kind),
		"line_ids": [line_id],
		"text": text,
		"v": 1,
	}
	var facts: Dictionary = {}
	var keys: PackedStringArray = entry.get("keys", PackedStringArray())
	for key in keys:
		var taken := _take_fact(runtime, line_id, String(key))
		if bool(taken.get("keep", false)):
			facts[String(key)] = taken["value"]
	packet["facts"] = facts
	var speaker_id := _speaker_id(runtime, entry, line_def, speaker)
	var world := _world(runtime)
	var speaker_name := ""
	if not speaker_id.is_empty():
		speaker_name = _entity_name(world, speaker_id)
		packet["speaker"] = {
			"id": speaker_id,
			"name": speaker_name,
			"roles": _speaker_roles(runtime, line_id, speaker_id),
		}
	var deeds: Array = []
	if kind == &"gossip":
		deeds = _gossip_deeds(runtime)
		packet["deeds"] = deeds
	packet["entities"] = _entities(world, speaker_id, speaker_name, facts, deeds)
	return packet


## Sorted keys, no extra whitespace. Insertion order does not change the string.
static func canonical(packet: Dictionary) -> String:
	return JSON.stringify(packet, "", true)


## Authored fallback. A summary joins [code]entries[/code] when that array is present.
static func fallback_text(kind: StringName, packet: Dictionary) -> String:
	if kind == &"journal_summary" and packet.get("entries", null) is Array:
		var lines: PackedStringArray = PackedStringArray()
		for item in packet["entries"]:
			lines.append(str(item))
		return "\n".join(lines)
	return str(packet.get("text", ""))


static func _take_fact(runtime: WyrdRuntime, line_id: String, key: String) -> Dictionary:
	var schema := runtime.content().schema
	var fact: WyrdFact = null
	if schema != null:
		fact = schema.lookup(key.split("."))
	if fact == null:
		runtime.trace_ai_packet_drop(line_id, key, "unknown")
		return {"keep": false}
	if not _player_knows(runtime, key):
		runtime.trace_ai_packet_drop(line_id, key, "not_known")
		return {"keep": false}
	return {"keep": true, "value": _known_value(runtime, key)}


static func _player_knows(runtime: WyrdRuntime, key: String) -> bool:
	if runtime.roles != null and runtime.roles.revealed(&"player", StringName(key)):
		return true
	if runtime.facts == null:
		return false
	return runtime.facts.get_in(StringName(key), &"known/player") != null


static func _known_value(runtime: WyrdRuntime, key: String) -> Variant:
	var role := _role_of_key(key)
	if role != &"" and runtime.roles != null and runtime.roles.revealed(&"player", StringName(key)):
		return String(runtime.roles.holder(role))
	var raw: Variant = null
	if runtime.facts != null:
		raw = runtime.facts.get_in(StringName(key), &"known/player")
	return _plain(raw)


static func _role_of_key(key: String) -> StringName:
	if not key.begins_with("role.") or not key.ends_with(".holder"):
		return &""
	var inner := key.substr(5, key.length() - 12)
	if inner.is_empty():
		return &""
	return StringName(inner)


static func _plain(raw: Variant) -> Variant:
	if raw is bool:
		return raw
	if typeof(raw) == TYPE_INT:
		return raw
	if typeof(raw) == TYPE_FLOAT:
		return raw
	if raw == null:
		return ""
	return String(raw)


static func _speaker_id(runtime: WyrdRuntime, entry: Dictionary, line_def: WyrdLineDef, given: StringName) -> String:
	var name := String(given)
	if name.is_empty():
		if str(entry.get("owner", "")) == "storylet":
			var story := runtime.content().storylets.get(str(entry.get("id", ""))) as WyrdStoryletDef
			if story != null:
				name = story.speaker
		elif line_def != null:
			name = line_def.speaker
		if runtime.roles != null and not name.is_empty():
			var held := runtime.roles.holder(StringName(name))
			if held != &"":
				name = String(held)
	if name.is_empty() or name == "any" or name == "narrator":
		return ""
	return name


static func _speaker_roles(runtime: WyrdRuntime, line_id: String, speaker_id: String) -> Array:
	var kept: Array = []
	if runtime.roles == null:
		return kept
	for role_id in runtime.roles.roles_of(StringName(speaker_id)):
		var fact_key := "role.%s.holder" % role_id
		if runtime.roles.revealed(&"player", StringName(fact_key)):
			kept.append(role_id)
		else:
			runtime.trace_ai_packet_drop(line_id, fact_key, "secret")
	return kept


static func _entities(world: WyrdWorldAdapter, speaker_id: String, speaker_name: String, facts: Dictionary, deeds: Array) -> Array:
	var names := {}
	if not speaker_id.is_empty():
		names[speaker_id] = speaker_name
	for value in facts.values():
		if not (value is String) or world == null:
			continue
		var id := StringName(value)
		if not world.exists(id):
			continue
		names[String(id)] = _entity_name(world, String(id))
	for deed in deeds:
		if not (deed is Dictionary) or world == null:
			continue
		var row: Dictionary = deed
		for field in ["actor", "target", "place"]:
			var deed_id := str(row.get(field, ""))
			if deed_id.is_empty() or not world.exists(StringName(deed_id)):
				continue
			names[deed_id] = _entity_name(world, deed_id)
	var ids: Array = names.keys()
	ids.sort()
	var rows: Array = []
	for id in ids:
		rows.append({"id": String(id), "name": String(names[id])})
	return rows


## At most five deeds the player knows, newest minute first, then higher id.
static func _gossip_deeds(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	if runtime.deeds == null:
		return rows
	var seen := {}
	for index in runtime.deeds.witness_indexes(&"player"):
		_take_deed(runtime, int(index), rows, seen)
	for item in runtime.deeds.believer_deeds(&"player"):
		if not (item is Dictionary):
			continue
		var deed_id := int((item as Dictionary).get("id", 0))
		var index := runtime.deeds.index_of(deed_id)
		if index < 0:
			continue
		_take_deed(runtime, index, rows, seen)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["minute"]) != int(b["minute"]):
			return int(a["minute"]) > int(b["minute"])
		return int(a["id"]) > int(b["id"])
	)
	if rows.size() > 5:
		rows.resize(5)
	return rows


static func _take_deed(runtime: WyrdRuntime, index: int, rows: Array, seen: Dictionary) -> void:
	var row := runtime.deeds.row_at(index)
	var deed_id := int(row.get("id", 0))
	if deed_id <= 0 or seen.has(deed_id):
		return
	seen[deed_id] = true
	rows.append({
		"actor": String(row.get("actor", "")),
		"how": _player_how(row),
		"id": deed_id,
		"minute": int(row.get("t", 0)),
		"place": String(row.get("place", "")),
		"target": String(row.get("target", "")),
		"verb": String(row.get("verb", "")),
	})


static func _player_how(row: Dictionary) -> String:
	var witnesses: PackedStringArray = row.get("witnesses", PackedStringArray())
	var modes: PackedStringArray = row.get("perception", PackedStringArray())
	for i in witnesses.size():
		if witnesses[i] != "player":
			continue
		if i < modes.size():
			return modes[i]
		return "saw"
	return "believed"


static func _entity_name(world: WyrdWorldAdapter, id: String) -> String:
	if world == null:
		return id
	var shown := world.display_name(StringName(id))
	if shown.is_empty():
		return id
	return shown


static func _world(runtime: WyrdRuntime) -> WyrdWorldAdapter:
	var found := runtime.adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
