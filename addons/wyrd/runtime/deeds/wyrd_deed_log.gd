class_name WyrdDeedLog
extends RefCounted

## Deed log with hour-bucketed decay. [method compact] merges interchangeable rows.
##
## Rows are parallel packed arrays. Indexes are by actor, target, and verb.
## A witness index stores each witness once per deed. That witness is the
## knower of the deed. [code]saw[/code], [code]heard[/code], and
## [code]inferred[/code] share the list. The mode stays on the row.
## A believer index stores each rumor listener who adopted the deed, with the
## minute they adopted it. [method note_believer] keeps the earlier minute.
## Time buckets use [member WyrdConfig.hour_bucket_minutes]. Each row is stored
## once. [method set_lookup] false makes scans walk every row instead.
## The witness index and the time index are not saved. The believer index is
## rebuilt from the optional [code]believers[/code] field on each deed row.
## [code]now[/code] is bucketed with [member WyrdConfig.hour_bucket_minutes].
## Memorable rows keep full magnitude. A half-life of 0 does not decay.
## Sums are rounded to 6 decimal places before they are returned.
## Witnesses [code]auto[/code] ask [method WyrdSpatialAdapter.witnesses_of].
## An explicit list is stored as given, sorted by id.
## Each witness stores a perception mode from [method WyrdSpatialAdapter.perceive]:
## [code]saw[/code], [code]heard[/code], or [code]inferred[/code]. An empty mode
## drops that witness. A rumor adoption is not a witness. It is a believer.

## Fires with the deed row that was just stored.
signal deed_recorded(deed: Dictionary)

## @experimental
var runtime: WyrdRuntime

## Scale used when returned sums are rounded to 6 decimal places.
const ROUND_SCALE: float = 1000000.0

## @experimental
var clock: Callable = Callable()
## @experimental
var config_of: Callable = Callable()
## @experimental
var spatial_of: Callable = Callable()
## Called once per stored witness: [code](agent, mode, verb)[/code]. Not saved.
## @experimental
var on_perceived: Callable = Callable()
## Called after [method compact]: [code]{before, after, merged, dropped}[/code]. Not saved.
## @experimental
var on_compact: Callable = Callable()

var _next: int = 1
var _id: PackedInt32Array = PackedInt32Array()
var _t: PackedInt32Array = PackedInt32Array()
var _verb: PackedStringArray = PackedStringArray()
var _actor: PackedStringArray = PackedStringArray()
var _target: PackedStringArray = PackedStringArray()
var _place: PackedStringArray = PackedStringArray()
var _magnitude: PackedFloat64Array = PackedFloat64Array()
var _visibility: PackedStringArray = PackedStringArray()
var _memorable: PackedByteArray = PackedByteArray()
var _tag_at: PackedInt32Array = PackedInt32Array()
var _tag_n: PackedInt32Array = PackedInt32Array()
var _wit_at: PackedInt32Array = PackedInt32Array()
var _wit_n: PackedInt32Array = PackedInt32Array()
var _tags: PackedStringArray = PackedStringArray()
var _witnesses: PackedStringArray = PackedStringArray()
var _modes: PackedStringArray = PackedStringArray()
var _by_actor: Dictionary = {}
var _by_target: Dictionary = {}
var _by_verb: Dictionary = {}
## Witness name to deed rows. Each witness is a knower of that deed. Not saved.
var _by_witness: Dictionary = {}
## Deed id to row index. Rebuilt with the rows. Not a separate save key.
var _row_of: Dictionary = {}
## Deed id to {who: adoption minute}. Rebuilt from each row's believers field.
var _believers: Dictionary = {}
## Listener to {deed id: adoption minute}. The reverse of [member _believers].
var _by_believer: Dictionary = {}
## Hour bucket to deed rows. Not saved.
var _by_time: Dictionary = {}
## Social pair "source\ttarget" for snapshot. Not saved. Rebuilt with the rows.
var _pairs: Dictionary = {}
var _pairs_dirty := false
var _stamp_gen: int = -1
var _stamp_now: int = -1
var _stamp_width: int = -2
var _stamp_value: int = 0
var _time_width: int = -1
## False selects a full row walk. The indexes stay built.
var _lookup: bool = true
## Bumps when the rows change. Combined with the decay bucket for relationship caches.
var _gen: int = 1


## @experimental
func export_state() -> Dictionary:
	var rows: Array = []
	for i in size():
		rows.append(_export_row(i))
	return {"next": _next, "rows": rows}


## Rows for [param actor], in log order. The array is the live index: do not mutate it.
## @experimental
func actor_indexes(actor: StringName) -> PackedInt32Array:
	return _index_rows(_by_actor, actor)


## Rows whose target is [param agent], in log order. The array is the live index.
## @experimental
func target_indexes(agent: StringName) -> PackedInt32Array:
	return _index_rows(_by_target, agent)


## Rows [param agent] witnessed, in log order. The array is the live index.
## @experimental
func witness_indexes(agent: StringName) -> PackedInt32Array:
	return _index_rows(_by_witness, agent)


