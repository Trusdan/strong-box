class_name WyrdSequences
extends RefCounted

## Timed event sequences. Partial progress is saved. Not a quest stage.
##
## @experimental
## [code]ordered[/code] matches steps in source order. [code]any[/code] with one
## step counts that step up to [code]m[/code]. [code]any[/code] with several steps
## counts each step once. The window is game minutes and includes the minute it
## closes. A finished sequence stays finished until its reset. A reset event is
## handled before a step on that same emit, so the reset does not also count.

var runtime: WyrdRuntime
var _defs: Dictionary = {}
var _rows: Dictionary = {}


func bind(host: WyrdRuntime) -> void:
	runtime = host
	_defs.clear()
	_rows.clear()
	if host == null or host.content() == null:
		return
	var ids: Array = host.content().sequences.keys()
	ids.sort()
	for id in ids:
		_defs[String(id)] = host.content().sequences[id]


func clear() -> void:
	_rows.clear()


func progress(id: String) -> int:
	if not _defs.has(id):
		push_error("WyrdSequences.progress: unknown sequence \"%s\"" % id)
		return 0
	if not _rows.has(id):
		return 0
	return int((_rows[id] as Dictionary).get("count", 0))


func done(id: String) -> bool:
	if not _defs.has(id):
		push_error("WyrdSequences.done: unknown sequence \"%s\"" % id)
		return false
	if not _rows.has(id):
		return false
	return bool((_rows[id] as Dictionary).get("done", false))


func on_tick() -> void:
	if runtime == null:
		return
	var changed := false
	var ids: Array = _defs.keys()
	ids.sort()
	for id in ids:
		var def := _defs[id] as WyrdSequenceDef
		if def == null:
			continue
		var had := _rows.has(String(id))
		var row := _blank()
		if had:
			row = (_rows[String(id)] as Dictionary).duplicate(true)
		var before := _sig(row)
		if not bool(row.get("done", false)):
			_expire(def, row)
		if _sig(row) != before:
			changed = true
			_store(String(id), row)
			_trace(String(id), row, "expire")
			before = _sig(row)
		if def.reset_cond != null and runtime.eval_bool(def.reset_cond):
			_clear_row(row)
		if _sig(row) != before:
			changed = true
			_store(String(id), row)
			_trace(String(id), row, "reset")
		elif had:
			_store(String(id), row)
	if changed:
		_mark()


func on_emit(event_name: StringName, payload: Dictionary) -> void:
	if runtime == null or _defs.is_empty():
		return
	var locals := {}
	var keys: Array = payload.keys()
	keys.sort()
	for key in keys:
		locals["event.%s" % String(key)] = payload[key]
	var changed := false
	var ids: Array = _defs.keys()
	ids.sort()
	for id in ids:
		var def := _defs[String(id)] as WyrdSequenceDef
		if def == null:
			continue
		if _on_one(String(id), def, String(event_name), locals):
			changed = true
	if changed:
		_mark()


func export_state() -> Dictionary:
	var out := {}
	var ids: Array = _rows.keys()
	ids.sort()
	for id in ids:
		var row := _rows[id] as Dictionary
		if row == null or _empty(row):
			continue
		var item := {
			"count": int(row.get("count", 0)),
			"done": bool(row.get("done", false)),
		}
		var matched: Array = row.get("matched", [])
		if not matched.is_empty():
			var copied: Array = []
			for entry in matched:
				copied.append(int(entry))
			item["matched"] = copied
		if int(row.get("started", -1)) >= 0:
			item["started"] = int(row.get("started", -1))
		out[String(id)] = item
	return out


func stored_ids() -> PackedStringArray:
	var names: Array = _rows.keys()
	names.sort()
	var out := PackedStringArray()
	for id in names:
		out.append(String(id))
	return out


func import_state(data: Dictionary) -> void:
	_rows.clear()
	for id in data.keys():
		var raw: Variant = data[id]
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		var matched: Array = []
		var listed: Variant = item.get("matched", [])
		if listed is Array:
			for entry in listed:
				matched.append(WyrdSave._whole(entry, 0))
		var started := -1
		if item.has("started"):
			started = WyrdSave._whole(item.get("started", -1), -1)
		_rows[String(id)] = {
			"count": WyrdSave._whole(item.get("count", 0), 0),
			"done": WyrdSave.flag_of(item.get("done", false), false),
			"matched": matched,
			"started": started,
		}


