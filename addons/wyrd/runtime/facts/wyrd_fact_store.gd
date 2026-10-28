class_name WyrdFactStore
extends RefCounted

## Stored facts, resolver cache, and perspectives.
##
## World values are [method Object.set] and [method Object.get], implemented
## here as [method _set] and [method _get]. Godot already owns those names, so
## a perspective argument cannot be added and [code]set[/code] cannot return a
## bool. [method set_in] and [method get_in] take [code]world[/code],
## [code]known/<agent>[/code], [code]believed/<agent>[/code], or
## [code]held/<group>[/code]. Only schema-declared stored facts can be learned,
## believed, or held. A missing fact reads as null. Conditions treat that as false.
##
## [signal fact_changed] fires only for prefixes passed to [method subscribe].
## Callables on this object are the runtime's hooks. They are not saved.

## Fires for a changed key whose prefix was passed to subscribe.
signal fact_changed(key: StringName, old_value: Variant, new_value: Variant)

## @experimental
var on_keys: Callable = Callable()
## @experimental
var tracer: Callable = Callable()
## Called after a [code]believed/[/code] or [code]held/[/code] value changes.
## [code]op[/code] is [code]believe[/code], [code]unbelieve[/code], [code]declare[/code], or [code]retract[/code].
## @experimental
var on_belief: Callable = Callable()
## [code]() -> void[/code]. The same change, with no row. Used to drop a cache without a trace.
## @experimental
var on_belief_touch: Callable = Callable()
## [code]() -> bool[/code]. When this is valid and false, [member on_belief] is not called.
## @experimental
var belief_trace_of: Callable = Callable()
## Called after a [code]known/[/code] value changes. [code]op[/code] is [code]learn[/code] or [code]forget[/code].
## @experimental
var on_knowledge: Callable = Callable()
## @experimental
var on_resolved: Callable = Callable()
## @experimental
var clock: Callable = Callable()
## @experimental
var resolver_of: Callable = Callable()
## [code]() -> Dictionary[/code] of fact key to scene, choice, and time. Not saved here.
## @experimental
var provenance_of: Callable = Callable()
## [code](fields, line)[/code]. Records one choice-summary read when tracing is on.
## @experimental
var on_choice_summary: Callable = Callable()
## @experimental
var runtime: WyrdRuntime

var _schema: WyrdFactSchema
var _world: Dictionary = {}
var _known: Dictionary = {}
var _believed: Dictionary = {}
var _held: Dictionary = {}
var _cache: Dictionary = {}
var _last: Dictionary = {}
var _reasons: Dictionary = {}
var _subs: PackedStringArray = PackedStringArray()
var _once: Dictionary = {}
var _quiet: bool = false
var _find_text := ""
var _find_fact: WyrdFact
## Evidence deadlines. Each row is actor, event, key, place, target, until, value.
## [code]until[/code] is the game minute that clears the world fact, or [code]-1[/code].
var _evidence: Array = []


## @experimental
func bind_schema(schema: WyrdFactSchema) -> void:
	_schema = schema
	_find_text = ""
	_find_fact = null
	clear_values()


const _SUMMARY_FILTERS: PackedStringArray = ["choice", "from", "prefix", "scene", "to"]


## Rows from the provenance map. [param query] may set [code]scene[/code],
## [code]choice[/code], [code]prefix[/code], [code]from[/code], and [code]to[/code].
## An omitted field does not filter. [code]from[/code] and [code]to[/code] are
## inclusive game minutes. One [code]choice_summary[/code] line is logged when tracing is on.
## @experimental
func choice_summary(query: Dictionary = {}) -> Array:
	if not _summary_query(query):
		return []
	var exported := {}
	if provenance_of.is_valid():
		var raw: Variant = provenance_of.call()
		if raw is Dictionary:
			exported = raw
	var rows: Array = []
	var keys: Array = exported.keys()
	keys.sort()
	for key in keys:
		var item: Variant = exported[key]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var name := String(key)
		if not _summary_keeps(name, row, query):
			continue
		rows.append({
			"choice": String(row.get("choice", "")),
			"key": name,
			"recap": _summary_recap(name),
			"scene": String(row.get("scene", "")),
			"time": int(row.get("time", 0)),
		})
	_summary_trace(query, rows.size())
	return rows


