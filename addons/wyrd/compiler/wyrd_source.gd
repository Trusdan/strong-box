class_name WyrdSource
extends RefCounted

## One `.wyrd` file: its path, its text, and offset-to-line mapping.
##
## @experimental
## Columns count Unicode code points, starting at 1. Carriage returns are normalized to `\n`.

var path: String = ""
var text: String = ""
var _line_starts: PackedInt32Array = PackedInt32Array()


func _init(source_path: String, source_text: String) -> void:
	path = source_path
	text = _normalize(source_text)
	_index_lines()


static func load_file(source_path: String) -> WyrdSource:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return null
	return WyrdSource.new(source_path, file.get_as_text())


func line_at(offset: int) -> int:
	var clamped := clampi(offset, 0, text.length())
	var low := 0
	var high := _line_starts.size() - 1
	while low < high:
		var mid := (low + high + 1) >> 1
		if _line_starts[mid] <= clamped:
			low = mid
		else:
			high = mid - 1
	return low + 1


func column_at(offset: int) -> int:
	var clamped := clampi(offset, 0, text.length())
	var line := line_at(clamped)
	return clamped - _line_starts[line - 1] + 1


func _normalize(raw: String) -> String:
	var body := raw.replace("\r\n", "\n").replace("\r", "\n")
	if body.begins_with("\uFEFF"):
		body = body.substr(1)
	return body


func _index_lines() -> void:
	_line_starts = PackedInt32Array()
	_line_starts.append(0)
	for i in text.length():
		if text[i] == "\n":
			_line_starts.append(i + 1)
