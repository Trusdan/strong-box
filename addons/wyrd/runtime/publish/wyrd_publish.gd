class_name WyrdPublish
extends RefCounted

## Periodic issues for compiled documents.
##
## @experimental
## [method enqueue_due] pushes one [code]publish[/code] token per missed issue,
## oldest first, up to [member WyrdConfig.publish_catchup_max]. One token is one
## frozen issue, built a slice at a time. Each publish unit reads at most
## [member WyrdConfig.publish_slice_rows] candidate rows, then the same token
## stays at the front of the queue. The claim and the candidate rows are frozen
## on the first slice, so the finished line matches a one-shot build from that
## moment. Issues past the cap are numbered and written as [code]skip[/code]
## lines in the document fact, so they are not published later. The in-memory
## counter, the covered minute, and the queued dues are saved in
## [code]flight.publish[/code]. A half-built issue also stores [code]cursor[/code],
## the optional [code]beliefs[/code] snapshot from the first slice, and the
## optional [code]claim[/code] frozen with it. Load continues that issue from
## the snapshot. A save that has [code]cursor[/code] and no [code]beliefs[/code]
## starts the issue over and can log [code]phase=restart[/code]. The gathered
## rows are dropped. Issue tokens ride with the scheduler. Schema stays 3.
## [method deeds_known_to] reads the verb index, the witness index, the hour
## buckets, and the believer field. Lookup off walks every row instead.
## A [code]saw[/code] witness counts as [code]known[/code]. [code]heard[/code],
## [code]inferred[/code], and a rumor believer count as [code]believed[/code].

var facts: WyrdFactStore
var deeds: WyrdDeedLog
var config_of: Callable = Callable()
var now_of: Callable = Callable()
var members_of: Callable = Callable()
var content_of: Callable = Callable()
var eval_of: Callable = Callable()
var trace_of: Callable = Callable()
var cursor_trace_of: Callable = Callable()
var enqueue_of: Callable = Callable()

var _covered: Dictionary = {}
var _memory_n: Dictionary = {}
var _queued: Dictionary = {}
var _build_token := ""
var _build_at := 0
var _build_rows := PackedInt32Array()
var _build_seen: Dictionary = {}
var _build_members := PackedStringArray()
var _build_set: Dictionary = {}
var _build_since := 0
var _build_verb := ""
var _build_due := 0
var _build_number := 0
var _build_doc := ""
var _build_claim: Dictionary = {}
var _build_gen := 0
var _build_limit := 0
var _build_beliefs: Dictionary = {}
var _restart := ""
var _resume := false
var _saved_beliefs: Dictionary = {}
var _saved_claim: Dictionary = {}
var _saved_claim_ok := false


func clear() -> void:
	_covered.clear()
	_memory_n.clear()
	_queued.clear()
	_clear_build()
	_restart = ""
	_resume = false
	_saved_beliefs = {}
	_saved_claim = {}
	_saved_claim_ok = false


## Counters, covered minutes, and dues already queued. Empty when nothing is in flight.
func export_state() -> Dictionary:
	var out := {}
	var counters := _export_ints(_memory_n)
	if not counters.is_empty():
		out["counters"] = counters
	var covered := _export_ints(_covered)
	if not covered.is_empty():
		out["covered"] = covered
	var queued: Array = []
	for key in _queued.keys():
		queued.append(String(key))
	queued.sort()
	if not queued.is_empty():
		out["queued"] = queued
	if not _build_token.is_empty():
		out["cursor"] = _build_token
		out["beliefs"] = _export_beliefs(_build_beliefs)
		out["claim"] = {
			"source": str(_build_claim.get("source", "none")),
			"value": str(_build_claim.get("value", "")),
		}
	elif not _restart.is_empty():
		out["cursor"] = _restart
		if _resume:
			out["beliefs"] = _export_beliefs(_saved_beliefs)
			if _saved_claim_ok:
				out["claim"] = _saved_claim
	return out