## Sorted table of [method choice_summary]. Columns are key, scene, choice, time, and recap.
## @experimental
func render_choice_summary(query: Dictionary = {}) -> String:
	var found := choice_summary(query)
	var header := PackedStringArray(["key", "scene", "choice", "time", "recap"])
	var lines: Array = []
	for item in found:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		lines.append(PackedStringArray([
			str(row.get("key", "")),
			str(row.get("scene", "")),
			str(row.get("choice", "")),
			str(int(row.get("time", 0))),
			"true" if bool(row.get("recap", false)) else "false",
		]))
	return _summary_table(header, lines)


func _summary_query(query: Dictionary) -> bool:
	for key in query.keys():
		var name := String(key)
		if not _SUMMARY_FILTERS.has(name):
			push_error("Wyrd.facts.choice_summary: unknown filter \"%s\"" % name)
			return false
		if name == "from" or name == "to":
			var value: Variant = query[key]
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				push_error("Wyrd.facts.choice_summary: %s must be a number" % name)
				return false
			continue
		if not (query[key] is String):
			push_error("Wyrd.facts.choice_summary: %s must be text" % name)
			return false
	return true


func _summary_keeps(key: String, row: Dictionary, query: Dictionary) -> bool:
	if query.has("scene") and String(row.get("scene", "")) != String(query["scene"]):
		return false
	if query.has("choice") and String(row.get("choice", "")) != String(query["choice"]):
		return false
	if query.has("prefix") and not key.begins_with(String(query["prefix"])):
		return false
	var minute := int(row.get("time", 0))
	if query.has("from") and minute < int(query["from"]):
		return false
	if query.has("to") and minute > int(query["to"]):
		return false
	return true


func _summary_recap(key: String) -> bool:
	var runtime: Variant = null
	if provenance_of.is_valid():
		runtime = provenance_of.get_object()
	if runtime is WyrdEffects and (runtime as WyrdEffects).runtime != null:
		return (runtime as WyrdEffects).runtime.fact_marked_recap(key)
	return false


func _summary_trace(query: Dictionary, rows: int) -> void:
	if not on_choice_summary.is_valid():
		return
	var scene := String(query["scene"]) if query.has("scene") else ""
	var choice := String(query["choice"]) if query.has("choice") else ""
	var prefix := String(query["prefix"]) if query.has("prefix") else ""
	var scene_token := scene if query.has("scene") else "-"
	var choice_token := choice if query.has("choice") else "-"
	var prefix_token := prefix if query.has("prefix") else "-"
	var from_token := str(int(query["from"])) if query.has("from") else "-"
	var to_token := str(int(query["to"])) if query.has("to") else "-"
	var fields := {
		"choice": choice_token,
		"from": from_token,
		"key": prefix,
		"path": scene,
		"prefix": prefix_token,
		"rows": rows,
		"scene": scene_token,
		"to": to_token,
	}
	var line := "wyrd choice_summary scene=%s choice=%s prefix=%s from=%s to=%s rows=%d" % [
		scene_token, choice_token, prefix_token, from_token, to_token, rows
	]
	on_choice_summary.call(fields, line)


func _summary_table(header: PackedStringArray, rows: Array) -> String:
	var width := PackedInt32Array()
	width.resize(header.size())
	for i in header.size():
		width[i] = header[i].length()
	for item in rows:
		var cells: PackedStringArray = item
		for i in header.size():
			if cells[i].length() > width[i]:
				width[i] = cells[i].length()
	var lines := PackedStringArray()
	lines.append(_summary_line(header, width))
	for item in rows:
		lines.append(_summary_line(item, width))
	return "\n".join(lines) + "\n"


