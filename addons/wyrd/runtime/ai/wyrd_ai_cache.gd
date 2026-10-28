class_name WyrdAICache
extends RefCounted

## Validated AI text, oldest inserted first. Pure: no runtime.
##
## @experimental
## [method insert] keeps at most [param cap] entries and evicts the oldest.
## A cap of 0 or less stores nothing.


var _rows: Dictionary = {}


## Inserts [param text] under [param key] and returns the evicted keys, oldest first.
## Re-inserting a key replaces its text and moves it to the newest position.
func insert(key: String, text: String, cap: int) -> PackedStringArray:
	var evicted := PackedStringArray()
	if cap <= 0:
		return evicted
	if _rows.has(key):
		_rows.erase(key)
	_rows[key] = text
	while _rows.size() > cap:
		var oldest := String(_rows.keys()[0])
		_rows.erase(oldest)
		evicted.append(oldest)
	return evicted


func text_for(key: String) -> String:
	if not _rows.has(key):
		return ""
	return String(_rows[key])


func has(key: String) -> bool:
	return _rows.has(key)


func size() -> int:
	return _rows.size()


## Oldest first.
func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _rows.keys():
		out.append(String(key))
	return out


func clear() -> void:
	_rows.clear()


## Oldest first. Each row is [code]k[/code] and [code]t[/code].
func export_rows() -> Array:
	var rows: Array = []
	for key in _rows.keys():
		rows.append({"k": String(key), "t": String(_rows[key])})
	return rows


## Replaces the contents. Returns how many rows were skipped.
## A row is skipped when it is not a [Dictionary], when [code]k[/code] is not
## 16 lowercase hex digits, or when [code]t[/code] fails [method WyrdAIValidator.safe_text].
## Rows are applied oldest first, then trimmed to [param cap], keeping the newest.
func import_rows(rows: Array, cap: int) -> int:
	clear()
	var skipped := 0
	for row in rows:
		if not _row_ok(row):
			skipped += 1
			continue
		var bag: Dictionary = row
		insert(String(bag["k"]), String(bag["t"]), cap)
	return skipped


func _row_ok(row: Variant) -> bool:
	if not (row is Dictionary):
		return false
	var bag: Dictionary = row
	var raw_key: Variant = bag.get("k", null)
	if not (raw_key is String or raw_key is StringName):
		return false
	if not _hex_key(String(raw_key)):
		return false
	var raw_text: Variant = bag.get("t", null)
	if not (raw_text is String):
		return false
	return WyrdAIValidator.safe_text(raw_text)


func _hex_key(key: String) -> bool:
	if key.length() != 16:
		return false
	for i in 16:
		var code := key.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var lower := code >= 97 and code <= 102
		if not digit and not lower:
			return false
	return not WyrdRng.parse_u64(key).is_empty()
