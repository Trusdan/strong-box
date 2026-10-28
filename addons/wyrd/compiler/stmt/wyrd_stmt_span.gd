class_name WyrdStmtSpan
extends RefCounted

## Source span and fact reads shared by statement records.
##
## @experimental
## [member reads] is the union of fact keys this record and its nested records may read.

var reads: Array[StringName] = []
var line: int = 1
var col: int = 1
var end_line: int = 1
var end_col: int = 1


func take_span(node: WyrdNode) -> void:
	line = node.start_line
	col = node.start_col
	end_line = node.end_line
	end_col = node.end_col


func span_data() -> Dictionary:
	return {"col": col, "end_col": end_col, "end_line": end_line, "line": line}


func read_data() -> Array:
	var rows: Array = []
	for item in reads:
		rows.append(String(item))
	return rows


static func add_reads(into: Array[StringName], extra: Array[StringName]) -> void:
	for item in extra:
		if not into.has(item):
			into.append(item)
