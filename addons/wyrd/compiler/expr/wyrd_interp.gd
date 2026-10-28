class_name WyrdInterp
extends RefCounted

## Turns a prose line's raw interpolation spans into a small tree.
##
## @experimental
## [code]{expr}[/code] is a value. [code]{if}...{else}...{end}[/code] is a conditional
## fragment and may nest. [code]{holder(name)|variants}[/code] marks a holder
## switch. The runtime picks a variant line, or the name-free line.
## [code]else[/code] and [code]end[/code] are reserved only as whole spans.

var _tokens: Array[WyrdToken] = []
var _schema: WyrdFactSchema
var _diagnostics: WyrdDiagnostics
var _path: String = ""
var _context: StringName = WyrdCondition.CONTEXT_STORYLET
var _minutes_per_day: int = WyrdCondition.MINUTES_PER_DAY
var _signatures: WyrdSignatures


func compile_line(
	tokens: Array[WyrdToken],
	schema: WyrdFactSchema,
	diagnostics: WyrdDiagnostics,
	source_path: String,
	context: StringName = WyrdCondition.CONTEXT_STORYLET,
	minutes_per_day: int = WyrdCondition.MINUTES_PER_DAY,
	signatures: WyrdSignatures = null
) -> WyrdExprNode:
	_tokens = tokens
	_schema = schema
	_diagnostics = diagnostics
	_path = source_path
	_context = context
	_minutes_per_day = minutes_per_day
	_signatures = signatures if signatures != null else WyrdSignatures.new()
	var root := WyrdExprNode.new()
	root.kind = &"prose"
	var index := 0
	while index < _tokens.size():
		var parsed := _parts(index)
		var nodes: Array = parsed["nodes"]
		for child in nodes:
			root.kids.append(child)
		var closer := String(parsed["closer"])
		if closer == "":
			break
		var token: WyrdToken = _tokens[int(parsed["index"])]
		_diagnostics.add(
			WyrdDiagnostic.E_INTERP_UNBALANCED,
			"unexpected {%s}" % closer,
			_path,
			token.line,
			token.col
		)
		index = int(parsed["index"]) + 1
	if not root.kids.is_empty():
		root.line = root.kids[0].line
		root.col = root.kids[0].col
		root.end_line = root.kids[root.kids.size() - 1].end_line
		root.end_col = root.kids[root.kids.size() - 1].end_col
	return root


func _parts(start: int) -> Dictionary:
	var nodes: Array[WyrdExprNode] = []
	var index := start
	while index < _tokens.size():
		var token := _tokens[index]
		if token.kind == &"interp":
			var body := token.text.strip_edges()
			if body == "else" or body == "end":
				return {"closer": body, "index": index, "nodes": nodes}
			if body == "if" or body.begins_with("if "):
				var built := _conditional(index)
				nodes.append(built["node"])
				index = int(built["index"])
				continue
			if _variant_at(token.text) >= 0:
				nodes.append(_variants(token))
				index += 1
				continue
			nodes.append(_value(token))
			index += 1
			continue
		if token.kind == &"prose":
			nodes.append(_text(token))
			index += 1
			continue
		index += 1
	return {"closer": "", "index": index, "nodes": nodes}


func _conditional(index: int) -> Dictionary:
	var token := _tokens[index]
	var cond := _slice_after_if(token)
	var compiled := _compile(cond["text"], cond["line"], cond["col"], true)
	var node := WyrdExprNode.new()
	node.kind = &"if"
	node.line = token.line
	node.col = token.col
	node.end_line = token.end_line
	node.end_col = token.end_col
	node.a = ast_of(compiled)
	node.payload = compiled["value"]
	var then_parts := _parts(index + 1)
	node.b = _prose(then_parts["nodes"])
	var cursor := int(then_parts["index"])
	var closer := String(then_parts["closer"])
	if closer == "else":
		var else_parts := _parts(cursor + 1)
		node.c = _prose(else_parts["nodes"])
		cursor = int(else_parts["index"])
		closer = String(else_parts["closer"])
	if closer == "end":
		cursor += 1
		if cursor - 1 < _tokens.size():
			node.end_line = _tokens[cursor - 1].end_line
			node.end_col = _tokens[cursor - 1].end_col
	else:
		_diagnostics.add(
			WyrdDiagnostic.E_INTERP_UNBALANCED,
			"unbalanced {if}",
			_path,
			token.line,
			token.col
		)
	return {"index": cursor, "node": node}


func _value(token: WyrdToken) -> WyrdExprNode:
	var sliced := _trimmed(token.text)
	var compiled := _compile(sliced["text"], token.line, token.col + 1 + int(sliced["at"]), false)
	var node := WyrdExprNode.new()
	node.kind = &"value"
	node.line = token.line
	node.col = token.col
	node.end_line = token.end_line
	node.end_col = token.end_col
	node.a = ast_of(compiled)
	node.payload = compiled["value"]
	return node


func _variants(token: WyrdToken) -> WyrdExprNode:
	var at := _variant_at(token.text)
	var raw := token.text.substr(0, at)
	var sliced := _trimmed(raw)
	var compiled := _compile(sliced["text"], token.line, token.col + 1 + int(sliced["at"]), false)
	var node := WyrdExprNode.new()
	node.kind = &"variants"
	node.text = "variants"
	node.line = token.line
	node.col = token.col
	node.end_line = token.end_line
	node.end_col = token.end_col
	node.a = ast_of(compiled)
	node.payload = compiled["value"]
	return node


func _text(token: WyrdToken) -> WyrdExprNode:
	var node := WyrdExprNode.new()
	node.kind = &"text"
	node.text = token.text
	node.line = token.line
	node.col = token.col
	node.end_line = token.end_line
	node.end_col = token.end_col
	return node


func _prose(nodes: Array) -> WyrdExprNode:
	var node := WyrdExprNode.new()
	node.kind = &"prose"
	for child in nodes:
		node.kids.append(child)
	if not node.kids.is_empty():
		node.line = node.kids[0].line
		node.col = node.kids[0].col
		node.end_line = node.kids[node.kids.size() - 1].end_line
		node.end_col = node.kids[node.kids.size() - 1].end_col
	return node


func _compile(text: String, line: int, col: int, require_bool: bool) -> Dictionary:
	var compiler := WyrdCondition.new()
	var compiled := compiler.compile(
		text,
		_schema,
		_diagnostics,
		_path,
		line,
		col,
		_context,
		_minutes_per_day,
		_signatures,
		require_bool
	)
	compiled.source_text = text.strip_edges()
	return {"ast": compiler.ast, "value": compiled}


func ast_of(compiled: Dictionary) -> WyrdExprNode:
	return compiled["ast"]


func _slice_after_if(token: WyrdToken) -> Dictionary:
	var raw := token.text
	var index := 0
	while index < raw.length() and (raw[index] == " " or raw[index] == "\t"):
		index += 1
	if raw.substr(index, 3) == "if " or raw.substr(index) == "if":
		index += 2
	if index < raw.length() and raw[index] == " ":
		index += 1
	while index < raw.length() and raw[index] == " ":
		index += 1
	return {"at": index, "col": token.col + 1 + index, "line": token.line, "text": raw.substr(index).strip_edges()}


func _trimmed(raw: String) -> Dictionary:
	var index := 0
	while index < raw.length() and (raw[index] == " " or raw[index] == "\t"):
		index += 1
	return {"at": index, "text": raw.substr(index).strip_edges()}


func _variant_at(raw: String) -> int:
	var at := raw.find("|variants")
	if at < 0:
		return -1
	if raw.substr(at).strip_edges() != "|variants":
		return -1
	return at