## Row index for [param deed_id], or [code]-1[/code] when that id is not stored.
## @experimental
func index_of(deed_id: int) -> int:
	return int(_row_of.get(deed_id, -1))


## Records that [param who] adopted [param deed_id] at [param minute].
## A later note for the same pair keeps the earlier minute. A missing deed id
## is stored until the next rebuild and is not exported.
## @experimental
func note_believer(deed_id: int, who: StringName, minute: int) -> void:
	if deed_id <= 0 or who == &"":
		return
	var at := minute if minute > 0 else 0
	var text := String(who)
	var bag: Dictionary = {}
	if _believers.has(deed_id):
		bag = _believers[deed_id]
	if bag.has(text) and int(bag[text]) <= at:
		return
	bag[text] = at
	_believers[deed_id] = bag
	var owned: Dictionary = {}
	if _by_believer.has(text):
		owned = _by_believer[text]
	owned[deed_id] = at
	_by_believer[text] = owned


## Listener minutes for deeds any key of [param members] believes, copied at this call.
## The copy does not follow later [method note_believer] writes.
## @experimental
func believer_snapshot(members: Dictionary) -> Dictionary:
	var out := {}
	for deed_id in _believers.keys():
		var live: Dictionary = _believers[deed_id]
		var copy := {}
		for who in live.keys():
			var name := String(who)
			if not members.has(name):
				continue
			copy[name] = int(live[who])
		if not copy.is_empty():
			out[int(deed_id)] = copy
	return out


## Live map of listener to adoption minute for [param deed_id]. Do not mutate it.
## @experimental
func believer_minutes(deed_id: int) -> Dictionary:
	if deed_id <= 0 or not _believers.has(deed_id):
		return {}
	return _believers[deed_id]


## Live map of deed id to adoption minute for [param who]. Do not mutate it.
## @experimental
func believer_index(who: StringName) -> Dictionary:
	var text := String(who)
	if who == &"" or not _by_believer.has(text):
		return {}
	return _by_believer[text]


## Deeds [param who] believes through a rumor, sorted by id.
## Each item is [code]{id, t}[/code]. [code]t[/code] is the adoption minute.
## @experimental
func believer_deeds(who: StringName) -> Array:
	var rows: Array = []
	var text := String(who)
	if who == &"" or not _by_believer.has(text):
		return rows
	var owned: Dictionary = _by_believer[text]
	var ids: Array = owned.keys()
	ids.sort()
	for deed_id in ids:
		rows.append({"id": int(deed_id), "t": int(owned[deed_id])})
	return rows


func _index_rows(table: Dictionary, name: StringName) -> PackedInt32Array:
	var text := String(name)
	if not table.has(text):
		return PackedInt32Array()
	return table[text]


## Changes when a row is added, replaced, or dropped, or when decay can move.
## @experimental
func weight_stamp() -> int:
	var now := _now()
	var width := _bucket()
	if _stamp_gen == _gen and _stamp_now == now and _stamp_width == width:
		return _stamp_value
	var bucket := now if width <= 0 else int(now / float(width)) * width
	_stamp_gen = _gen
	_stamp_now = now
	_stamp_width = width
	_stamp_value = WyrdHash.combine(_gen, bucket)
	return _stamp_value


## Bumps when rows are replaced. A publish cursor restarts when this changes.
## @experimental
func generation() -> int:
	return _gen


## @experimental
func import_state(data: Dictionary) -> void:
	clear()
	var width := _bucket()
	for item in data.get("rows", []):
		if item is Dictionary:
			_append_stored(item, width)
	var next := WyrdSave._whole(data.get("next", 1), 1)
	_next = next if next > 0 else 1


## Merges rows that still count the same, and drops weight that has rounded to zero.
## Rows keep their minute, so a [code]within[/code] window does not grow. The newest id in a
## merged group is kept. Believers from a merged group move onto that id, and the
## same listener keeps the earlier minute. A dropped row loses its believers.
## [code]_next[/code] does not go backwards. Perception callbacks do not run.
## @experimental
func compact() -> int:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null and runtime._host_logs():
		runtime._host_mark("deeds.compact", [])
	var before := size()
	var plan := _compact_plan()
	var merged := int(plan["merged"])
	var dropped := int(plan["dropped"])
	if merged > 0 or dropped > 0:
		var next := _next
		var rows: Array = plan["rows"]
		clear()
		_next = next if next > 0 else 1
		var width := _bucket()
		for row in rows:
			_append_stored(row, width)
	var after := size()
	if on_compact.is_valid():
		on_compact.call({"after": after, "before": before, "dropped": dropped, "merged": merged})
	return after


