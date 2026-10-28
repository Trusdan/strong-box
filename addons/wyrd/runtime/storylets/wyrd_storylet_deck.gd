class_name WyrdStoryletDeck
extends RefCounted

## Seeded draw of a storylet line set, plus director selection rows.
##
## @experimental
## [method draw] does not record a selection. [method note_selected] does.
## A known draw notifies [member on_coverage] with the storylet id and the line id.
## A [param visible] callback can skip a line. The cursor moves past a skip.
## A [code]line[/code] body and a [code]scene[/code] body write no draw row.
## A [code]set[/code] shuffles with [method WyrdRng.for_decision] on the
## [constant STREAM] stream, the storylet id, and the cycle number.
## The row stores that order, a cursor, and the cycle. The next cycle starts
## when the cursor reaches the end. [code]seen[/code] and [code]last_minute[/code]
## ride on the same row and are omitted when the storylet has never been selected.
## An id the pack does not declare is kept and ignored.
## Bark speaker clocks live in a separate bag, [code]bark_speakers[/code].

const STREAM: StringName = &"storylet_lines"

## [code](storylet_id, line_id)[/code] after a known storylet is drawn.
var on_coverage: Callable = Callable()
var _content: WyrdContent
var _seed: int = 0
var _rows: Dictionary = {}
## Save rows whose storylet id is not in the loaded pack. Ignored by draw and rank.
var _kept: Dictionary = {}
## Speaker id to [code]cooldown[/code] and [code]last_minute[/code]. Not storylet rows.
var _speakers: Dictionary = {}


func bind(content: WyrdContent) -> void:
	_content = content
	_rows.clear()
	_kept.clear()
	_speakers.clear()


func clear() -> void:
	_rows.clear()
	_kept.clear()
	_speakers.clear()


func clear_draws() -> void:
	_rows.clear()
	_kept.clear()


func clear_speakers() -> void:
	_speakers.clear()


func set_seed(seed_value: int) -> void:
	_seed = seed_value


func draw(id: String, visible: Callable = Callable()) -> Dictionary:
	var story := _story(id)
	if story == null:
		if _content == null:
			push_error("Wyrd.storylets.draw: load content before drawing a storylet")
		else:
			push_error("Wyrd.storylets.draw: unknown storylet \"%s\"" % id)
		return {}
	if story.body_kind == &"line":
		if story.lines.is_empty():
			push_error("Wyrd.storylets.draw: storylet \"%s\" has no line" % id)
			return {}
		if visible.is_valid() and not visible.call(story.lines[0]):
			return _drawn(story, "", 0)
		return _drawn(story, story.lines[0].line_id, 0)
	if story.body_kind == &"scene":
		return _drawn(story, "", 0)
	if story.body_kind != &"set":
		push_error("Wyrd.storylets.draw: storylet \"%s\" has no body" % id)
		return {}
	if story.lines.is_empty():
		push_error("Wyrd.storylets.draw: storylet \"%s\" has no lines" % id)
		return {}
	var row := _ensure(story)
	var order: PackedStringArray = row["order"]
	var cursor := int(row["cursor"])
	while cursor < order.size():
		var line_id := String(order[cursor])
		cursor += 1
		row["cursor"] = cursor
		var line := _line_by_id(story, line_id)
		if line != null and visible.is_valid() and not visible.call(line):
			continue
		return _drawn(story, line_id, int(row["cycle"]))
	return _drawn(story, "", int(row.get("cycle", 0)))


func seen_of(id: String) -> int:
	if not _rows.has(id):
		return 0
	return int((_rows[id] as Dictionary).get("seen", 0))


func last_minute_of(id: String) -> int:
	if not _rows.has(id):
		return -1
	return int((_rows[id] as Dictionary).get("last_minute", -1))


func note_bark_speaker(key: String, cooldown: int, minute: int) -> void:
	if key.is_empty() or cooldown <= 0:
		return
	_speakers[key] = {"cooldown": cooldown, "last_minute": minute}


