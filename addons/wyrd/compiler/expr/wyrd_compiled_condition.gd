class_name WyrdCompiledCondition
extends RefCounted

## Plain-data compiled condition. No lambdas and no callables.
##
## @experimental
## [member reads] lists every fact key the condition may read, including
## short-circuit paths that a single evaluation might skip.
## [member source_span] is [code]line[/code], [code]col[/code], [code]end_line[/code], [code]end_col[/code].

var code: PackedInt32Array = PackedInt32Array()
var consts: Array = []
var reads: Array[StringName] = []
var specificity: int = 0
var uses_chance: bool = false
## [code]nearby[/code], [code]can_perceive[/code], or [code]can_reach[/code]. Not saved.
var uses_spatial: bool = false
var source_span: Dictionary = {"col": 1, "end_col": 1, "end_line": 1, "line": 1}
## Expression text for a prose interpolation. Empty on a condition. Not saved.
var source_text: String = ""


func to_data() -> Dictionary:
	var code_rows: Array = []
	for op in code:
		code_rows.append(int(op))
	var const_rows: Array = []
	for item in consts:
		const_rows.append(_const_row(item))
	var op_rows: Array = []
	for line in WyrdOpcodes.disasm(code, consts):
		op_rows.append(line)
	var read_rows: Array = []
	for read in reads:
		read_rows.append(String(read))
	return {
		"code": code_rows,
		"consts": const_rows,
		"ops": op_rows,
		"reads": read_rows,
		"source_span": source_span.duplicate(),
		"specificity": specificity,
		"uses_chance": uses_chance,
	}


func _const_row(item: Variant) -> Dictionary:
	if item is bool:
		return {"t": "bool", "v": item}
	if item is int:
		return {"t": "int", "v": item}
	if item is float:
		return {"t": "float", "v": item}
	return {"t": "name", "v": String(item)}