func _on_one(id: String, def: WyrdSequenceDef, event_name: String, locals: Dictionary) -> bool:
	var had := _rows.has(id)
	var row := _blank()
	if had:
		row = (_rows[id] as Dictionary).duplicate(true)
	var before := _sig(row)
	var moved := false
	if not bool(row.get("done", false)):
		_expire(def, row)
	if _sig(row) != before:
		_store(id, row)
		_trace(id, row, "expire")
		before = _sig(row)
		moved = true
	if def.reset_event != "" and def.reset_event == event_name:
		_clear_row(row)
		if _sig(row) != before:
			_store(id, row)
			_trace(id, row, "reset")
			return true
		return moved
	if bool(row.get("done", false)):
		return moved
	if def.mode == &"any" and def.steps.size() == 1:
		_match_repeat(def, row, event_name, locals)
	elif def.mode == &"any":
		_match_distinct(def, row, event_name, locals)
	else:
		_match_ordered(def, row, event_name, locals)
	if _sig(row) == before:
		return moved
	_store(id, row)
	var reason := "done" if bool(row.get("done", false)) else "step"
	_trace(id, row, reason)
	return true


func _trace(id: String, row: Dictionary, reason: String) -> void:
	if runtime == null:
		return
	runtime.trace_sequence(id, int(row.get("count", 0)), bool(row.get("done", false)), reason)


func _match_ordered(def: WyrdSequenceDef, row: Dictionary, event_name: String, locals: Dictionary) -> void:
	var index := int(row.get("count", 0))
	if index < 0 or index >= def.steps.size():
		return
	var step := def.steps[index]
	if not _step_ok(step, event_name, locals):
		return
	_note_start(row)
	row["count"] = index + 1
	if int(row["count"]) >= def.steps.size():
		row["done"] = true


func _match_repeat(def: WyrdSequenceDef, row: Dictionary, event_name: String, locals: Dictionary) -> void:
	if def.steps.is_empty():
		return
	if int(row.get("count", 0)) >= def.total:
		return
	if not _step_ok(def.steps[0], event_name, locals):
		return
	_note_start(row)
	row["count"] = int(row.get("count", 0)) + 1
	if int(row["count"]) >= def.need:
		row["done"] = true


func _match_distinct(def: WyrdSequenceDef, row: Dictionary, event_name: String, locals: Dictionary) -> void:
	var matched: Array = row.get("matched", [])
	if matched.size() >= def.total:
		return
	for index in def.steps.size():
		if matched.has(index):
			continue
		if not _step_ok(def.steps[index], event_name, locals):
			continue
		_note_start(row)
		matched.append(index)
		row["matched"] = matched
		row["count"] = matched.size()
		if int(row["count"]) >= def.need:
			row["done"] = true
		return


func _step_ok(step: WyrdOnEventDef, event_name: String, locals: Dictionary) -> bool:
	if step == null or step.event_name != event_name:
		return false
	if step.where_cond == null:
		return false
	return runtime.eval_with_locals(step.where_cond, locals)


func _expire(def: WyrdSequenceDef, row: Dictionary) -> void:
	if bool(row.get("done", false)):
		return
	var started := int(row.get("started", -1))
	if started < 0 or runtime == null:
		return
	if runtime.now_minutes() > started + def.within_minutes:
		_clear_row(row)


func _note_start(row: Dictionary) -> void:
	if int(row.get("count", 0)) != 0 or int(row.get("started", -1)) >= 0:
		return
	if runtime == null:
		row["started"] = 0
		return
	row["started"] = runtime.now_minutes()


func _clear_row(row: Dictionary) -> void:
	row["count"] = 0
	row["done"] = false
	row["matched"] = []
	row["started"] = -1


func _store(id: String, row: Dictionary) -> void:
	if _empty(row):
		_rows.erase(id)
		return
	_rows[id] = row


func _empty(row: Dictionary) -> bool:
	return int(row.get("count", 0)) == 0 and not bool(row.get("done", false)) and int(row.get("started", -1)) < 0


func _blank() -> Dictionary:
	return {"count": 0, "done": false, "matched": [], "started": -1}


func _sig(row: Dictionary) -> String:
	return "%d|%s|%d|%s" % [int(row.get("count", 0)), str(bool(row.get("done", false))), int(row.get("started", -1)), str(row.get("matched", []))]


func _mark() -> void:
	if runtime != null:
		runtime.note_sequence_change()