func speaker_cooling(key: String, now_minute: int) -> bool:
	if key.is_empty() or not _speakers.has(key):
		return false
	var row: Dictionary = _speakers[key]
	return now_minute - int(row.get("last_minute", 0)) < int(row.get("cooldown", 0))


func speaker_cooldown_of(key: String) -> int:
	if not _speakers.has(key):
		return 0
	return int((_speakers[key] as Dictionary).get("cooldown", 0))


func speaker_remaining(key: String, now_minute: int) -> int:
	if not speaker_cooling(key, now_minute):
		return 0
	var row: Dictionary = _speakers[key]
	return int(row.get("cooldown", 0)) - (now_minute - int(row.get("last_minute", 0)))


func note_selected(id: String, minute: int) -> void:
	var row: Dictionary
	if _rows.has(id):
		row = _rows[id]
	else:
		row = {"seen": 0, "last_minute": -1}
		_rows[id] = row
	row["seen"] = int(row.get("seen", 0)) + 1
	row["last_minute"] = minute


func export_state() -> Dictionary:
	var pending := {}
	for id in _rows.keys():
		var item := _export_row(_rows[id])
		if not item.is_empty():
			pending[String(id)] = item
	for id in _kept.keys():
		if pending.has(String(id)):
			continue
		if _kept[id] is Dictionary:
			pending[String(id)] = (_kept[id] as Dictionary).duplicate(true)
	if pending.is_empty():
		return {}
	var names: Array = pending.keys()
	names.sort()
	var out := {}
	for id in names:
		out[String(id)] = pending[id]
	return out


func ignored_ids() -> PackedStringArray:
	var names: Array = _kept.keys()
	names.sort()
	var out := PackedStringArray()
	for id in names:
		out.append(String(id))
	return out


func export_speakers() -> Dictionary:
	if _speakers.is_empty():
		return {}
	var names: Array = _speakers.keys()
	names.sort()
	var out := {}
	for id in names:
		var row: Dictionary = _speakers[id]
		out[String(id)] = {
			"cooldown": int(row.get("cooldown", 0)),
			"last_minute": int(row.get("last_minute", 0)),
		}
	return out


## Unknown speaker ids are kept. A non-object entry is dropped.
func import_speakers(data: Dictionary) -> void:
	_speakers.clear()
	for key in data.keys():
		if not (data[key] is Dictionary):
			continue
		var raw: Dictionary = data[key]
		var cooldown := _whole(raw.get("cooldown", 0))
		if cooldown < 0:
			cooldown = 0
		var last := _whole(raw.get("last_minute", 0))
		if last < 0:
			last = 0
		_speakers[String(key)] = {"cooldown": cooldown, "last_minute": last}


## Drops line ids that are no longer in the set. Appends new ids in source order.
## The cursor is clamped to the new order. It is not remapped.
## An unknown storylet id is kept. A non-object entry is dropped.
func import_state(data: Dictionary) -> void:
	_rows.clear()
	_kept.clear()
	for key in data.keys():
		if not (data[key] is Dictionary):
			continue
		var id := String(key)
		var raw: Dictionary = data[key]
		var story := _story(id)
		if story == null:
			_kept[id] = raw.duplicate(true)
			continue
		var seen := _whole(raw.get("seen", 0))
		if seen < 0:
			seen = 0
		var last := -1
		if raw.has("last_minute"):
			last = _whole(raw.get("last_minute", -1))
			if last < 0:
				last = -1
		if story.body_kind != &"set":
			if seen > 0 or last >= 0:
				_rows[id] = {"seen": seen, "last_minute": last}
			continue
		var source := PackedStringArray()
		for line in story.lines:
			if not line.line_id.is_empty():
				source.append(line.line_id)
		var order := PackedStringArray()
		var taken := {}
		var saved: Variant = raw.get("order", [])
		if saved is Array:
			for item in saved:
				var line_id := WyrdSave.text_of(item, "")
				if not source.has(line_id) or taken.has(line_id):
					continue
				order.append(line_id)
				taken[line_id] = true
		for line_id in source:
			if taken.has(line_id):
				continue
			order.append(line_id)
			taken[line_id] = true
		if order.is_empty():
			if seen > 0 or last >= 0:
				_rows[id] = {"seen": seen, "last_minute": last}
			continue
		var cursor := _whole(raw.get("cursor", 0))
		var cycle := _whole(raw.get("cycle", 0))
		if cycle < 0:
			cycle = 0
		if cursor < 0:
			cursor = 0
		if cursor > order.size():
			cursor = order.size()
		_rows[id] = {
			"cursor": cursor,
			"cycle": cycle,
			"last_minute": last,
			"order": order,
			"seen": seen,
		}


