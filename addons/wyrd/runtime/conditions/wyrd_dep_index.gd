class_name WyrdDepIndex
extends RefCounted

## Fact-key to condition-index map, built from compiled reads.
##
## @experimental
## Condition identity is the index passed to [method build]. Exact keys live in
## [member exact]. A read with a [code]{...}[/code] segment is a pattern: it is
## stored by segment count and static prefix, and a changed key matches only
## when every segment agrees. The prefix is a lookup bucket. The condition
## still depends on the whole pattern, so a computed segment ([code]LOAD_KEY[/code])
## is never resolved here. Rebuilt from plain reads. Never saved.

var exact: Dictionary[StringName, PackedInt32Array] = {}
var entries: int = 0
var keys: int = 0

var _by_count: Array = []
var _pattern_count: int = 0
var _seen: PackedInt32Array = PackedInt32Array()
var _hits: PackedInt32Array = PackedInt32Array()
var _generation: int = 0


func build(conditions: Array[WyrdCompiledCondition]) -> void:
	exact.clear()
	_by_count.clear()
	entries = 0
	keys = 0
	_pattern_count = 0
	_generation = 0
	_seen = PackedInt32Array()
	_seen.resize(conditions.size())
	_hits = PackedInt32Array()
	_hits.resize(conditions.size())
	for index in conditions.size():
		var compiled := conditions[index]
		if compiled == null:
			continue
		for read in compiled.reads:
			_add(read, index)
	keys = exact.size() + _pattern_count


func affected(changed_keys: Array[StringName]) -> PackedInt32Array:
	_generation += 1
	if _generation == 0x7fffffff:
		_seen.fill(0)
		_generation = 1
	var count := 0
	var use_patterns := _pattern_count > 0
	for key in changed_keys:
		count = _take_exact(key, count)
		if use_patterns:
			count = _take_patterns(key, count)
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = _hits[i]
	out.sort()
	return out


func _add(read: StringName, index: int) -> void:
	var text := String(read)
	if text.is_empty():
		return
	var segments := text.split(".")
	var wild := PackedByteArray()
	wild.resize(segments.size())
	var patterned := false
	for i in segments.size():
		if segments[i].begins_with("{"):
			wild[i] = 1
			patterned = true
	if not patterned:
		_add_exact(read, index)
		return
	var prefix := ""
	for i in segments.size():
		if wild[i] != 0:
			break
		if not prefix.is_empty():
			prefix += "."
		prefix += segments[i]
	var width := segments.size()
	var bucket: Dictionary = _bucket(width)
	var group: Array = bucket[prefix] if bucket.has(prefix) else []
	for row_at in group.size():
		var row: Dictionary = group[row_at]
		var have: PackedStringArray = row["segments"]
		if not _same_segments(have, segments):
			continue
		var conds: PackedInt32Array = row["conds"]
		if conds.size() > 0 and conds[conds.size() - 1] == index:
			return
		conds.append(index)
		row["conds"] = conds
		group[row_at] = row
		bucket[prefix] = group
		_by_count[width] = bucket
		entries += 1
		return
	group.append({
		"conds": PackedInt32Array([index]),
		"segments": segments,
		"wild": wild,
	})
	bucket[prefix] = group
	_by_count[width] = bucket
	_pattern_count += 1
	entries += 1


func _add_exact(read: StringName, index: int) -> void:
	var row := PackedInt32Array()
	if exact.has(read):
		row = exact[read]
		if row.size() > 0 and row[row.size() - 1] == index:
			return
	row.append(index)
	exact[read] = row
	entries += 1


func _bucket(count: int) -> Dictionary:
	while _by_count.size() <= count:
		_by_count.append({})
	return _by_count[count]


func _take_exact(key: StringName, count: int) -> int:
	if not exact.has(key):
		return count
	var row: PackedInt32Array = exact[key]
	for cond in row:
		count = _mark(int(cond), count)
	return count


func _take_patterns(key: StringName, count: int) -> int:
	var segments := String(key).split(".")
	var width := segments.size()
	if width >= _by_count.size():
		return count
	var bucket: Dictionary = _by_count[width]
	if bucket.is_empty():
		return count
	count = _take_group(bucket, "", segments, count)
	var prefix := ""
	for i in width:
		if i > 0:
			prefix += "."
		prefix += segments[i]
		count = _take_group(bucket, prefix, segments, count)
	return count


func _take_group(bucket: Dictionary, prefix: String, segments: PackedStringArray, count: int) -> int:
	if not bucket.has(prefix):
		return count
	var group: Array = bucket[prefix]
	for row in group:
		var have: PackedStringArray = row["segments"]
		var wild: PackedByteArray = row["wild"]
		if not _pattern_hit(have, wild, segments):
			continue
		var conds: PackedInt32Array = row["conds"]
		for cond in conds:
			count = _mark(int(cond), count)
	return count


func _same_segments(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	for i in left.size():
		if left[i] != right[i]:
			return false
	return true


func _pattern_hit(have: PackedStringArray, wild: PackedByteArray, segments: PackedStringArray) -> bool:
	for i in have.size():
		if wild[i] == 0 and have[i] != segments[i]:
			return false
	return true


func _mark(cond: int, count: int) -> int:
	if cond < 0 or cond >= _seen.size() or _seen[cond] == _generation:
		return count
	_seen[cond] = _generation
	_hits[count] = cond
	return count + 1
