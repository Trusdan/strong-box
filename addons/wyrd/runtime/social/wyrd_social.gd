class_name WyrdSocial
extends RefCounted

## Relationship baselines, deed axes, and disposition.
##
## @experimental
## Kinds and baselines are stored. Axes add a configured verb delta times the
## deed's decayed weight. A deed counts for [code]axis(observer, subject)[/code]
## when [code]subject[/code] did it and [code]observer[/code] was the target or
## a witness. A kind the observer holds toward the subject multiplies that
## delta by [method WyrdConfig.kind_scale]. Several matching kinds multiply.
## The baseline is not scaled. The default disposition is
## [code]disposition_default + affinity / 2[/code], clamped to 0..100. A host
## may [method register_formula]; the callable receives [code](a, b, axes)[/code]
## and is not saved. [method reputation] is the mean disposition of a group's
## members toward the subject. It is derived, not saved.
## Axes, disposition, reputation, and [method path_exists] are cached for the
## current time bucket. [method set_cache] false recomputes and does not store.
## A deed, relationship, membership, config, or bucket change drops the entries.
## An invalidation drops every entry and queues no [code]cache_refresh[/code] unit.
## Entries refill on read. The cache is not saved.

var deeds: WyrdDeedLog
var runtime: WyrdRuntime
var config_of: Callable = Callable()
var formula: Callable = Callable()
var on_changed: Callable = Callable()
## [code](group) -> PackedStringArray[/code]. Not saved.
## Replacing the callable drops the reputation cache.
var members_of: Callable = Callable():
	set(value):
		members_of = value
		if _booted:
			_members_gen += 1
			_force_invalidate("members")
## [code](subject, group, value, members)[/code]. Not saved.
var on_reputation: Callable = Callable()
## [code](token: String)[/code]. One cache entry for the scheduler. Not saved.
var enqueue_cache: Callable = Callable()
## [code](fields: Dictionary)[/code]. Not saved. The runtime logs it when tracing is on.
var on_cache: Callable = Callable()
## [code]() -> bool[/code]. When this is valid and false, cache hits do not build a trace row.
var tracing_of: Callable = Callable()
## [code](fields)[/code]. Logs one [code]baseline_adjust[/code] line. Not saved.
var trace_of: Callable = Callable()
var _target_cache: Dictionary = {}
var _target_rev: int = -1

var _kinds: Dictionary = {}
var _baseline: Dictionary = {}
var _rev: int = 1
var _members_gen: int = 1
var _cache_on: bool = true
var _cache_ready: bool = false
var _seen_bucket: int = 0
var _seen_rev: int = 0
var _seen_deed: int = 0
var _seen_members: int = 0
var _seen_config: int = 0
var _axis_cache: Dictionary = {}
var _disp_cache: Dictionary = {}
var _rep_cache: Dictionary = {}
var _path_cache: Dictionary = {}
var _booted: bool = false
var _stamp_ready := false
var _stamp_cfg: WyrdConfig
var _stamp_default := 0
var _stamp_hour := 0
var _stamp_half_verbs := PackedStringArray()
var _stamp_half_minutes := PackedFloat64Array()
var _stamp_axis_verbs := PackedStringArray()
var _stamp_axis_names := PackedStringArray()
var _stamp_axis_deltas := PackedFloat64Array()
var _stamp_kind_kinds := PackedStringArray()
var _stamp_kind_axes := PackedStringArray()
var _stamp_kind_values := PackedFloat64Array()
var _stamp_value := 0


func _init() -> void:
	_booted = true


func export_state() -> Dictionary:
	var kinds: Array = []
	var sources: Array = _kinds.keys()
	sources.sort()
	for source in sources:
		var outgoing: Dictionary = _kinds[source]
		var targets: Array = outgoing.keys()
		targets.sort()
		for target in targets:
			var bag: Dictionary = outgoing[target]
			var names: Array = bag.keys()
			names.sort()
			for kind in names:
				kinds.append({"kind": String(kind), "source": String(source), "target": String(target)})
	var baselines: Array = []
	var edges: Array = _baseline.keys()
	edges.sort()
	for edge in edges:
		var parts := String(edge).split("\t")
		if parts.size() != 3:
			continue
		baselines.append({
			"axis": parts[2],
			"source": parts[0],
			"target": parts[1],
			"value": float(_baseline[edge]),
		})
	return {"baselines": baselines, "kinds": kinds}