## Replaces counters, covered minutes, and the queued-due set.
## Issue tokens stay on the scheduler. A saved [code]cursor[/code] with
## [code]beliefs[/code] resumes that issue. Without [code]beliefs[/code] the
## next slice starts over. The gathered rows are not restored.
func import_state(data: Dictionary) -> void:
	clear()
	_import_ints(_memory_n, data.get("counters", {}))
	_import_ints(_covered, data.get("covered", {}))
	var queued: Variant = data.get("queued", [])
	if queued is Array:
		for item in queued:
			var key := WyrdSave.text_of(item, "")
			if not key.is_empty():
				_queued[key] = true
	_restart = String(data.get("cursor", ""))
	_resume = data.has("beliefs")
	if _resume:
		_saved_beliefs = _import_beliefs(data.get("beliefs", []))
		_saved_claim_ok = data.has("claim")
		if _saved_claim_ok and data["claim"] is Dictionary:
			var claim: Dictionary = data["claim"]
			_saved_claim = {
				"source": str(claim.get("source", "none")),
				"value": str(claim.get("value", "")),
			}
		else:
			_saved_claim_ok = false
			_saved_claim = {}


func _export_beliefs(beliefs: Dictionary) -> Array:
	var rows: Array = []
	var ids: Array = beliefs.keys()
	ids.sort()
	for deed_id in ids:
		var bag: Dictionary = beliefs[deed_id]
		var names: Array = bag.keys()
		names.sort()
		for who in names:
			rows.append({
				"deed": int(deed_id),
				"t": int(bag[who]),
				"who": String(who),
			})
	return rows


func _import_beliefs(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Array):
		return out
	for item in raw:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var deed_id := WyrdSave._whole(row.get("deed", 0), 0)
		var who := str(row.get("who", ""))
		if deed_id <= 0 or who.is_empty():
			continue
		var bag: Dictionary = out[deed_id] if out.has(deed_id) else {}
		bag[who] = WyrdSave._whole(row.get("t", 0), 0)
		out[deed_id] = bag
	return out


func _export_ints(bag: Dictionary) -> Dictionary:
	var out := {}
	var ids: Array = bag.keys()
	ids.sort()
	for id in ids:
		out[String(id)] = int(bag[id])
	return out


