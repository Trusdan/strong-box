class_name WyrdExprNode
extends RefCounted

## One condition or interpolation node. [member kind] selects the production.
##
## @experimental
## Kinds include [code]binary[/code], [code]unary[/code], [code]call[/code], [code]fact[/code],
## [code]name[/code], [code]set[/code], [code]range[/code], [code]ternary[/code], [code]if[/code],
## [code]value[/code], [code]variants[/code], [code]text[/code], and [code]prose[/code].

var kind: StringName = &""
var text: String = ""
var value: Variant = null
var type_name: StringName = &""
var a: WyrdExprNode = null
var b: WyrdExprNode = null
var c: WyrdExprNode = null
var kids: Array[WyrdExprNode] = []
var payload: Variant = null
var line: int = 1
var col: int = 1
var end_line: int = 1
var end_col: int = 1


func to_data() -> Dictionary:
	var data := {
		"col": col,
		"kind": String(kind),
		"line": line,
		"type": String(type_name),
	}
	if text != "":
		data["text"] = text
	if value is bool or value is int or value is float:
		data["value"] = value
	if a != null:
		data["a"] = a.to_data()
	if b != null:
		data["b"] = b.to_data()
	if c != null:
		data["c"] = c.to_data()
	if not kids.is_empty():
		var rows: Array = []
		for kid in kids:
			rows.append(kid.to_data())
		data["kids"] = rows
	if payload is WyrdCompiledCondition:
		data["compiled"] = (payload as WyrdCompiledCondition).to_data()
	return data
