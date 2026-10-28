class_name WyrdTopics
extends RefCounted

## The player's unlocked topic ids.
##
## There is no topic declaration. An id is whatever [code]unlock topic[/code],
## [code]lock topic[/code], or [code]scope: topic[/code] uses. A repeat unlock
## traces [code]already[/code] and does not signal again. A lock of a topic
## that is not unlocked traces [code]not_unlocked[/code] and does not warn.
## The save bag is a sorted id list, omitted when empty. Unknown ids are kept.

## Fires when a topic becomes unlocked. A repeat unlock does not fire.
signal topic_unlocked(topic: StringName)
## @experimental
signal topic_locked(topic: StringName)

## @experimental
var trace_of: Callable = Callable()
## @experimental
var runtime: WyrdRuntime

var _ids: Dictionary = {}


## @experimental
func is_unlocked(id: StringName) -> bool:
	return _ids.has(id)


## @experimental
func unlocked() -> PackedStringArray:
	var names := PackedStringArray()
	for id in _ids.keys():
		names.append(String(id))
	names.sort()
	return names


## @experimental
func unlock(id: StringName) -> String:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null and runtime._host_logs():
		runtime._host_mark("topics.unlock", [id])
	if _ids.has(id):
		_trace("topic_unlock", id, false, "already")
		return "already"
	_ids[id] = true
	topic_unlocked.emit(id)
	_trace("topic_unlock", id, true, "unlocked")
	return "unlocked"


## @experimental
func lock(id: StringName) -> String:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null and runtime._host_logs():
		runtime._host_mark("topics.lock", [id])
	if not _ids.has(id):
		_trace("topic_lock", id, false, "not_unlocked")
		return "not_unlocked"
	_ids.erase(id)
	topic_locked.emit(id)
	_trace("topic_lock", id, true, "locked")
	return "locked"


## @experimental
func clear() -> void:
	_ids.clear()


## @experimental
func export_state() -> PackedStringArray:
	return unlocked()


## @experimental
func import_state(ids: Array) -> void:
	_ids.clear()
	for item in ids:
		var name := WyrdSave.text_of(item, "").strip_edges()
		if name.is_empty():
			continue
		_ids[StringName(name)] = true


func _trace(kind: String, id: StringName, ok: bool, reason: String) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call(kind, {
		"key": String(id),
		"ok": "true" if ok else "false",
		"reason": reason,
		"topic": String(id),
	})