func _line_by_id(story: WyrdStoryletDef, line_id: String) -> WyrdLineDef:
	for line in story.lines:
		if line.line_id == line_id:
			return line
	return null


func _story(id: String) -> WyrdStoryletDef:
	if _content == null:
		return null
	var found: Variant = _content.storylets.get(id, null)
	if found is WyrdStoryletDef:
		return found
	return null


func _ensure(story: WyrdStoryletDef) -> Dictionary:
	var id := story.id
	if not _rows.has(id):
		var created := {
			"cursor": 0,
			"cycle": 0,
			"last_minute": -1,
			"order": _shuffle(id, 0, story.lines),
			"seen": 0,
		}
		_rows[id] = created
		return created
	var row: Dictionary = _rows[id]
	if not (row.get("order") is PackedStringArray):
		row["cursor"] = 0
		row["cycle"] = int(row.get("cycle", 0))
		row["order"] = _shuffle(id, int(row.get("cycle", 0)), story.lines)
		if not row.has("seen"):
			row["seen"] = 0
		if not row.has("last_minute"):
			row["last_minute"] = -1
		_rows[id] = row
		return row
	var order: PackedStringArray = row["order"]
	if int(row.get("cursor", 0)) < order.size():
		return row
	var cycle := int(row.get("cycle", 0)) + 1
	row["cursor"] = 0
	row["cycle"] = cycle
	row["order"] = _shuffle(id, cycle, story.lines)
	_rows[id] = row
	return row


func _shuffle(id: String, cycle: int, lines: Array[WyrdLineDef]) -> PackedStringArray:
	var order := PackedStringArray()
	for line in lines:
		order.append(line.line_id)
	if order.size() < 2:
		return order
	var rng := WyrdRng.for_decision(_seed, STREAM, StringName(id), cycle)
	var index := order.size() - 1
	while index > 0:
		var swap_at := rng.randi_bounded(index + 1)
		var swap := order[index]
		order[index] = order[swap_at]
		order[swap_at] = swap
		index -= 1
	return order


func _export_row(row: Dictionary) -> Dictionary:
	var item := {}
	if row.get("order") is PackedStringArray:
		var order: Array = []
		var packed: PackedStringArray = row["order"]
		for line_id in packed:
			order.append(String(line_id))
		item["cursor"] = int(row.get("cursor", 0))
		item["cycle"] = int(row.get("cycle", 0))
		item["order"] = order
	var seen := int(row.get("seen", 0))
	if seen > 0:
		item["seen"] = seen
	if int(row.get("last_minute", -1)) >= 0:
		item["last_minute"] = int(row["last_minute"])
	return item


func _drawn(story: WyrdStoryletDef, line_id: String, cycle: int) -> Dictionary:
	if on_coverage.is_valid():
		on_coverage.call(story.id, line_id)
	return {
		"body": String(story.body_kind),
		"cycle": cycle,
		"id": story.id,
		"line_id": line_id,
		"scene": story.scene_id,
	}


func _whole(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0