## Defaults match [method _append_stored]: magnitude 1, memorable false, visibility
## public, minute 0, empty place and target, empty tags, and saw for every witness.
## Older saves that still write those fields load unchanged. Schema stays 2.
func _export_row(index: int) -> Dictionary:
	var row := {
		"actor": String(_actor[index]),
		"id": int(_id[index]),
		"verb": String(_verb[index]),
	}
	var magnitude := float(_magnitude[index])
	if magnitude != 1.0:
		row["magnitude"] = magnitude
	if _memorable[index] != 0:
		row["memorable"] = true
	var place := String(_place[index])
	if not place.is_empty():
		row["place"] = place
	var minute := int(_t[index])
	if minute != 0:
		row["t"] = minute
	var tag_n := int(_tag_n[index])
	if tag_n > 0:
		row["tags"] = _string_list(_slice(_tags, int(_tag_at[index]), tag_n))
	var target := String(_target[index])
	if not target.is_empty():
		row["target"] = target
	var wit_n := int(_wit_n[index])
	if wit_n > 0:
		var modes := _slice(_modes, int(_wit_at[index]), wit_n)
		var all_saw := true
		for mode in modes:
			if mode != "saw":
				all_saw = false
				break
		if not all_saw:
			row["perception"] = _string_list(modes)
		row["witnesses"] = _string_list(_slice(_witnesses, int(_wit_at[index]), wit_n))
	var visibility := String(_visibility[index])
	if visibility != "public":
		row["visibility"] = visibility
	var believers := _believer_list(int(_id[index]))
	if not believers.is_empty():
		row["believers"] = believers
	return row


func _append_stored(row: Dictionary, bucket_width: int) -> void:
	var tags := _stored_texts(row.get("tags", []))
	var witnesses := _stored_texts(row.get("witnesses", []))
	var perception := _align_modes(witnesses, _stored_texts(row.get("perception", [])))
	var index := _id.size()
	var id := _stored_whole(row.get("id", 0), 0)
	var minute := _stored_whole(row.get("t", 0), 0)
	var verb := _stored_text(row.get("verb", ""), "")
	var actor := _stored_text(row.get("actor", ""), "")
	var target := _stored_text(row.get("target", ""), "")
	_id.append(id)
	_t.append(minute)
	_verb.append(verb)
	_actor.append(actor)
	_target.append(target)
	_place.append(_stored_text(row.get("place", ""), ""))
	_magnitude.append(_stored_number(row.get("magnitude", 1.0), 1.0))
	_visibility.append(_stored_text(row.get("visibility", "public"), "public"))
	_memorable.append(1 if _stored_flag(row.get("memorable", false), false) else 0)
	_tag_at.append(_tags.size())
	_tag_n.append(tags.size())
	for tag in tags:
		_tags.append(tag)
	var wit_at := _witnesses.size()
	_wit_at.append(wit_at)
	_wit_n.append(witnesses.size())
	for i in witnesses.size():
		_witnesses.append(witnesses[i])
		_modes.append(perception[i])
	_index_text(_by_actor, actor, index)
	_index_text(_by_target, target, index)
	_index_text(_by_verb, verb, index)
	_row_of[id] = index
	for offset in witnesses.size():
		_index_text(_by_witness, witnesses[offset], index)
	_pairs_dirty = true
	if bucket_width != _time_width:
		_time_width = bucket_width
		_by_time.clear()
		for i in size():
			_push_width(i, bucket_width)
	else:
		var bucket := minute if bucket_width <= 0 else int(minute / float(bucket_width)) * bucket_width
		var timed := PackedInt32Array()
		if _by_time.has(bucket):
			timed = _by_time[bucket]
		timed.append(index)
		_by_time[bucket] = timed
	for item in row.get("believers", []):
		if item is Dictionary:
			note_believer(id, StringName(str(item.get("who", ""))), _stored_whole(item.get("t", 0), 0))


func _stored_text(value: Variant, fallback: String) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return WyrdSave.text_of(value, fallback)


func _stored_whole(value: Variant, fallback: int) -> int:
	var kind := typeof(value)
	if kind == TYPE_INT or kind == TYPE_FLOAT:
		return int(value)
	return fallback


func _stored_number(value: Variant, fallback: float) -> float:
	var kind := typeof(value)
	if kind == TYPE_INT or kind == TYPE_FLOAT:
		return float(value)
	return fallback


func _stored_flag(value: Variant, fallback: bool) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return fallback