func _summary_line(cells: PackedStringArray, width: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for i in cells.size():
		parts.append(cells[i].rpad(width[i]))
	return "  ".join(parts)


## @experimental
func export_state() -> Dictionary:
	var out := {
		"believed": _export_layers(_believed),
		"held": _export_layers(_held),
		"known": _export_layers(_known),
		"world": _export_bag(_world),
	}
	if not _evidence.is_empty():
		out["evidence"] = _export_evidence()
	return out


## Empty when [param value] is acceptable for a saved [param key], or the type word when it is not.
## An unknown key is acceptable here. Import still reports a missing schema entry.
## @experimental
func saved_type_issue(key: String, value: Variant) -> String:
	var fact := _find(key)
	if fact == null:
		return ""
	var type_name := String(fact.type_name)
	if type_name == "int":
		if typeof(value) == TYPE_INT:
			return ""
		if typeof(value) == TYPE_FLOAT and not is_nan(value) and not is_inf(value) and value == floor(value):
			return ""
		return "int"
	if type_name == "bool":
		if typeof(value) == TYPE_BOOL:
			return ""
		return "bool"
	if type_name == "float":
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return ""
		return "float"
	if type_name == "symbol":
		if value is String or value is StringName:
			return ""
		return "string"
	return ""


## @experimental
func import_state(data: Dictionary) -> void:
	clear_values()
	_quiet = true
	var world_value: Variant = data.get("world", {})
	var world: Dictionary = world_value if world_value is Dictionary else {}
	var world_keys: Array = world.keys()
	world_keys.sort()
	for key in world_keys:
		set_in(StringName(str(key)), _saved_value(String(key), world[key]))
	var known_value: Variant = data.get("known", {})
	var known: Dictionary = known_value if known_value is Dictionary else {}
	var agents: Array = known.keys()
	agents.sort()
	for agent in agents:
		var bag: Variant = known[agent]
		if not (bag is Dictionary):
			continue
		var perspective := StringName("known/%s" % String(agent))
		var keys: Array = (bag as Dictionary).keys()
		keys.sort()
		for key in keys:
			var text := String(key)
			var value: Variant = _saved_value(text, (bag as Dictionary)[key])
			if _find(text) == null:
				remember(StringName(text), value, perspective)
			else:
				set_in(StringName(text), value, perspective)
	_import_beliefs(data.get("believed", {}), "believed")
	_import_beliefs(data.get("held", {}), "held")
	_import_evidence(data.get("evidence", []))
	_quiet = false


func _import_beliefs(raw: Variant, layer: String) -> void:
	if not (raw is Dictionary):
		return
	var owners: Array = (raw as Dictionary).keys()
	owners.sort()
	for owner in owners:
		var bag: Variant = (raw as Dictionary)[owner]
		if not (bag is Dictionary):
			continue
		var perspective := StringName("%s/%s" % [layer, String(owner)])
		var keys: Array = (bag as Dictionary).keys()
		keys.sort()
		for key in keys:
			var text := String(key)
			set_in(StringName(text), _saved_value(text, (bag as Dictionary)[key]), perspective)


func _export_evidence() -> Array:
	var rows: Array = _evidence.duplicate(true)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("key", "")) < str(b.get("key", "")))
	var out: Array = []
	for row in rows:
		out.append({
			"actor": str(row.get("actor", "")),
			"event": str(row.get("event", "")),
			"key": str(row.get("key", "")),
			"place": str(row.get("place", "")),
			"target": str(row.get("target", "")),
			"until": int(row.get("until", -1)),
			"value": _plain_fact(row.get("value")),
		})
	return out


func _import_evidence(raw: Variant) -> void:
	if not (raw is Array):
		return
	for item in raw:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var key := String(row.get("key", ""))
		if key.is_empty():
			continue
		note_evidence(
			key,
			_saved_value(key, row.get("value")),
			WyrdSave.text_of(row.get("place", ""), ""),
			WyrdSave._whole(row.get("until", -1), -1),
			WyrdSave.text_of(row.get("event", ""), ""),
			WyrdSave.text_of(row.get("actor", ""), ""),
			WyrdSave.text_of(row.get("target", ""), "")
		)


func _clear_world_key(text: String) -> void:
	if not _world.has(text):
		return
	var old_value: Variant = _world[text]
	_world.erase(text)
	_notify(PackedStringArray([text]))
	_emit(text, old_value, null, true)


func _export_layers(layers: Dictionary) -> Dictionary:
	var out := {}
	var owners: Array = layers.keys()
	owners.sort()
	for owner in owners:
		var bag: Dictionary = layers[owner]
		if bag.is_empty():
			continue
		out[String(owner)] = _export_bag(bag)
	return out