func import_state(data: Dictionary) -> void:
	clear_state()
	for item in data.get("kinds", []):
		if item is Dictionary:
			var row: Dictionary = item
			set_kind(StringName(str(row.get("source", ""))), StringName(str(row.get("target", ""))), StringName(str(row.get("kind", ""))))
	for item in data.get("baselines", []):
		if item is Dictionary:
			var row: Dictionary = item
			set_baseline(
				StringName(str(row.get("source", ""))),
				StringName(str(row.get("target", ""))),
				StringName(str(row.get("axis", ""))),
				WyrdSave.number_of(row.get("value", 0.0), 0.0)
			)


func clear_state() -> void:
	_kinds.clear()
	_baseline.clear()
	_rev += 1
	_clear_entries()
	_cache_ready = false


func register_formula(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdSocial.register_formula: missing callable")
		return
	formula = fn
	_touch("formula")


func set_kind(source: StringName, target: StringName, kind: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if source == &"" or target == &"" or kind == &"":
		push_error("WyrdSocial.set_kind: missing source, target, or kind")
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("social.set_kind", [source, target, kind])
	if not _kinds.has(source):
		_kinds[source] = {}
	var outgoing: Dictionary = _kinds[source]
	if not outgoing.has(target):
		outgoing[target] = {}
	(outgoing[target] as Dictionary)[kind] = true
	_touch()


## A missing kind is a no-op.
func clear_kind(source: StringName, target: StringName, kind: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if not has_kind(source, target, kind):
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("social.clear_kind", [source, target, kind])
	var outgoing: Dictionary = _kinds[source]
	var bag: Dictionary = outgoing[target]
	bag.erase(kind)
	if bag.is_empty():
		outgoing.erase(target)
	if outgoing.is_empty():
		_kinds.erase(source)
	_touch()


func has_kind(source: StringName, target: StringName, kind: StringName) -> bool:
	if not _kinds.has(source):
		return false
	var outgoing: Dictionary = _kinds[source]
	if not outgoing.has(target):
		return false
	return (outgoing[target] as Dictionary).has(kind)


func targets(source: StringName, kind: StringName) -> PackedStringArray:
	if _target_rev != _rev:
		_target_cache.clear()
		_target_rev = _rev
	var key := "%s\t%s" % [String(source), String(kind)]
	if _target_cache.has(key):
		return _target_cache[key] as PackedStringArray
	var rows := PackedStringArray()
	if not _kinds.has(source):
		_target_cache[key] = rows
		return rows
	var outgoing: Dictionary = _kinds[source]
	for target in outgoing.keys():
		if (outgoing[target] as Dictionary).has(kind):
			rows.append(String(target))
	rows.sort()
	_target_cache[key] = rows
	return rows


func set_baseline(source: StringName, target: StringName, axis_name: StringName, value: float) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null and runtime._host_logs():
		runtime._host_mark("social.set_baseline", [source, target, axis_name, value])
	_baseline[_edge(source, target, axis_name)] = value
	_touch()


## Adds [param n] to the stored baseline. A missing baseline counts as 0.
## Zero does not touch the cache. Kind scale does not apply. Load does not call this.
func adjust_baseline(a: StringName, b: StringName, axis_name: StringName, n: float) -> bool:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null and runtime._host_logs():
		runtime._host_mark("social.adjust_baseline", [a, b, axis_name, n])
	if a == &"" or b == &"":
		_trace_adjust(a, b, axis_name, 0.0, 0.0, false, "no_entity")
		push_warning("WyrdSocial.adjust_baseline: missing entity")
		return false
	var old := _base(a, b, axis_name)
	if a == b:
		_trace_adjust(a, b, axis_name, old, old, false, "self_edge")
		push_warning("WyrdSocial.adjust_baseline: \"%s\" is a self edge" % String(a))
		return false
	if n == 0.0:
		_trace_adjust(a, b, axis_name, old, old, false, "zero")
		push_warning("WyrdSocial.adjust_baseline: zero")
		return false
	var next := old + n
	set_baseline(a, b, axis_name, next)
	_trace_adjust(a, b, axis_name, old, next, true, "adjusted")
	return true


func _trace_adjust(a: StringName, b: StringName, axis_name: StringName, old: float, next: float, ok: bool, reason: String) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call({
		"a": String(a),
		"axis": String(axis_name),
		"b": String(b),
		"from": str(old),
		"ok": "true" if ok else "false",
		"reason": reason,
		"to": str(next),
		"who": String(a),
	})


## A missing baseline is a no-op. Absence is the same as a baseline of 0.
func clear_baseline(source: StringName, target: StringName, axis_name: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var key := _edge(source, target, axis_name)
	if not _baseline.has(key):
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("social.clear_baseline", [source, target, axis_name])
	_baseline.erase(key)
	_touch()


## Drops cached reputation. Hosts call this when membership changes.
## [method WyrdRuntime.invalidate_groups] does that.
func invalidate_members() -> void:
	_members_gen += 1
	_force_invalidate("members")


## False recomputes axes, disposition, reputation, and [method path_exists].
## The stored entries are dropped. Turning it back on fills them again on read.
func set_cache(enabled: bool) -> void:
	_cache_on = enabled
	if not enabled:
		_clear_entries()
		_cache_ready = false


func cache_enabled() -> bool:
	return _cache_on


func cache_entries() -> int:
	return _axis_cache.size() + _disp_cache.size() + _rep_cache.size() + _path_cache.size()


## Key text plus 8 bytes for an axis or reputation value, or 4 for disposition
## and [method path_exists]. This is not process memory.
func cache_bytes() -> int:
	return _key_bytes(_axis_cache, 8) + _key_bytes(_disp_cache, 4) + _key_bytes(_rep_cache, 8) + _key_bytes(_path_cache, 4)


## Writes the affinity and disposition keys for every ordered pair. No deeds run.
func fill_pair_matrix(count: int) -> void:
	for i in count:
		var source := "dock_hand_%03d" % i
		for j in count:
			if i == j:
				continue
			var target := "dock_hand_%03d" % j
			_axis_cache["axis\t%s\t%s\taffinity" % [source, target]] = 0.0
			_disp_cache["disp\t%s\t%s" % [source, target]] = 50


## Notices a deed, config, or time-bucket change. An invalidation drops every entry and queues no unit. Entries refill on read.
func sync_cache() -> void:
	_ensure()


## Rebuilds one queued entry. A fresh entry is left as it is.
func rebuild_cached(token: String) -> void:
	if not _cache_on or token.is_empty():
		return
	_ensure()
	if _contains(token):
		return
	_read_token(token)


func _touch(reason: String = "relation") -> void:
	_rev += 1
	_force_invalidate(reason)
	if on_changed.is_valid():
		on_changed.call()


func axis(source: StringName, target: StringName, axis_name: StringName) -> float:
	if not _cache_on or source == &"" or target == &"" or axis_name == &"":
		return _axis_raw(source, target, axis_name)
	_ensure()
	return _remember_axis(source, target, axis_name)


func _remember_axis(source: StringName, target: StringName, axis_name: StringName) -> float:
	var key := "axis\t%s\t%s\t%s" % [String(source), String(target), String(axis_name)]
	if _axis_cache.has(key):
		_emit_cache("hit", "axis", String(target), String(source), String(axis_name), 0)
		return float(_axis_cache[key])
	var value := _axis_raw(source, target, axis_name)
	_axis_cache[key] = value
	_emit_cache("miss", "axis", String(target), String(source), String(axis_name), 0)
	return value


func _axis_raw(source: StringName, target: StringName, axis_name: StringName) -> float:
	var total := _base(source, target, axis_name)
	if deeds != null and source != &"" and target != &"" and _axis_has_delta(axis_name):
		var cfg := _config()
		var scale := _kind_scale(source, target, axis_name)
		var rows := deeds.actor_indexes(target)
		var witnessed := deeds.witness_indexes(source)
		# Membership only. The add order stays the actor index so the rounded sum matches.
		var use_index := _cache_on and witnessed.size() < rows.size()
		var known := {}
		if use_index:
			for index in witnessed:
				known[int(index)] = true
		for index in rows:
			var row := int(index)
			var saw := known.has(row) if use_index else deeds.witnessed(row, source)
			if deeds.target_at(row) != source and not saw:
				continue
			var delta := 0.0
			if cfg != null:
				delta = cfg.axis_delta(deeds.verb_at(row), axis_name)
			total += delta * deeds.weight_at(row) * scale
	return WyrdDeedLog.round_sum(total)


## Mean disposition of [param group]'s members toward [param subject].
## The subject is skipped. Duplicate members count once. No members returns 0.
## The mean shares the social cache. The stamp is checked once per call, then
## each member's axis and disposition entries are filled with the same keys a
## direct read would store. Membership inside a host is read again only after
## [method invalidate_members]. [member WyrdRuntime.invalidate_groups] is the
## host signal.
func reputation(subject: StringName, group: StringName) -> float:
	if subject == &"" or group == &"":
		return 0.0
	if not _cache_on:
		var fresh := _reputation_raw(subject, group)
		_emit_reputation(subject, group, float(fresh["v"]), int(fresh["n"]))
		return float(fresh["v"])
	_ensure()
	var key := "rep\t%s\t%s" % [String(subject), String(group)]
	if _rep_cache.has(key):
		var hit: Dictionary = _rep_cache[key]
		_emit_cache("hit", "reputation", String(group), String(subject), "", 0)
		_emit_reputation(subject, group, float(hit["v"]), int(hit["n"]))
		return float(hit["v"])
	var computed := _reputation_sum(subject, group, true)
	_rep_cache[key] = computed
	_emit_cache("miss", "reputation", String(group), String(subject), "", 0)
	_emit_reputation(subject, group, float(computed["v"]), int(computed["n"]))
	return float(computed["v"])


func _reputation_raw(subject: StringName, group: StringName) -> Dictionary:
	return _reputation_sum(subject, group, false)


## [param warmed] fills axis and disposition entries without another stamp check.
## The keys match a direct [method axis] and [method disposition] for each member.
func _reputation_sum(subject: StringName, group: StringName, warmed: bool) -> Dictionary:
	var listed := PackedStringArray()
	if members_of.is_valid():
		var raw: Variant = members_of.call(group)
		if raw is PackedStringArray:
			listed = raw
		elif raw is Array:
			for item in raw:
				if item != null:
					listed.append(String(item))
	var seen := {}
	var total := 0.0
	var count := 0
	for member in listed:
		var who := StringName(String(member))
		if who == &"" or who == subject or seen.has(who):
			continue
		seen[who] = true
		if warmed:
			total += float(_remember_disposition(who, subject))
		else:
			total += float(disposition(who, subject))
		count += 1
	var value := 0.0 if count == 0 else WyrdDeedLog.round_sum(total / float(count))
	return {"n": count, "v": value}


func _force_invalidate(reason: String) -> void:
	_enqueue_current(reason)
	_remember_seen()
	_cache_ready = true


func _ensure() -> void:
	var bucket := _time_bucket()
	var rev := _rev
	var deed := 0
	if deeds != null:
		deed = deeds.weight_stamp()
	var members := _members_gen
	var config := _config_stamp()
	if not _cache_ready:
		_seen_bucket = bucket
		_seen_rev = rev
		_seen_deed = deed
		_seen_members = members
		_seen_config = config
		_cache_ready = true
		return
	var reason := ""
	if bucket != _seen_bucket:
		reason = "time"
	elif rev != _seen_rev:
		reason = "relation"
	elif deed != _seen_deed:
		reason = "deed"
	elif members != _seen_members:
		reason = "members"
	elif config != _seen_config:
		reason = "config"
	if reason == "":
		return
	_enqueue_current(reason)
	_seen_bucket = bucket
	_seen_rev = rev
	_seen_deed = deed
	_seen_members = members
	_seen_config = config


func _remember_seen() -> void:
	var snap := _snap()
	_seen_bucket = int(snap["bucket"])
	_seen_rev = int(snap["rev"])
	_seen_deed = int(snap["deed"])
	_seen_members = int(snap["members"])
	_seen_config = int(snap["config"])


func _snap() -> Dictionary:
	var deed := 0
	if deeds != null:
		deed = deeds.weight_stamp()
	return {
		"bucket": _time_bucket(),
		"config": _config_stamp(),
		"deed": deed,
		"members": _members_gen,
		"rev": _rev,
	}


func _reason(snap: Dictionary) -> String:
	if int(snap["bucket"]) != _seen_bucket:
		return "time"
	if int(snap["rev"]) != _seen_rev:
		return "relation"
	if int(snap["deed"]) != _seen_deed:
		return "deed"
	if int(snap["members"]) != _seen_members:
		return "members"
	if int(snap["config"]) != _seen_config:
		return "config"
	return ""


func _time_bucket() -> int:
	var now := 0
	if deeds != null and deeds.clock.is_valid():
		now = int(deeds.clock.call())
	var size := 60
	var cfg := _config()
	if cfg != null:
		size = maxi(cfg.hour_bucket_minutes, 0)
	if size <= 0:
		return now
	return int(now / float(size)) * size


func _enqueue_current(reason: String) -> void:
	var keys: Array[String] = []
	_collect_keys(_axis_cache, keys)
	_collect_keys(_disp_cache, keys)
	_collect_keys(_rep_cache, keys)
	_collect_keys(_path_cache, keys)
	var count := keys.size()
	_clear_entries()
	if count == 0:
		return
	_emit_cache("invalidate", reason, reason, "", "", count)


func _collect_keys(table: Dictionary, into: Array[String]) -> void:
	for key in table.keys():
		into.append(String(key))


func _clear_entries() -> void:
	_axis_cache.clear()
	_disp_cache.clear()
	_rep_cache.clear()
	_path_cache.clear()


func _contains(token: String) -> bool:
	var head := token.get_slice("\t", 0)
	match head:
		"axis":
			return _axis_cache.has(token)
		"disp":
			return _disp_cache.has(token)
		"rep":
			return _rep_cache.has(token)
		"path":
			return _path_cache.has(token)
		_:
			return false


func _read_token(token: String) -> void:
	var parts := token.split("\t")
	if parts.is_empty():
		return
	var head := String(parts[0])
	if head == "axis" and parts.size() >= 4:
		axis(StringName(parts[1]), StringName(parts[2]), StringName(parts[3]))
	elif head == "disp" and parts.size() >= 3:
		disposition(StringName(parts[1]), StringName(parts[2]))
	elif head == "rep" and parts.size() >= 3:
		reputation(StringName(parts[1]), StringName(parts[2]))
	elif head == "path" and parts.size() >= 5:
		var kinds := PackedStringArray()
		if String(parts[3]) != "":
			for kind in String(parts[3]).split(","):
				kinds.append(kind)
		path_exists(StringName(parts[1]), StringName(parts[2]), kinds, int(parts[4]))


func _neighbors(source: StringName, allow: Dictionary) -> PackedStringArray:
	var rows := PackedStringArray()
	if not _kinds.has(source):
		return rows
	var outgoing: Dictionary = _kinds[source]
	for target in outgoing.keys():
		var bag: Dictionary = outgoing[target]
		for kind in allow.keys():
			if bag.has(kind):
				rows.append(String(target))
				break
	rows.sort()
	return rows


func _kind_key(kinds: PackedStringArray) -> String:
	var names: Array[String] = []
	for kind in kinds:
		var text := String(kind)
		if text != "" and not names.has(text):
			names.append(text)
	names.sort()
	return ",".join(names)


func _key_bytes(table: Dictionary, value_bytes: int) -> int:
	var total := 0
	for key in table.keys():
		total += String(key).length() + value_bytes
	return total


func _emit_cache(event: String, kind: String, key: String, who: String, path: String, entries: int) -> void:
	if not on_cache.is_valid():
		return
	if tracing_of.is_valid() and not bool(tracing_of.call()):
		return
	on_cache.call({
		"bucket": _time_bucket(),
		"cache": kind,
		"entries": entries,
		"event": event,
		"key": key,
		"path": path,
		"who": who,
	})


func _axis_has_delta(axis_name: StringName) -> bool:
	var cfg := _config()
	if cfg == null or axis_name == &"":
		return false
	var count := mini(cfg.axis_names.size(), cfg.axis_deltas.size())
	for index in count:
		if StringName(cfg.axis_names[index]) != axis_name:
			continue
		if cfg.axis_deltas[index] != 0.0:
			return true
	return false


func _config_stamp() -> int:
	var cfg := _config()
	if cfg == null:
		return 0
	if (
		_stamp_ready
		and _stamp_cfg == cfg
		and _stamp_default == cfg.disposition_default
		and _stamp_hour == cfg.hour_bucket_minutes
		and _stamp_half_verbs == cfg.half_life_verbs
		and _stamp_half_minutes == cfg.half_life_minutes
		and _stamp_axis_verbs == cfg.axis_verbs
		and _stamp_axis_names == cfg.axis_names
		and _stamp_axis_deltas == cfg.axis_deltas
		and _stamp_kind_kinds == cfg.kind_scale_kinds
		and _stamp_kind_axes == cfg.kind_scale_axes
		and _stamp_kind_values == cfg.kind_scale_values
	):
		return _stamp_value
	var mixed := WyrdHash.of_int(cfg.disposition_default)
	mixed = WyrdHash.combine(mixed, cfg.hour_bucket_minutes)
	mixed = _mix_strings(mixed, cfg.half_life_verbs)
	mixed = _mix_floats(mixed, cfg.half_life_minutes)
	mixed = _mix_strings(mixed, cfg.axis_verbs)
	mixed = _mix_strings(mixed, cfg.axis_names)
	mixed = _mix_floats(mixed, cfg.axis_deltas)
	mixed = _mix_strings(mixed, cfg.kind_scale_kinds)
	mixed = _mix_strings(mixed, cfg.kind_scale_axes)
	mixed = _mix_floats(mixed, cfg.kind_scale_values)
	_stamp_ready = true
	_stamp_cfg = cfg
	_stamp_default = cfg.disposition_default
	_stamp_hour = cfg.hour_bucket_minutes
	_stamp_half_verbs = cfg.half_life_verbs.duplicate()
	_stamp_half_minutes = cfg.half_life_minutes.duplicate()
	_stamp_axis_verbs = cfg.axis_verbs.duplicate()
	_stamp_axis_names = cfg.axis_names.duplicate()
	_stamp_axis_deltas = cfg.axis_deltas.duplicate()
	_stamp_kind_kinds = cfg.kind_scale_kinds.duplicate()
	_stamp_kind_axes = cfg.kind_scale_axes.duplicate()
	_stamp_kind_values = cfg.kind_scale_values.duplicate()
	_stamp_value = mixed
	return mixed


func _mix_strings(mixed: int, values: PackedStringArray) -> int:
	mixed = WyrdHash.combine(mixed, values.size())
	for value in values:
		mixed = WyrdHash.combine(mixed, WyrdHash.of_string_name(StringName(value)))
	return mixed


func _mix_floats(mixed: int, values: PackedFloat64Array) -> int:
	mixed = WyrdHash.combine(mixed, values.size())
	for value in values:
		mixed = WyrdHash.combine(mixed, WyrdHash.of_string_name(StringName("%.8f" % value)))
	return mixed


func _emit_reputation(subject: StringName, group: StringName, value: float, count: int) -> void:
	if on_reputation.is_valid():
		on_reputation.call(subject, group, value, count)


func affinity(source: StringName, target: StringName) -> float:
	return axis(source, target, &"affinity")


func disposition(source: StringName, target: StringName) -> int:
	if not _cache_on or source == &"" or target == &"":
		return _disposition_raw(source, target)
	_ensure()
	return _remember_disposition(source, target)


func _remember_disposition(source: StringName, target: StringName) -> int:
	var key := "disp\t%s\t%s" % [String(source), String(target)]
	if _disp_cache.has(key):
		_emit_cache("hit", "disposition", String(target), String(source), "", 0)
		return int(_disp_cache[key])
	var value := _disposition_raw(source, target)
	_disp_cache[key] = value
	_emit_cache("miss", "disposition", String(target), String(source), "", 0)
	return value


func _disposition_raw(source: StringName, target: StringName) -> int:
	var base := 50
	var cfg := _config()
	if cfg != null:
		base = cfg.disposition_default
	var axes := _axes(source, target)
	var raw := 0
	if formula.is_valid():
		raw = int(formula.call(source, target, axes))
	else:
		raw = int(round(float(base) + float(axes[&"affinity"]) / 2.0))
	return clampi(raw, 0, 100)


## True when [param target] is reachable from [param source] in at most
## [param max_hops] directed steps. A step may use any kind in [param kinds].
## [param source] equals [param target] when [param max_hops] is at least 0.
func path_exists(source: StringName, target: StringName, kinds: PackedStringArray, max_hops: int) -> bool:
	if not _cache_on or source == &"" or target == &"":
		return _path_raw(source, target, kinds, max_hops)
	_ensure()
	var key := "path\t%s\t%s\t%s\t%d" % [String(source), String(target), _kind_key(kinds), max_hops]
	if _path_cache.has(key):
		_emit_cache("hit", "path", String(target), String(source), _kind_key(kinds), 0)
		return bool(_path_cache[key])
	var value := _path_raw(source, target, kinds, max_hops)
	_path_cache[key] = value
	_emit_cache("miss", "path", String(target), String(source), _kind_key(kinds), 0)
	return value


func _path_raw(source: StringName, target: StringName, kinds: PackedStringArray, max_hops: int) -> bool:
	if source == &"" or target == &"" or max_hops < 0:
		return false
	if source == target:
		return true
	var allow := {}
	for kind in kinds:
		var name := StringName(String(kind))
		if name != &"":
			allow[name] = true
	if allow.is_empty():
		return false
	var queue: Array[StringName] = [source]
	var dist := {source: 0}
	var head := 0
	while head < queue.size():
		var node: StringName = queue[head]
		head += 1
		var steps := int(dist[node])
		if steps >= max_hops:
			continue
		for nxt in _neighbors(node, allow):
			var who := StringName(nxt)
			if dist.has(who):
				continue
			if who == target:
				return true
			dist[who] = steps + 1
			queue.append(who)
	return false


func _axes(source: StringName, target: StringName) -> Dictionary:
	var names := PackedStringArray(["affinity"])
	var cfg := _config()
	if cfg != null:
		for axis_name in cfg.axis_names:
			if not names.has(axis_name):
				names.append(axis_name)
	var axes := {}
	for axis_name in names:
		var axis_id := StringName(axis_name)
		if _cache_on:
			axes[axis_id] = _remember_axis(source, target, axis_id)
		else:
			axes[axis_id] = _axis_raw(source, target, axis_id)
	return axes


func _kind_scale(observer: StringName, subject: StringName, axis_name: StringName) -> float:
	var cfg := _config()
	if cfg == null:
		return 1.0
	var scale := 1.0
	for row in cfg.scales_for(axis_name):
		var spec: Dictionary = row
		if has_kind(observer, subject, spec["kind"]):
			scale *= float(spec["scale"])
	return scale


func _base(source: StringName, target: StringName, axis_name: StringName) -> float:
	var key := _edge(source, target, axis_name)
	if not _baseline.has(key):
		return 0.0
	return float(_baseline[key])


func _edge(source: StringName, target: StringName, axis_name: StringName) -> String:
	return "%s\t%s\t%s" % [String(source), String(target), String(axis_name)]


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null