func _stored_texts(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var rows := PackedStringArray()
	if value is Array:
		var items: Array = value
		rows.resize(items.size())
		for i in items.size():
			rows[i] = _stored_text(items[i], "")
	return rows


func _index_text(table: Dictionary, key: String, row: int) -> void:
	if key.is_empty():
		return
	var rows := PackedInt32Array()
	if table.has(key):
		rows = table[key]
	rows.append(row)
	table[key] = rows


func _push_width(index: int, width: int) -> void:
	var minute := int(_t[index])
	var bucket := minute if width <= 0 else int(minute / float(width)) * width
	var rows := PackedInt32Array()
	if _by_time.has(bucket):
		rows = _by_time[bucket]
	rows.append(index)
	_by_time[bucket] = rows


func _compact_plan() -> Dictionary:
	var count := size()
	var latest := {}
	for i in count:
		var verb := String(_verb[i])
		var at := int(_wit_at[i])
		for offset in int(_wit_n[i]):
			latest["%s\t%s" % [_witnesses[at + offset], verb]] = i
	var drop := {}
	var tiny := 0.0
	var tiny_rows: Array = []
	for i in count:
		if round_sum(weight_at(i)) != 0.0:
			continue
		if _protects_mode(i, latest):
			continue
		tiny += weight_at(i)
		tiny_rows.append(i)
	if round_sum(tiny) == 0.0:
		for i in tiny_rows:
			drop[int(i)] = true
	var groups := {}
	for i in count:
		if drop.has(i):
			continue
		var key := _compact_key(i)
		var bucket: Array = groups.get(key, [])
		bucket.append(i)
		groups[key] = bucket
	var rows: Array = []
	var merged := 0
	for i in count:
		if drop.has(i):
			continue
		var bucket: Array = groups[_compact_key(i)]
		var last := int(bucket[bucket.size() - 1])
		if last != i:
			continue
		if bucket.size() == 1:
			rows.append(_attach_believers(row_at(i), [int(_id[i])]))
			continue
		var combined := row_at(i)
		var magnitude := 0.0
		var kept_id := 0
		var ids: Array = []
		for member in bucket:
			var index := int(member)
			magnitude += float(_magnitude[index])
			kept_id = maxi(kept_id, int(_id[index]))
			ids.append(int(_id[index]))
		combined["magnitude"] = round_sum(magnitude)
		combined["id"] = kept_id
		rows.append(_attach_believers(combined, ids))
		merged += bucket.size() - 1
	return {"dropped": drop.size(), "merged": merged, "rows": rows}


func _protects_mode(index: int, latest: Dictionary) -> bool:
	var verb := String(_verb[index])
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		var key := "%s\t%s" % [_witnesses[at + offset], verb]
		if int(latest.get(key, -1)) == index:
			return true
	return false


func _compact_key(index: int) -> String:
	var tags := _slice(_tags, int(_tag_at[index]), int(_tag_n[index]))
	var wit := ""
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		if offset > 0:
			wit += ","
		wit += "%s=%s" % [_witnesses[at + offset], _modes[at + offset]]
	return "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s" % [
		_verb[index],
		_actor[index],
		_target[index],
		_place[index],
		_visibility[index],
		int(_memorable[index]),
		int(_t[index]),
		",".join(tags),
		wit,
	]


func _believer_list(deed_id: int) -> Array:
	var listed: Array = []
	if not _believers.has(deed_id):
		return listed
	var bag: Dictionary = _believers[deed_id]
	var names: Array = bag.keys()
	names.sort()
	for who in names:
		listed.append({"t": int(bag[who]), "who": String(who)})
	return listed


## Copies believers from [param deed_ids] onto [param row]. The same listener
## keeps the earlier minute. An empty list adds no field.
func _attach_believers(row: Dictionary, deed_ids: Array) -> Dictionary:
	var bag := {}
	for deed_id in deed_ids:
		if not _believers.has(int(deed_id)):
			continue
		var part: Dictionary = _believers[int(deed_id)]
		for who in part.keys():
			var minute := int(part[who])
			if not bag.has(who) or minute < int(bag[who]):
				bag[who] = minute
	if bag.is_empty():
		return row
	var names: Array = bag.keys()
	names.sort()
	var listed: Array = []
	for who in names:
		listed.append({"t": int(bag[who]), "who": String(who)})
	row["believers"] = listed
	return row


func _string_list(value: Variant) -> Array:
	var rows: Array = []
	if value is PackedStringArray:
		for item in value:
			rows.append(String(item))
	elif value is Array:
		for item in value:
			rows.append(String(item))
	return rows


func _packed(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var rows := PackedStringArray()
	if value is Array:
		for item in value:
			rows.append(WyrdSave.text_of(item, ""))
	return rows


## @experimental
func clear() -> void:
	_next = 1
	_id = PackedInt32Array()
	_t = PackedInt32Array()
	_verb = PackedStringArray()
	_actor = PackedStringArray()
	_target = PackedStringArray()
	_place = PackedStringArray()
	_magnitude = PackedFloat64Array()
	_visibility = PackedStringArray()
	_memorable = PackedByteArray()
	_tag_at = PackedInt32Array()
	_tag_n = PackedInt32Array()
	_wit_at = PackedInt32Array()
	_wit_n = PackedInt32Array()
	_tags = PackedStringArray()
	_witnesses = PackedStringArray()
	_modes = PackedStringArray()
	_by_actor.clear()
	_by_target.clear()
	_by_verb.clear()
	_by_witness.clear()
	_row_of.clear()
	_believers.clear()
	_by_believer.clear()
	_by_time.clear()
	_pairs.clear()
	_pairs_dirty = false
	_time_width = -1
	_stamp_gen = -1
	_gen += 1


## @experimental
func size() -> int:
	return _id.size()


## @experimental
func index_size(which: StringName, key: StringName) -> int:
	var table := _index_table(which)
	if table.is_empty() or not table.has(String(key)):
		return 0
	return (table[String(key)] as PackedInt32Array).size()


## Stores one deed and returns its id. An empty verb or actor returns -1.
func record(
	verb: StringName,
	actor: StringName,
	target: StringName = &"",
	place: StringName = &"",
	tags: PackedStringArray = PackedStringArray(),
	magnitude: float = 1.0,
	witnesses: Variant = null,
	visibility: StringName = &"public",
	memorable: bool = false
) -> int:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if verb == &"" or actor == &"":
		push_error("WyrdDeedLog.record: verb and actor are required")
		return -1
	if runtime != null and runtime._host_logs():
		runtime._host_mark("deeds.record", [verb, actor, target, place, tags, magnitude, witnesses, visibility, memorable])
	var row := _id.size()
	var stamp := _now()
	var shown := visibility if visibility != &"" else &"public"
	var tag_rows := _sorted(tags)
	var perceived := _perceived(actor, target, place, witnesses)
	var wit_rows: PackedStringArray = perceived["witnesses"]
	var mode_rows: PackedStringArray = perceived["modes"]
	_id.append(_next)
	_next += 1
	_t.append(stamp)
	_verb.append(String(verb))
	_actor.append(String(actor))
	_target.append(String(target))
	_place.append(String(place))
	_magnitude.append(magnitude)
	_visibility.append(String(shown))
	_memorable.append(1 if memorable else 0)
	_tag_at.append(_tags.size())
	_tag_n.append(tag_rows.size())
	for tag in tag_rows:
		_tags.append(tag)
	_wit_at.append(_witnesses.size())
	_wit_n.append(wit_rows.size())
	for i in wit_rows.size():
		_witnesses.append(wit_rows[i])
		_modes.append(mode_rows[i])
		if on_perceived.is_valid():
			on_perceived.call(StringName(wit_rows[i]), StringName(mode_rows[i]), verb)
	_index(_by_actor, actor, row)
	_index(_by_target, target, row)
	_index(_by_verb, verb, row)
	_row_of[int(_id[row])] = row
	_index_witnesses(row)
	if not _pairs_dirty:
		_index_pairs(row)
	_note_time(row)
	_gen += 1
	var deed := row_at(row)
	deed_recorded.emit(deed)
	return int(deed["id"])


## @experimental
func count_matching(
	actor: StringName,
	verb: Variant = null,
	target: Variant = null,
	place: Variant = null,
	within: Variant = null,
	tags: PackedStringArray = PackedStringArray()
) -> int:
	return _scan(actor, verb, target, place, within, tags, false)


## @experimental
func score_matching(
	actor: StringName,
	verb: Variant = null,
	target: Variant = null,
	place: Variant = null,
	within: Variant = null,
	tags: PackedStringArray = PackedStringArray()
) -> float:
	return float(_scan(actor, verb, target, place, within, tags, true))


## @experimental
func verb_at(index: int) -> StringName:
	return StringName(_verb[index])


## @experimental
func actor_at(index: int) -> StringName:
	return StringName(_actor[index])


## @experimental
func target_at(index: int) -> StringName:
	return StringName(_target[index])


## @experimental
func id_at(index: int) -> int:
	return int(_id[index])


## @experimental
func minute_at(index: int) -> int:
	return int(_t[index])


## @experimental
func place_at(index: int) -> StringName:
	return StringName(_place[index])


## @experimental
func magnitude_at(index: int) -> float:
	return _magnitude[index]


## @experimental
func memorable_at(index: int) -> bool:
	return _memorable[index] != 0


## Rows whose verb is [param verb], in log order. The array is the live index.
## @experimental
func verb_indexes(verb: StringName) -> PackedInt32Array:
	return _index_rows(_by_verb, verb)


## Rows in hour buckets at or after [param minute]. The caller still checks the minute.
## @experimental
func rows_since(minute: int) -> PackedInt32Array:
	_ensure_time()
	var start := _bucketed(minute if minute > 0 else 0)
	var merged := PackedInt32Array()
	for key in _by_time.keys():
		if int(key) < start:
			continue
		var bucket_rows: PackedInt32Array = _by_time[key]
		for row in bucket_rows:
			merged.append(int(row))
	return merged


## @experimental
func witness_count_at(index: int) -> int:
	return int(_wit_n[index])


## @experimental
func witness_name_at(index: int, offset: int) -> String:
	return _witnesses[int(_wit_at[index]) + offset]


## @experimental
func witness_mode_name_at(index: int, offset: int) -> String:
	return _modes[int(_wit_at[index]) + offset]


## Pair keys [code]source\ttarget[/code] from deed targets and witnesses. Not saved.
## @experimental
func pair_keys() -> PackedStringArray:
	_ensure_pairs()
	var keys := PackedStringArray()
	keys.resize(_pairs.size())
	var at := 0
	for key in _pairs.keys():
		keys[at] = String(key)
		at += 1
	return keys


## @experimental
func witnesses_at(index: int) -> PackedStringArray:
	return _slice(_witnesses, int(_wit_at[index]), int(_wit_n[index]))


## @experimental
func witnessed(index: int, agent: StringName) -> bool:
	return _has_in(_witnesses, _wit_at[index], _wit_n[index], String(agent))


## False makes snapshot and [code]within[/code] scans walk rows instead of the indexes.
## @experimental
func set_lookup(enabled: bool) -> void:
	_lookup = enabled


## @experimental
func lookup_enabled() -> bool:
	return _lookup


## UTF-8 size of witness names and time-bucket labels, plus 4 bytes per stored row ref.
## Actor, target, and verb indexes are not included. Each deed row is stored once
## per witness and once in its time bucket.
## @experimental
func index_text_bytes() -> int:
	_ensure_time()
	return _table_text(_by_witness, false) + _table_text(_by_time, true)


## @experimental
func witness_buckets() -> int:
	return _by_witness.size()


## @experimental
func witness_refs() -> int:
	return _ref_count(_by_witness)


## @experimental
func time_buckets() -> int:
	_ensure_time()
	return _by_time.size()


## @experimental
func time_refs() -> int:
	_ensure_time()
	return _ref_count(_by_time)


## Deed rows whose actor can start [code]actor/verb/target[/code] for [param prefix].
## An empty prefix is every row, grouped by time bucket.
## @experimental
func rows_for_deed_prefix(prefix: String) -> PackedInt32Array:
	_ensure_time()
	if prefix.is_empty():
		return _all_time_rows()
	var merged := _rows_for_names(_by_actor, prefix)
	if prefix.begins_with("/"):
		_append_empty_actors(merged)
	return merged


## Deed rows whose target or witness can start [code]source/actor[/code] for [param prefix].
## An empty prefix is every row.
## @experimental
func rows_for_pair_prefix(prefix: String) -> PackedInt32Array:
	_ensure_time()
	if prefix.is_empty():
		return _all_time_rows()
	var seen := {}
	var merged := PackedInt32Array()
	_collect_named(_by_target, prefix, seen, merged)
	_collect_named(_by_witness, prefix, seen, merged)
	return merged


## Actor, target, and witness names that begin with [param prefix].
## @experimental
func agent_names(prefix: String) -> PackedStringArray:
	var seen := {}
	var names := PackedStringArray()
	for table in [_by_actor, _by_target, _by_witness]:
		for key in (table as Dictionary).keys():
			var name := String(key)
			if name.is_empty() or seen.has(name):
				continue
			if not prefix.is_empty() and not name.begins_with(prefix):
				continue
			seen[name] = true
			names.append(name)
	return names


## @experimental
func weight_at(index: int) -> float:
	if _memorable[index] != 0:
		return _magnitude[index]
	var life := _half_life(StringName(_verb[index]))
	if life <= 0.0:
		return _magnitude[index]
	var age := float(_bucketed(_now()) - int(_t[index]))
	if age <= 0.0:
		return _magnitude[index]
	return _magnitude[index] * pow(0.5, age / life)


## @experimental
func row_at(index: int) -> Dictionary:
	return {
		"actor": StringName(_actor[index]),
		"id": int(_id[index]),
		"magnitude": _magnitude[index],
		"memorable": _memorable[index] != 0,
		"place": StringName(_place[index]),
		"t": int(_t[index]),
		"tags": _slice(_tags, _tag_at[index], _tag_n[index]),
		"target": StringName(_target[index]),
		"verb": StringName(_verb[index]),
		"perception": _slice(_modes, _wit_at[index], _wit_n[index]),
		"visibility": StringName(_visibility[index]),
		"witnesses": _slice(_witnesses, _wit_at[index], _wit_n[index]),
	}


## Latest mode for [param agent] on [param verb], or empty when they never perceived it.
## @experimental
func mode_of(agent: StringName, verb: StringName) -> StringName:
	if agent == &"" or verb == &"":
		return &""
	var who := String(agent)
	if not _lookup:
		return _mode_of_scan(who, verb)
	var rows := PackedInt32Array()
	if _by_witness.has(who):
		rows = _by_witness[who]
	for step in range(rows.size() - 1, -1, -1):
		var index := int(rows[step])
		if StringName(_verb[index]) != verb:
			continue
		var at := int(_wit_at[index])
		for offset in int(_wit_n[index]):
			if _witnesses[at + offset] == who:
				return StringName(_modes[at + offset])
	return &""


func _mode_of_scan(who: String, verb: StringName) -> StringName:
	for index in range(size() - 1, -1, -1):
		if StringName(_verb[index]) != verb:
			continue
		var at := int(_wit_at[index])
		for offset in int(_wit_n[index]):
			if _witnesses[at + offset] == who:
				return StringName(_modes[at + offset])
	return &""


## @experimental
static func round_sum(value: float) -> float:
	return round(value * ROUND_SCALE) / ROUND_SCALE


func _scan(
	actor: StringName,
	verb: Variant,
	target: Variant,
	place: Variant,
	within: Variant,
	tags: PackedStringArray,
	as_score: bool
) -> Variant:
	var verb_name := _opt_name(verb)
	var target_name := _opt_name(target)
	var place_name := _opt_name(place)
	var now := _now()
	var rows := _candidates(actor, verb_name, target_name, within, now)
	var count := 0
	var total := 0.0
	for index in rows:
		if not _hit(int(index), actor, verb_name, target_name, place_name, within, tags, now):
			continue
		count += 1
		if as_score:
			total += weight_at(int(index))
	if as_score:
		return round_sum(total)
	return count


func _hit(
	index: int,
	actor: StringName,
	verb: StringName,
	target: StringName,
	place: StringName,
	within: Variant,
	tags: PackedStringArray,
	now: int
) -> bool:
	if actor != &"" and _actor[index] != String(actor):
		return false
	if verb != &"" and _verb[index] != String(verb):
		return false
	if target != &"" and _target[index] != String(target):
		return false
	if place != &"" and _place[index] != String(place):
		return false
	if within != null and now - int(_t[index]) > int(within):
		return false
	for tag in tags:
		if not _has_in(_tags, _tag_at[index], _tag_n[index], tag):
			return false
	return true


func _candidates(actor: StringName, verb: StringName, target: StringName, within: Variant, now: int) -> PackedInt32Array:
	var best := PackedInt32Array()
	var chosen := false
	if actor != &"":
		best = _copy_index(_by_actor, actor)
		chosen = true
	if verb != &"":
		var rows := _copy_index(_by_verb, verb)
		if not chosen or rows.size() < best.size():
			best = rows
			chosen = true
	if target != &"":
		var rows := _copy_index(_by_target, target)
		if not chosen or rows.size() < best.size():
			best = rows
			chosen = true
	if not chosen:
		if _lookup and within != null:
			return _rows_in_window(now, int(within))
		best.resize(_id.size())
		for i in _id.size():
			best[i] = i
		return best
	if _lookup and within != null:
		return _intersect(best, _rows_in_window(now, int(within)))
	return best


func _perceived(actor: StringName, target: StringName, place: StringName, witnesses: Variant) -> Dictionary:
	var ids := _witness_list(actor, target, place, witnesses)
	var kept := PackedStringArray()
	var modes := PackedStringArray()
	var spatial := _spatial()
	for id in ids:
		var mode := &"saw"
		if spatial != null:
			mode = _perception_mode(spatial.perceive(StringName(id), actor, target, place))
		if mode == &"":
			continue
		kept.append(String(id))
		modes.append(String(mode))
	return {"modes": modes, "witnesses": kept}


func _perception_mode(raw: StringName) -> StringName:
	var text := String(raw)
	if text == "saw" or text == "heard" or text == "inferred":
		return StringName(text)
	if text.is_empty():
		return &""
	push_error("WyrdDeedLog.record: perception \"%s\" is not saw, heard, or inferred" % text)
	return &"saw"


func _align_modes(witnesses: PackedStringArray, perception: PackedStringArray) -> PackedStringArray:
	var modes := perception.duplicate()
	while modes.size() < witnesses.size():
		modes.append("saw")
	if modes.size() > witnesses.size():
		modes.resize(witnesses.size())
	return modes


func _witness_list(actor: StringName, target: StringName, place: StringName, witnesses: Variant) -> PackedStringArray:
	if witnesses == null:
		return PackedStringArray()
	if witnesses is StringName or witnesses is String:
		if String(witnesses) != "auto":
			push_error("WyrdDeedLog.record: witnesses must be auto or a list")
			return PackedStringArray()
		var spatial := _spatial()
		if spatial == null:
			return PackedStringArray()
		return _sorted(spatial.witnesses_of(actor, target, place))
	if witnesses is PackedStringArray:
		return _sorted(witnesses)
	if witnesses is Array:
		var rows := PackedStringArray()
		for item in witnesses:
			if item != null:
				rows.append(String(item))
		return _sorted(rows)
	push_error("WyrdDeedLog.record: witnesses must be auto or a list")
	return PackedStringArray()


func _sorted(values: PackedStringArray) -> PackedStringArray:
	var copy := values.duplicate()
	copy.sort()
	return copy


func _index_witnesses(index: int) -> void:
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		_index(_by_witness, StringName(_witnesses[at + offset]), index)


func _ensure_pairs() -> void:
	if not _pairs_dirty:
		return
	_pairs.clear()
	for index in size():
		_index_pairs(index)
	_pairs_dirty = false


func _index_pairs(index: int) -> void:
	var actor := String(_actor[index])
	if actor.is_empty():
		return
	var target := String(_target[index])
	if not target.is_empty():
		_pairs["%s\t%s" % [target, actor]] = true
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		var source := _witnesses[at + offset]
		if source.is_empty():
			continue
		_pairs["%s\t%s" % [source, actor]] = true


func _note_time(index: int) -> void:
	var width := _bucket()
	if width != _time_width:
		_ensure_time()
		return
	_push_time(index)


func _ensure_time() -> void:
	var width := _bucket()
	if width == _time_width:
		return
	_time_width = width
	_by_time.clear()
	for i in size():
		_push_time(i)


func _push_time(index: int) -> void:
	var bucket := _bucketed(int(_t[index]))
	var rows := PackedInt32Array()
	if _by_time.has(bucket):
		rows = _by_time[bucket]
	rows.append(index)
	_by_time[bucket] = rows


func _all_time_rows() -> PackedInt32Array:
	var merged := PackedInt32Array()
	merged.resize(size())
	var at := 0
	var buckets: Array = _by_time.keys()
	buckets.sort()
	for bucket in buckets:
		var rows: PackedInt32Array = _by_time[bucket]
		for row in rows:
			merged[at] = int(row)
			at += 1
	if at != merged.size():
		merged.resize(at)
	return merged


func _rows_in_window(now: int, within: int) -> PackedInt32Array:
	_ensure_time()
	var start := _bucketed(now - within)
	var merged := PackedInt32Array()
	for key in _by_time.keys():
		if int(key) < start:
			continue
		var rows: PackedInt32Array = _by_time[key]
		for row in rows:
			merged.append(int(row))
	return merged


func _intersect(left: PackedInt32Array, right: PackedInt32Array) -> PackedInt32Array:
	var gate := {}
	var small := left
	var large := right
	if right.size() < left.size():
		small = right
		large = left
	for row in small:
		gate[int(row)] = true
	var merged := PackedInt32Array()
	for row in large:
		var index := int(row)
		if gate.has(index):
			merged.append(index)
	return merged


func _rows_for_names(table: Dictionary, prefix: String) -> PackedInt32Array:
	var seen := {}
	var merged := PackedInt32Array()
	_collect_named(table, prefix, seen, merged)
	return merged


func _collect_named(table: Dictionary, prefix: String, seen: Dictionary, merged: PackedInt32Array) -> void:
	for key in table.keys():
		var name := String(key)
		if not _name_can_start(name, prefix):
			continue
		var rows: PackedInt32Array = table[key]
		for row in rows:
			var index := int(row)
			if seen.has(index):
				continue
			seen[index] = true
			merged.append(index)


func _append_empty_actors(merged: PackedInt32Array) -> void:
	var seen := {}
	for row in merged:
		seen[int(row)] = true
	for index in size():
		if not String(_actor[index]).is_empty() or seen.has(index):
			continue
		merged.append(index)


func _name_can_start(name: String, prefix: String) -> bool:
	if prefix.is_empty() or name.begins_with(prefix):
		return true
	if not prefix.begins_with(name):
		return false
	return prefix.length() == name.length() or prefix.substr(name.length(), 1) == "/"


func _table_text(table: Dictionary, numeric_key: bool) -> int:
	var total := 0
	for key in table.keys():
		var label := str(int(key)) if numeric_key else String(key)
		total += label.to_utf8_buffer().size()
		total += (table[key] as PackedInt32Array).size() * 4
	return total


func _ref_count(table: Dictionary) -> int:
	var total := 0
	for key in table.keys():
		total += (table[key] as PackedInt32Array).size()
	return total


func _index(table: Dictionary, key: StringName, row: int) -> void:
	if key == &"":
		return
	var text := String(key)
	var rows := PackedInt32Array()
	if table.has(text):
		rows = table[text]
	rows.append(row)
	table[text] = rows


func _copy_index(table: Dictionary, key: StringName) -> PackedInt32Array:
	var text := String(key)
	if not table.has(text):
		return PackedInt32Array()
	return (table[text] as PackedInt32Array).duplicate()


func _index_table(which: StringName) -> Dictionary:
	match String(which):
		"actor":
			return _by_actor
		"target":
			return _by_target
		"verb":
			return _by_verb
		"witness":
			return _by_witness
		_:
			return {}


func _slice(pool: PackedStringArray, at: int, count: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for i in count:
		rows.append(pool[at + i])
	return rows


func _has_in(pool: PackedStringArray, at: int, count: int, needle: String) -> bool:
	for i in count:
		if pool[at + i] == needle:
			return true
	return false


func _opt_name(value: Variant) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _bucketed(now: int) -> int:
	var size := _bucket()
	if size <= 0:
		return now
	return int(now / float(size)) * size


func _bucket() -> int:
	var cfg := _config()
	if cfg == null:
		return 60
	return maxi(cfg.hour_bucket_minutes, 0)


func _half_life(verb: StringName) -> float:
	var cfg := _config()
	if cfg == null:
		return 0.0
	return cfg.half_life_for(verb)


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null


func _spatial() -> WyrdSpatialAdapter:
	if not spatial_of.is_valid():
		return null
	var found: Variant = spatial_of.call()
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null
