class_name WyrdCastIndex
extends RefCounted

## Derived candidate cache for hosts that report world changes. Not saved.
##
## @experimental
## A base list is one [method WyrdWorldAdapter.candidates] answer, deduped and
## sorted the same way as a full scan. A local list is the entities in that
## answer that pass a plan's local clauses. [method invalidate] with ids marks
## every base list stale and drops those ids' cached results. The next use
## asks the host once per filter and diffs. An empty id list drops everything.

var _bases: Dictionary = {}
var _locals: Dictionary = {}


func clear() -> void:
	_bases.clear()
	_locals.clear()


func invalidate(ids: PackedStringArray) -> void:
	if ids.is_empty():
		clear()
		return
	for entry in _bases.values():
		var base: Dictionary = entry
		base["stale"] = true
		base["digest_ready"] = false
	for entry in _locals.values():
		var row: Dictionary = entry
		var results: Dictionary = row["results"]
		for id in ids:
			results.erase(String(id))
		row["dirty"] = true


func store_digest(filter_key: String, digest: int) -> void:
	if not _bases.has(filter_key):
		return
	var base: Dictionary = _bases[filter_key]
	base["digest"] = digest
	base["digest_ready"] = true


## [param accepts] is [code](condition, entity) -> bool[/code].
## [param pin_value] is [code](condition) -> Variant[/code].
## [param scope_ok] is [code](condition) -> bool[/code].
func pool(
	plan: WyrdCastPlan,
	world: WyrdWorldAdapter,
	accepts: Callable,
	pin_value: Callable,
	scope_ok: Callable
) -> Dictionary:
	var base := _base(plan, world)
	var raw: Array = base["ids"]
	var empty := {
		"accepted": [],
		"digest": int(base["digest"]),
		"digest_ready": bool(base["digest_ready"]),
		"filter": plan.filter_key(),
		"raw": raw,
	}
	if not _scopes(plan, scope_ok):
		return empty
	var row := _local_row(plan, base, accepts)
	var ids: Array = row["passed"]
	if plan.pin != null:
		ids = _pinned(pin_value.call(plan.pin), row)
	if not plan.rest.is_empty():
		ids = _rest(ids, plan, accepts)
	return {
		"accepted": ids,
		"digest": int(base["digest"]),
		"digest_ready": bool(base["digest_ready"]),
		"filter": plan.filter_key(),
		"raw": raw,
	}


func _scopes(plan: WyrdCastPlan, scope_ok: Callable) -> bool:
	for cond in plan.scope:
		if not bool(scope_ok.call(cond)):
			return false
	return true


func _base(plan: WyrdCastPlan, world: WyrdWorldAdapter) -> Dictionary:
	var filter_key := plan.filter_key()
	if _bases.has(filter_key):
		var cached: Dictionary = _bases[filter_key]
		if not bool(cached["stale"]):
			return cached
		return _refresh(filter_key, cached, _ask(plan, world))
	var ids := _ask(plan, world)
	var created := {
		"digest": 0,
		"digest_ready": false,
		"ids": ids,
		"set": _set_of(ids),
		"stale": false,
	}
	_bases[filter_key] = created
	return created


func _refresh(filter_key: String, base: Dictionary, ids: Array) -> Dictionary:
	var previous: Dictionary = base["set"]
	var nxt := _set_of(ids)
	var removed: Array = []
	for id in previous.keys():
		if not nxt.has(id):
			removed.append(id)
	base["ids"] = ids
	base["set"] = nxt
	base["stale"] = false
	base["digest_ready"] = false
	_bases[filter_key] = base
	for entry in _locals.values():
		var row: Dictionary = entry
		if str(row["filter"]) != filter_key:
			continue
		var results: Dictionary = row["results"]
		for id in removed:
			results.erase(id)
		row["dirty"] = true
	return base


func _ask(plan: WyrdCastPlan, world: WyrdWorldAdapter) -> Array:
	var raw: Array = []
	if world == null:
		return raw
	var filter := WyrdEntityFilter.new()
	if plan.use_filter:
		filter = WyrdEntityFilter.new(StringName(plan.tag), StringName(plan.kind))
	var seen := {}
	for item in world.candidates(filter):
		var who := StringName(str(item))
		if who == &"" or seen.has(who):
			continue
		seen[who] = true
		raw.append(String(who))
	raw.sort()
	return raw


func _local_row(plan: WyrdCastPlan, base: Dictionary, accepts: Callable) -> Dictionary:
	var key := plan.key
	var row: Dictionary = _locals.get(key, {})
	if row.is_empty():
		row = {
			"dirty": true,
			"filter": plan.filter_key(),
			"passed": [],
			"results": {},
			"set": {},
		}
		_locals[key] = row
	if not bool(row["dirty"]):
		return row
	var results: Dictionary = row["results"]
	var passed: Array = []
	if plan.local.is_empty():
		passed = base["ids"]
		row["passed"] = passed
		row["set"] = base["set"]
		row["dirty"] = false
		return row
	var ids: Array = base["ids"]
	for id in ids:
		var text := String(id)
		var ok := false
		if results.has(text):
			ok = bool(results[text])
		else:
			ok = _local_accepts(plan, StringName(text), accepts)
			results[text] = ok
		if ok:
			passed.append(text)
	row["passed"] = passed
	row["results"] = results
	row["set"] = _set_of(passed)
	row["dirty"] = false
	_locals[key] = row
	return row


func _local_accepts(plan: WyrdCastPlan, entity: StringName, accepts: Callable) -> bool:
	for cond in plan.local:
		if not bool(accepts.call(cond, entity)):
			return false
	return true


func _pinned(value: Variant, row: Dictionary) -> Array:
	if value == null:
		return []
	var text := str(value)
	if text.is_empty():
		return []
	var have: Dictionary = row["set"]
	if not bool(have.get(text, false)):
		return []
	return [text]


func _rest(ids: Array, plan: WyrdCastPlan, accepts: Callable) -> Array:
	var kept: Array = []
	for id in ids:
		var entity := StringName(str(id))
		var ok := true
		for cond in plan.rest:
			if not bool(accepts.call(cond, entity)):
				ok = false
				break
		if ok:
			kept.append(String(id))
	return kept


func _set_of(ids: Array) -> Dictionary:
	var have := {}
	for id in ids:
		have[String(id)] = true
	return have