func _import_ints(into: Dictionary, raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	for id in (raw as Dictionary).keys():
		into[String(id)] = WyrdSave._whole((raw as Dictionary)[id], 0)


## Deed rows any current member witnessed, or believes through a rumor, at or
## after [param since]. A witness uses the deed minute. A believer uses the
## adoption minute. [param filter] empty keeps every verb. Otherwise it is the
## verb. Rows are unique by deed id and sorted by that id. [code]t[/code] is
## the earliest qualifying minute. [code]mode[/code] is [code]known[/code] when
## any included member saw the deed, and [code]believed[/code] otherwise.
## [code]knowers[/code] lists those members once.
func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array:
	var rows: Array = []
	if deeds == null or group == &"":
		return rows
	var start := since if since > 0 else 0
	var verb := String(filter)
	var members := _members(String(group))
	var seen := {}
	var gate := _member_set(members)
	for index in _candidate_rows(members, start, verb):
		_fill_known(seen, int(index), gate, start, verb)
	return _sorted_known(seen)


## Queues due issues that are not already frozen, skipped, or already queued.
## A visit takes at most the catch-up cap, oldest first. The rest are numbered
## and stored as skip lines in the document fact. The cap is per document.
func enqueue_due() -> void:
	var content := _content()
	if content == null or not enqueue_of.is_valid():
		return
	var now := _now()
	var cap := _cap()
	var ids: Array = content.documents.keys()
	ids.sort()
	for id in ids:
		_enqueue_doc(content.documents[id] as WyrdDocumentDef, now, cap)


## Reads one slice of the frozen issue named by an [code]issue[/code] token.
## Returns false when the token should stay queued. Other tokens are ignored
## and return true. The copy is written on the slice that finishes the cursor.
func issue(token: String) -> bool:
	if not token.begins_with("issue\t"):
		return true
	var parts := token.split("\t")
	if parts.size() != 4:
		return true
	var doc := _doc(parts[1])
	if doc == null:
		return true
	var phase := "continue"
	if _build_token != token:
		phase = "start"
		if token == _restart and _resume:
			phase = "resume"
		elif token == _restart or _build_token != "":
			phase = "restart"
		_restart = ""
		_open_build(token, doc, int(parts[2]), int(parts[3]))
		if phase == "resume":
			_build_beliefs = _saved_beliefs
			if _saved_claim_ok:
				_build_claim = _saved_claim
		_resume = false
		_saved_beliefs = {}
		_saved_claim = {}
		_saved_claim_ok = false
	elif deeds != null and deeds.generation() != _build_gen:
		phase = "restart"
		_open_build(token, doc, int(parts[2]), int(parts[3]))
	var budget := _slice_rows()
	var consumed := 0
	while consumed < budget and _build_at < _build_rows.size():
		var index := int(_build_rows[_build_at])
		_build_at += 1
		consumed += 1
		if index < 0 or index >= _build_limit:
			continue
		_fill_known(_build_seen, index, _build_set, _build_since, _build_verb, true)
	if _build_at < _build_rows.size():
		_trace_slice(phase, consumed)
		return false
	if phase == "restart" or phase == "resume":
		_trace_slice(phase, consumed)
	_commit_build(doc, consumed)
	return true


func _enqueue_doc(doc: WyrdDocumentDef, now: int, cap: int) -> void:
	if doc == null or doc.period_minutes <= 0:
		return
	var missed := _missed(doc, now)
	var take := missed.size()
	if cap < take:
		take = cap
	var number := int(_published(doc)["n"])
	for index in missed.size():
		number += 1
		var due := int(missed[index])
		_memory_n[doc.id] = number
		if index < take:
			_queued["%s\t%d" % [doc.id, due]] = true
			enqueue_of.call("issue\t%s\t%d\t%d" % [doc.id, number, due])
		else:
			_write(doc, "skip %s#%d due=%d" % [doc.id, number, due])
	_covered[doc.id] = now


func _missed(doc: WyrdDocumentDef, now: int) -> Array:
	var out: Array = []
	if now < doc.delay_minutes or doc.period_minutes <= 0:
		return out
	var due := doc.delay_minutes
	var covered := int(_covered.get(doc.id, -1))
	if covered >= doc.delay_minutes:
		var steps := _div_floor(covered - doc.delay_minutes, doc.period_minutes) + 1
		due = doc.delay_minutes + steps * doc.period_minutes
	var issued: Dictionary = _published(doc)["dues"]
	var guard := 0
	while due <= now and guard < 100000:
		guard += 1
		var key := "%s\t%d" % [doc.id, due]
		if not issued.has(due) and not _queued.has(key):
			out.append(due)
		due += doc.period_minutes
	return out


func _published(doc: WyrdDocumentDef) -> Dictionary:
	var number := int(_memory_n.get(doc.id, 0))
	var dues := {}
	var prefix := "%s#" % doc.id
	for raw in _fact_text(doc).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ")
		var head := parts[0]
		var copy := ""
		if head == "skip":
			if parts.size() < 2:
				continue
			copy = parts[1]
		elif head.begins_with(prefix):
			copy = head
		if not copy.begins_with(prefix):
			continue
		var num_text := copy.substr(prefix.length())
		if not num_text.is_valid_int():
			continue
		var found := int(num_text)
		if found > number:
			number = found
		var due := _field(line, "due")
		if due >= 0:
			dues[due] = true
	return {"dues": dues, "n": number}


func _claim(doc: WyrdDocumentDef, members: PackedStringArray) -> Dictionary:
	if doc.claim_key.is_empty() or facts == null:
		return {"source": "none", "value": ""}
	var key := StringName(doc.claim_key)
	var names: Array = []
	for member in members:
		names.append(String(member))
	names.sort()
	for who in names:
		var believed: Variant = facts.get_in(key, StringName("believed/%s" % who))
		if believed != null:
			return {"source": "belief", "value": String(believed)}
	for who in names:
		var known: Variant = facts.get_in(key, StringName("known/%s" % who))
		if known != null:
			return {"source": "known", "value": String(known)}
	var world: Variant = facts.get_in(key, &"world")
	if world != null:
		return {"source": "world", "value": String(world)}
	return {"source": "none", "value": ""}


func _slant(doc: WyrdDocumentDef) -> String:
	if not eval_of.is_valid():
		return ""
	for fragment in doc.fragments:
		var cond: WyrdCompiledCondition = fragment.get("when") as WyrdCompiledCondition
		if cond != null and bool(eval_of.call(cond)):
			return String(fragment.get("slant", ""))
	return ""


func _write(doc: WyrdDocumentDef, line: String) -> void:
	if doc.fact_key.is_empty() or facts == null:
		return
	var key := StringName(doc.fact_key)
	var prior: Variant = facts.get_in(key, &"world")
	var text := ""
	if prior != null:
		text = String(prior)
	if not text.is_empty():
		text += "\n"
	text += line
	if not facts.set_in(key, text, &"world"):
		push_error("WyrdPublish.issue: could not store %s" % line.split(" ")[0])


func _fact_text(doc: WyrdDocumentDef) -> String:
	if doc.fact_key.is_empty() or facts == null:
		return ""
	var prior: Variant = facts.get_in(StringName(doc.fact_key), &"world")
	if prior == null:
		return ""
	return String(prior)


func _doc(id: String) -> WyrdDocumentDef:
	var content := _content()
	if content == null or not content.documents.has(id):
		return null
	return content.documents[id] as WyrdDocumentDef


func _content() -> WyrdContent:
	if not content_of.is_valid():
		return null
	var raw: Variant = content_of.call()
	if raw is WyrdContent:
		return raw as WyrdContent
	return null


func _members(group: String) -> PackedStringArray:
	var rows := PackedStringArray()
	if group.is_empty() or not members_of.is_valid():
		return rows
	var raw: Variant = members_of.call(StringName(group))
	if raw is PackedStringArray:
		rows = (raw as PackedStringArray).duplicate()
	elif raw is Array:
		for item in raw:
			rows.append(String(item))
	rows.sort()
	return rows


func _candidate_rows(members: PackedStringArray, start: int, verb: String) -> PackedInt32Array:
	var rows := PackedInt32Array()
	if deeds == null:
		return rows
	if not deeds.lookup_enabled():
		rows.resize(deeds.size())
		for index in deeds.size():
			rows[index] = index
		return rows
	if not verb.is_empty():
		var indexes := deeds.verb_indexes(StringName(verb))
		if start <= 0:
			return indexes.duplicate()
		var window := {}
		for index in deeds.rows_since(start):
			window[int(index)] = true
		var seen := {}
		for index in indexes:
			var row := int(index)
			if not window.has(row) and not _row_believed(row, members, start):
				continue
			if seen.has(row):
				continue
			seen[row] = true
			rows.append(row)
		return rows
	var seen := {}
	if start > 0:
		for index in deeds.rows_since(start):
			var row := int(index)
			if seen.has(row):
				continue
			seen[row] = true
			rows.append(row)
	else:
		for member in members:
			for index in deeds.witness_indexes(StringName(String(member))):
				var row := int(index)
				if seen.has(row):
					continue
				seen[row] = true
				rows.append(row)
	for member in members:
		var owned: Dictionary = deeds.believer_index(StringName(String(member)))
		for deed_id in owned.keys():
			if int(owned[deed_id]) < start:
				continue
			var index := deeds.index_of(int(deed_id))
			if index < 0 or seen.has(index):
				continue
			seen[index] = true
			rows.append(index)
	return rows


func _row_believed(index: int, members: PackedStringArray, start: int) -> bool:
	var bag: Dictionary = deeds.believer_minutes(deeds.id_at(index))
	if bag.is_empty():
		return false
	for member in members:
		var who := String(member)
		if bag.has(who) and int(bag[who]) >= start:
			return true
	return false


func _fill_known(
	seen: Dictionary,
	index: int,
	gate: Dictionary,
	start: int,
	verb: String,
	frozen: bool = false
) -> void:
	if deeds == null:
		return
	if not verb.is_empty() and String(deeds.verb_at(index)) != verb:
		return
	var minute := deeds.minute_at(index)
	var deed_id := deeds.id_at(index)
	var actor := String(deeds.actor_at(index))
	var place := String(deeds.place_at(index))
	var verb_name := String(deeds.verb_at(index))
	var layers := {}
	var times := {}
	var names: Array = []
	if minute >= start:
		var count := deeds.witness_count_at(index)
		for offset in count:
			var who := deeds.witness_name_at(index, offset)
			if not gate.has(who):
				continue
			var mode := deeds.witness_mode_name_at(index, offset)
			layers[who] = "known" if mode == "saw" else "believed"
			times[who] = minute
			names.append(who)
	var bag: Dictionary = {}
	if frozen:
		if _build_beliefs.has(deed_id):
			bag = _build_beliefs[deed_id]
	else:
		bag = deeds.believer_minutes(deed_id)
	for who in bag.keys():
		var name := String(who)
		if not gate.has(name):
			continue
		var at := int(bag[who])
		if at < start:
			continue
		if not times.has(name) or at < int(times[name]):
			times[name] = at
		if not layers.has(name):
			layers[name] = "believed"
			names.append(name)
	if names.is_empty():
		return
	names.sort()
	for who in names:
		var name := String(who)
		_include_fields(seen, deed_id, actor, place, verb_name, name, String(layers[name]), int(times[name]))


func _include_fields(
	seen: Dictionary,
	deed_id: int,
	actor: String,
	place: String,
	verb_name: String,
	who: String,
	layer: String,
	at: int
) -> void:
	if not seen.has(deed_id):
		seen[deed_id] = {
			"actor": actor,
			"id": deed_id,
			"knowers": [],
			"mode": "believed",
			"place": place,
			"t": at,
			"verb": verb_name,
			"_seen": {},
		}
	var entry: Dictionary = seen[deed_id]
	if at < int(entry["t"]):
		entry["t"] = at
	var known: Dictionary = entry["_seen"]
	if known.has(who):
		if layer == "known":
			_mark_known(entry, who)
		seen[deed_id] = entry
		return
	known[who] = true
	entry["_seen"] = known
	var knowers: Array = entry["knowers"]
	knowers.append({"layer": layer, "who": who})
	entry["knowers"] = knowers
	if layer == "known":
		entry["mode"] = "known"
	seen[deed_id] = entry


func _sorted_known(seen: Dictionary) -> Array:
	var rows: Array = []
	var order: Array = seen.keys()
	order.sort()
	for deed_id in order:
		var entry: Dictionary = seen[deed_id]
		entry.erase("_seen")
		rows.append(entry)
	return rows


func _member_set(members: PackedStringArray) -> Dictionary:
	var gate := {}
	for member in members:
		var who := String(member)
		if not who.is_empty():
			gate[who] = true
	return gate


func _open_build(token: String, doc: WyrdDocumentDef, number: int, due: int) -> void:
	var since := due - doc.period_minutes
	if since < 0:
		since = 0
	var members := _members(doc.group)
	var verb := String(doc.verb_filter)
	_build_token = token
	_build_at = 0
	_build_rows = _candidate_rows(members, since, verb)
	_build_seen = {}
	_build_members = members
	_build_set = _member_set(members)
	_build_since = since
	_build_verb = verb
	_build_due = due
	_build_number = number
	_build_doc = doc.id
	_build_claim = _frozen_claim(doc, members)
	_build_gen = deeds.generation() if deeds != null else 0
	_build_limit = deeds.size() if deeds != null else 0
	_build_beliefs = deeds.believer_snapshot(_build_set) if deeds != null else {}


func _commit_build(doc: WyrdDocumentDef, consumed: int) -> void:
	var window: Array = []
	for row in _sorted_known(_build_seen):
		if int(row["t"]) < _build_due:
			window.append(row)
	var ids := PackedStringArray()
	for row in window:
		ids.append(str(int(row["id"])))
	var copy_id := "%s#%d" % [doc.id, _build_number]
	var line := "%s due=%d deeds=%d ids=%s claim=%s source=%s" % [
		copy_id,
		_build_due,
		window.size(),
		",".join(ids),
		str(_build_claim.get("value", "")),
		str(_build_claim.get("source", "none")),
	]
	_queued.erase("%s\t%d" % [doc.id, _build_due])
	_write(doc, line)
	_trace_slice("done", consumed)
	if trace_of.is_valid():
		trace_of.call({
			"deeds": window.size(),
			"document": doc.id,
			"issue": copy_id,
			"key": copy_id,
			"path": doc.id,
			"who": doc.group,
		})
	_clear_build()


func _frozen_claim(doc: WyrdDocumentDef, members: PackedStringArray) -> Dictionary:
	var claim := _claim(doc, members)
	var slant := _slant(doc)
	if not slant.is_empty():
		return {"source": "slant", "value": slant}
	return claim


func _clear_build() -> void:
	_build_token = ""
	_build_at = 0
	_build_rows = PackedInt32Array()
	_build_seen = {}
	_build_members = PackedStringArray()
	_build_set = {}
	_build_since = 0
	_build_verb = ""
	_build_due = 0
	_build_number = 0
	_build_doc = ""
	_build_claim = {}
	_build_gen = 0
	_build_limit = 0
	_build_beliefs = {}


func _slice_rows() -> int:
	if not config_of.is_valid():
		return 128
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return maxi((config as WyrdConfig).publish_slice_rows, 1)
	return 128


func _trace_slice(phase: String, consumed: int) -> void:
	if not cursor_trace_of.is_valid() or _build_doc.is_empty():
		return
	var copy_id := "%s#%d" % [_build_doc, _build_number]
	cursor_trace_of.call({
		"budget": _slice_rows(),
		"document": _build_doc,
		"issue": copy_id,
		"key": copy_id,
		"path": _build_doc,
		"phase": phase,
		"rows": consumed,
		"who": phase,
	})


func _mark_known(entry: Dictionary, who: String) -> void:
	var knowers: Array = entry["knowers"]
	for item in knowers:
		if item is Dictionary and String(item.get("who", "")) == who:
			item["layer"] = "known"
	entry["knowers"] = knowers
	entry["mode"] = "known"


func _now() -> int:
	if not now_of.is_valid():
		return 0
	return maxi(int(now_of.call()), 0)


func _cap() -> int:
	if not config_of.is_valid():
		return 3
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return maxi((config as WyrdConfig).publish_catchup_max, 0)
	return 3


func _field(line: String, name: String) -> int:
	var needle := "%s=" % name
	for part in line.split(" "):
		if not part.begins_with(needle):
			continue
		var rest := part.substr(needle.length())
		if rest.is_valid_int():
			return int(rest)
	return -1


static func _div_floor(numer: int, denom: int) -> int:
	if denom == 0:
		return 0
	return int(floor(float(numer) / float(denom)))