func _export_bag(bag: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = bag.keys()
	keys.sort()
	for key in keys:
		out[String(key)] = _plain_fact(bag[key])
	return out


func _plain_fact(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	return value


func _saved_value(key: String, value: Variant) -> Variant:
	var fact := _find(key)
	if fact == null:
		return value if not (value is String) else value
	if fact.type_name == &"int" and typeof(value) == TYPE_FLOAT:
		return int(value)
	if fact.type_name == &"float" and typeof(value) == TYPE_INT:
		return float(value)
	if fact.type_name == &"symbol":
		return StringName(str(value))
	return value


## @experimental
func clear_values() -> void:
	_world.clear()
	_known.clear()
	_believed.clear()
	_held.clear()
	_cache.clear()
	_last.clear()
	_reasons.clear()
	_evidence.clear()


## Replaces any deadline already stored for [param key]. [param until] of [code]-1[/code] does not decay.
## @experimental
func note_evidence(
	key: String,
	value: Variant,
	place: String,
	until: int,
	event_name: String,
	actor: String,
	target: String
) -> void:
	var next: Array = []
	for row in _evidence:
		if str(row.get("key", "")) == key:
			continue
		next.append(row)
	next.append({
		"actor": actor,
		"event": event_name,
		"key": key,
		"place": place,
		"target": target,
		"until": until,
		"value": value,
	})
	_evidence = next


## @experimental
func evidence_rows() -> Array:
	return _evidence.duplicate(true)


## Drops deadlines that have come due. Clears the world fact when it still holds the evidence value.
## @experimental
func decay_evidence(now: int) -> void:
	if _evidence.is_empty():
		return
	var next: Array = []
	for row in _evidence:
		var until := int(row.get("until", -1))
		if until < 0 or now < until:
			next.append(row)
			continue
		var key := String(row.get("key", ""))
		var current: Variant = get_in(StringName(key), &"world")
		if current != null and current == row.get("value"):
			_clear_world_key(key)
	_evidence = next


## @experimental
func subscribe(prefix: StringName) -> void:
	var text := String(prefix)
	if not _subs.has(text):
		_subs.append(text)


## Sorted keys that currently hold a world value. Resolved facts are not included.
## The returned array is a copy.
## @experimental
func world_keys() -> PackedStringArray:
	var names: Array = _world.keys()
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append(str(name))
	return out


## @experimental
func get_in(key: StringName, perspective: StringName = &"world") -> Variant:
	var text := String(key)
	var kind := _kind(perspective)
	if kind == "known" or kind == "believed" or kind == "held":
		var bag := _layer_bag(_layers(kind), _who(perspective), false)
		if bag.has(text):
			return bag[text]
		return null
	if kind != "world":
		return null
	var fact := _find(text)
	if fact == null or fact.origin == &"stored":
		if _world.has(text):
			return _world[text]
		return null
	if text.contains("{"):
		return null
	return _resolved(fact, text)


## Stores a value in one perspective. Returns false when the perspective, key, or type is refused.
func set_in(key: StringName, new_value: Variant, perspective: StringName = &"world") -> bool:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var text := String(key)
	var kind := _kind(perspective)
	if kind != "world" and kind != "known" and kind != "believed" and kind != "held":
		if _logs_host():
			_host_mark("facts.set_in", [key, new_value, perspective])
		_refuse("perspective", text, "unknown perspective %s" % String(perspective))
		return false
	if _key_refused(text):
		if _logs_host():
			_host_mark("facts.set_in", [key, new_value, perspective])
		_stored_key(text)
		return false
	var fact := _find(text)
	if not _type_ok(fact.type_name, new_value):
		if _logs_host():
			_host_mark("facts.set_in", [key, new_value, perspective])
		_refuse("type", text, "expected %s" % String(fact.type_name))
		return false
	var stored := _coerce(fact.type_name, new_value)
	var bag := _world if kind == "world" else _layer_bag(_layers(kind), _who(perspective), true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	if _logs_host():
		_host_mark("facts.set_in", [key, new_value, perspective])
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
	if kind == "believed" or kind == "held":
		_log_belief("believe" if kind == "believed" else "declare", _who(perspective), text, stored)
	elif kind == "known":
		_log_knowledge("learn", _who(perspective), text, stored)
	return true


## Removes one [code]known/[/code], [code]believed/[/code], or [code]held/[/code] key. A missing key is a no-op.
## @experimental
func clear_in(key: StringName, perspective: StringName) -> bool:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var text := String(key)
	var kind := _kind(perspective)
	if kind != "known" and kind != "believed" and kind != "held":
		if _logs_host():
			_host_mark("facts.clear_in", [key, perspective])
		_refuse("perspective", text, "clear only removes known/, believed/, or held/")
		return false
	if _key_refused(text):
		if _logs_host():
			_host_mark("facts.clear_in", [key, perspective])
		_stored_key(text)
		return false
	var who := _who(perspective)
	var layers := _layers(kind)
	if not layers.has(who):
		return true
	var bag: Dictionary = layers[who]
	if not bag.has(text):
		return true
	if _logs_host():
		_host_mark("facts.clear_in", [key, perspective])
	var old_value: Variant = bag[text]
	bag.erase(text)
	if bag.is_empty():
		layers.erase(who)
	_notify(PackedStringArray([text]))
	_emit(text, old_value, null, true)
	if kind == "known":
		_log_knowledge("forget", who, text, null)
	else:
		_log_belief("unbelieve" if kind == "believed" else "retract", who, text, null)
	return true


func _logs_host() -> bool:
	return runtime != null and runtime._host_logs()


func _host_mark(call_name: String, args: Array) -> void:
	if runtime != null:
		runtime._host_mark(call_name, args)


func _key_refused(text: String) -> bool:
	if text.is_empty() or text.contains("{"):
		return true
	var fact := _find(text)
	return fact == null or fact.origin != &"stored"


func _stored_key(text: String) -> bool:
	if text.is_empty() or text.contains("{"):
		_refuse("key", text, "not a concrete fact key")
		return false
	var fact := _find(text)
	if fact == null:
		_refuse("unknown", text, "no schema entry")
		return false
	if fact.origin != &"stored":
		_refuse("resolved", text, "resolved facts are not writable")
		return false
	return true


## Writes a [code]known/[/code] value that is not a schema fact. Role reveals use this.
## @experimental
func remember(key: StringName, value: Variant, perspective: StringName) -> bool:
	var text := String(key)
	if _kind(perspective) != "known":
		_refuse("perspective", text, "remember only writes known/")
		return false
	if text.is_empty():
		_refuse("key", text, "not a concrete fact key")
		return false
	var stored: Variant = StringName(str(value)) if value is String or value is StringName else value
	var bag := _layer_bag(_known, _who(perspective), true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
	_log_knowledge("learn", _who(perspective), text, stored)
	return true


## Drops cached concrete keys under [param prefix]. A pattern key such as
## [code]npc.{id}.alive[/code] drops every cached concrete key of that pattern.
## [param reason] is the event name recorded for the playtest, or empty.
func invalidate(prefix: StringName, reason: StringName = &"") -> PackedStringArray:
	var text := String(prefix)
	var dropped := PackedStringArray()
	if text.is_empty():
		return dropped
	var doomed := {}
	for cached in _cache.keys():
		var cached_key := str(cached)
		if _prefix_hit(cached_key, text) or _pattern_covers(text, cached_key):
			doomed[cached_key] = true
	var names: Array = doomed.keys()
	names.sort()
	for cached_key in names:
		var key := String(cached_key)
		_remember(key)
		_cache.erase(key)
		dropped.append(key)
		_note_reason(key, reason)
	if _schema != null:
		for fact in _schema.entries:
			if fact.origin != &"resolved":
				continue
			var hit := _prefix_hit(fact.key, text)
			if not hit and fact.is_pattern():
				hit = _matches(fact, text) or fact.key == text or fact.key.begins_with(text + ".")
			if hit:
				_note_reason(fact.key, reason)
				if not dropped.has(fact.key):
					dropped.append(fact.key)
	_notify(dropped)
	return dropped


## Drops every [code]on_event[/code] fact bound to [param event_name], including
## every concrete cache of a pattern fact. The returned keys are sorted.
## @experimental
func invalidate_event(event_name: StringName) -> PackedStringArray:
	var found := {}
	if _schema == null:
		return PackedStringArray()
	for fact in _schema.entries:
		if fact.invalidate != &"on_event" or StringName(fact.invalidate_arg) != event_name:
			continue
		for key in invalidate(StringName(fact.key), event_name):
			found[String(key)] = true
		_note_reason(fact.key, event_name)
	return _sorted_keys(found)


## [code]mode[/code] is the schema invalidation ([code]on_event[/code], [code]poll[/code],
## [code]per_query[/code], [code]manual[/code]) or [code]absent[/code]. [code]event[/code]
## is the last invalidate reason. [code]cached[/code] is false for [code]per_query[/code].
## @experimental
func cache_view(key: String) -> Dictionary:
	var fact := _find(key)
	var mode := "absent"
	if fact != null and fact.origin == &"resolved":
		mode = String(fact.invalidate) if fact.invalidate != &"" else "manual"
	var event := String(_reasons.get(key, ""))
	if event.is_empty() and fact != null:
		event = String(_reasons.get(fact.key, ""))
	return {"cached": _cache.has(key), "event": event, "mode": mode}


## @experimental
func refresh_poll(now: int) -> void:
	var doomed := PackedStringArray()
	for cached in _cache.keys():
		var row: Dictionary = _cache[cached]
		if str(row.get("mode", "")) != "poll":
			continue
		var every := int(row.get("every", 0))
		if every > 0 and now - int(row.get("at", 0)) >= every:
			doomed.append(str(cached))
	if doomed.is_empty():
		return
	for cached_key in doomed:
		_remember(cached_key)
		_cache.erase(cached_key)
	_notify(doomed)


func _get(property: StringName) -> Variant:
	return get_in(property, &"world")


func _set(property: StringName, value: Variant) -> bool:
	set_in(property, value, &"world")
	return true


func _resolved(fact: WyrdFact, concrete: String) -> Variant:
	if fact.invalidate != &"per_query" and _cache.has(concrete):
		return (_cache[concrete] as Dictionary)["value"]
	var resolved := _call_resolver(fact, concrete)
	if on_resolved.is_valid():
		on_resolved.call(concrete, resolved)
	if fact.invalidate == &"per_query":
		return resolved
	var had := _last.has(concrete)
	var old_value: Variant = _last[concrete] if had else null
	_cache[concrete] = {
		"at": _now(),
		"every": _poll_every(fact),
		"mode": String(fact.invalidate) if fact.invalidate != &"" else "manual",
		"value": resolved,
	}
	if had:
		_last.erase(concrete)
		if old_value != resolved:
			_emit(concrete, old_value, resolved, true)
	return resolved


func _call_resolver(fact: WyrdFact, concrete: String) -> Variant:
	var dot := fact.resolver.find(".")
	if dot <= 0:
		_once_error(fact.resolver, "resolver \"%s\" is missing an adapter" % fact.resolver)
		return null
	var head := fact.resolver.substr(0, dot)
	var method := fact.resolver.substr(dot + 1)
	var adapter: Object = resolver_of.call(head) if resolver_of.is_valid() else null
	if adapter == null or not adapter.has_method(method):
		_once_error(fact.resolver, "resolver \"%s\" is not on an adapter" % fact.resolver)
		return null
	var parts := concrete.split(".")
	if parts.size() != fact.segments.size():
		return null
	var args: Array = []
	for i in fact.segments.size():
		if fact.segments[i].begins_with("{"):
			args.append(StringName(parts[i]))
	return adapter.callv(method, args)


func _find(concrete: String) -> WyrdFact:
	if concrete == _find_text:
		return _find_fact
	if _schema == null or concrete.is_empty():
		_find_text = concrete
		_find_fact = null
		return null
	var found := _schema.lookup(concrete.split("."))
	_find_text = concrete
	_find_fact = found
	return found


func _kind(perspective: StringName) -> String:
	var text := String(perspective)
	if text == "world":
		return "world"
	var slash := text.find("/")
	if slash <= 0:
		return "bad"
	var head := text.substr(0, slash)
	if text.substr(slash + 1).is_empty():
		return "bad"
	if head == "known" or head == "believed" or head == "held":
		return head
	return "bad"


func _who(perspective: StringName) -> String:
	var text := String(perspective)
	var slash := text.find("/")
	if slash < 0:
		return ""
	return text.substr(slash + 1)


func _layers(kind: String) -> Dictionary:
	if kind == "known":
		return _known
	if kind == "believed":
		return _believed
	return _held


func _layer_bag(layers: Dictionary, who: String, create: bool) -> Dictionary:
	if who.is_empty():
		return {}
	if not layers.has(who):
		if not create:
			return {}
		var created := {}
		layers[who] = created
		return created
	return layers[who]


func _log_belief(op: String, who: String, key: String, value: Variant) -> void:
	if _quiet:
		return
	if on_belief_touch.is_valid():
		on_belief_touch.call()
	if not on_belief.is_valid():
		return
	if belief_trace_of.is_valid() and not bool(belief_trace_of.call()):
		return
	on_belief.call({"key": key, "op": op, "value": value, "who": who})


func _log_knowledge(op: String, who: String, key: String, value: Variant) -> void:
	if _quiet or not on_knowledge.is_valid():
		return
	on_knowledge.call({"key": key, "op": op, "value": value, "who": who})


func _type_ok(type_name: StringName, new_value: Variant) -> bool:
	match String(type_name):
		"bool":
			return new_value is bool
		"int":
			return typeof(new_value) == TYPE_INT
		"float":
			return new_value is float or typeof(new_value) == TYPE_INT
		"symbol":
			return new_value is String or new_value is StringName
		_:
			return false


func _coerce(type_name: StringName, new_value: Variant) -> Variant:
	if type_name == &"float" and typeof(new_value) == TYPE_INT:
		return float(new_value)
	if type_name == &"symbol":
		return StringName(str(new_value))
	return new_value


func _emit(key: String, old_value: Variant, new_value: Variant, had_old: bool) -> void:
	if had_old and old_value == new_value:
		return
	if not _subscribed(key):
		return
	fact_changed.emit(StringName(key), old_value if had_old else null, new_value)


func _subscribed(key: String) -> bool:
	for prefix in _subs:
		if prefix.is_empty() or key == prefix or key.begins_with(prefix + "."):
			return true
	return false


func _notify(keys: PackedStringArray) -> void:
	if keys.is_empty() or not on_keys.is_valid():
		return
	on_keys.call(keys)


func _remember(key: String) -> void:
	if _cache.has(key):
		_last[key] = (_cache[key] as Dictionary)["value"]


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _poll_every(fact: WyrdFact) -> int:
	if fact.invalidate != &"poll" or not fact.invalidate_arg.is_valid_int():
		return 0
	return int(fact.invalidate_arg)


func _prefix_hit(key: String, prefix: String) -> bool:
	return key == prefix or key.begins_with(prefix + ".")


## True when [param prefix] is a pattern fact key, or a parent of one, and
## [param concrete] is a cached value of that pattern.
func _pattern_covers(prefix: String, concrete: String) -> bool:
	if _schema == null or concrete.contains("{"):
		return false
	for fact in _schema.entries:
		if fact.origin != &"resolved" or not fact.is_pattern():
			continue
		if fact.key != prefix and not fact.key.begins_with(prefix + "."):
			continue
		if _matches(fact, concrete):
			return true
	return false


func _note_reason(key: String, reason: StringName) -> void:
	if reason != &"":
		_reasons[key] = String(reason)


func _sorted_keys(found: Dictionary) -> PackedStringArray:
	var names: Array = found.keys()
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append(String(name))
	return out


func _matches(fact: WyrdFact, concrete: String) -> bool:
	var parts := concrete.split(".")
	if parts.size() != fact.segments.size():
		return false
	for i in parts.size():
		var segment := fact.segments[i]
		if segment.begins_with("{"):
			continue
		if segment != parts[i]:
			return false
	return true


func _refuse(kind: String, key: String, detail: String) -> void:
	push_error("WyrdFactStore: %s (%s)." % [detail, key])
	_trace(kind, key, detail)


func _once_error(resolver: String, detail: String) -> void:
	if _once.has(resolver):
		return
	_once[resolver] = true
	push_error("WyrdFactStore: %s." % detail)
	_trace("resolver", resolver, detail)


func _trace(kind: String, key: String, detail: String) -> void:
	if tracer.is_valid():
		tracer.call({"detail": detail, "key": key, "kind": kind})
