class_name WyrdDiagnostics
extends RefCounted

## Collects compiler diagnostics in source order.
##

## Diagnostics in the order they were added, until sort_items runs.
var items: Array[WyrdDiagnostic] = []


## Appends one diagnostic. The line and column are at least 1.
func add(
	code: StringName,
	message: String,
	source_path: String,
	line: int,
	col: int,
	severity: StringName = WyrdDiagnostic.SEVERITY_ERROR
) -> void:
	items.append(WyrdDiagnostic.new(severity, code, message, source_path, maxi(line, 1), maxi(col, 1)))


## True when any item is an error.
func has_errors() -> bool:
	return _has(WyrdDiagnostic.SEVERITY_ERROR)


## True when any item is a warning.
func has_warnings() -> bool:
	return _has(WyrdDiagnostic.SEVERITY_WARNING)


## Stable order: file, line, column, code, then the order diagnostics were added.
func sort_items() -> void:
	var rows: Array = []
	for i in items.size():
		rows.append({"i": i, "item": items[i]})
	rows.sort_custom(_less_row)
	items.clear()
	for row in rows:
		items.append(row["item"])


func _has(severity: StringName) -> bool:
	for item in items:
		if item.severity == severity:
			return true
	return false


static func _less_row(a: Dictionary, b: Dictionary) -> bool:
	var left: WyrdDiagnostic = a["item"]
	var right: WyrdDiagnostic = b["item"]
	if left.path != right.path:
		return left.path < right.path
	if left.line != right.line:
		return left.line < right.line
	if left.col != right.col:
		return left.col < right.col
	if left.code != right.code:
		return String(left.code) < String(right.code)
	return int(a["i"]) < int(b["i"])


## One formatted line per item, ending in a newline. Empty when there are no items.
func format() -> String:
	if items.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for item in items:
		lines.append(item.format_line())
	return "\n".join(lines) + "\n"
