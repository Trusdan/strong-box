class_name WyrdTickQueue
extends RefCounted

## Per-tick work list for waiting conditions.
##
## @experimental
## A fixed budget, from [member WyrdConfig.scheduler_work_per_tick], re-checks
## dirty indexes in ascending order. The rest stay dirty. The sort is taken
## once per [method tick] call. A mark during that call joins the next call,
## still in ascending order. Which indexes are watched is rebuilt from the
## content index. The dirty set is saved.

var last_rechecks: int = 0

var _dirty: Dictionary = {}
var _waiting: Dictionary = {}
## Sorted dirty indexes for the current cursor. Packed so a drained list of
## every condition is not a variant array sitting on the heap. Dropped when
## the cursor finishes.
var _order := PackedInt32Array()
var _order_at: int = 0
var _order_gen: int = 0
var _dirty_gen: int = 1


func clear() -> void:
	_dirty.clear()
	_waiting.clear()
	last_rechecks = 0
	_order = PackedInt32Array()
	_order_at = 0
	_dirty_gen += 1
	_order_gen = _dirty_gen


func watch(index: int) -> void:
	_waiting[index] = true
	_dirtify(index)


func unwatch(index: int) -> void:
	_waiting.erase(index)
	_dirty.erase(index)


func mark(indexes: PackedInt32Array) -> void:
	for index in indexes:
		_dirtify(int(index))


func dirty_count() -> int:
	return _dirty.size()


func is_dirty(index: int) -> bool:
	return _dirty.has(index)


func dirty_indexes() -> PackedInt32Array:
	var keys: Array = _dirty.keys()
	keys.sort()
	var out := PackedInt32Array()
	for key in keys:
		out.append(int(key))
	return out


## Replaces the dirty set with [param indexes] that are still watched.
func restore_dirty(indexes: Array) -> void:
	_dirty.clear()
	_dirty_gen += 1
	for index in indexes:
		var at := WyrdSave._whole(index, -1)
		if _waiting.has(at):
			_dirty[at] = true


## [param eval_one] receives a condition index and returns nothing.
func tick(budget: int, eval_one: Callable) -> int:
	if _order_gen != _dirty_gen:
		var keys: Array = _dirty.keys()
		keys.sort()
		_order = PackedInt32Array(keys)
		_order_at = 0
		_order_gen = _dirty_gen
	var ran := 0
	var cap := budget if budget > 0 else 0
	while ran < cap and _order_at < _order.size():
		var index := int(_order[_order_at])
		_order_at += 1
		if not _dirty.has(index):
			continue
		_dirty.erase(index)
		if eval_one.is_valid():
			eval_one.call(index)
		ran += 1
	if _order_at >= _order.size():
		_order = PackedInt32Array()
	last_rechecks = ran
	return ran


func _dirtify(at: int) -> void:
	if not _waiting.has(at) or _dirty.has(at):
		return
	_dirty[at] = true
	_dirty_gen += 1


## Re-checks [param indexes] that are watched, in ascending order, ignoring the
## tick budget. Other dirty indexes stay dirty. Returns the indexes that ran.
func recheck_some(indexes: PackedInt32Array, eval_one: Callable) -> PackedInt32Array:
	var ordered: Array[int] = []
	for index in indexes:
		var at := int(index)
		if not ordered.has(at):
			ordered.append(at)
	ordered.sort()
	var ran := PackedInt32Array()
	for index in ordered:
		if not _waiting.has(index):
			continue
		_dirty.erase(index)
		if eval_one.is_valid():
			eval_one.call(index)
		ran.append(index)
	last_rechecks = ran.size()
	return ran
