class_name WyrdExprParser
extends RefCounted

## Recursive-descent parser for one expression.
##
## @experimental
## Precedence, loosest first: [code]?:[/code], [code]or[/code], [code]and[/code], [code]not[/code],
## comparisons and [code]in[/code], [code]+ -[/code], [code]* /[/code], unary [code]-[/code].
## [code]fact(...)[/code] is a fact reference. [code][a, b][/code] is a set. [code]6..18[/code] is a range.

var _tokens: Array[WyrdToken] = []
var _index: int = 0
var _diagnostics: WyrdDiagnostics
var _path: String = ""


func parse(tokens: Array[WyrdToken], diagnostics: WyrdDiagnostics, source_path: String) -> WyrdExprNode:
	_tokens = tokens
	_index = 0
	_diagnostics = diagnostics
	_path = source_path
	var node := _ternary()
	if _tok().kind != &"eof":
		_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % _tok().display(), _tok())
	return node


func _ternary() -> WyrdExprNode:
	var cond := _or()
	if _tok().kind != &"?":
		return cond
	var mark := _tok()
	_advance()
	var yes := _ternary()
	if not _eat(&":"):
		_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected \":\" in a ternary", _tok())
		return cond
	var no := _ternary()
	var node := _node(&"ternary", mark)
	node.a = cond
	node.b = yes
	node.c = no
	node.line = cond.line
	node.col = cond.col
	node.end_line = no.end_line
	node.end_col = no.end_col
	return node


func _or() -> WyrdExprNode:
	var left := _and()
	while _tok().kind == &"or":
		var op := _tok()
		_advance()
		left = _binary(op, left, _and())
	return left


func _and() -> WyrdExprNode:
	var left := _not()
	while _tok().kind == &"and":
		var op := _tok()
		_advance()
		left = _binary(op, left, _not())
	return left


func _not() -> WyrdExprNode:
	if _tok().kind != &"not":
		return _cmp()
	var op := _tok()
	_advance()
	var node := _node(&"unary", op)
	node.text = "not"
	node.a = _not()
	_finish(node, node.a)
	return node


func _cmp() -> WyrdExprNode:
	var left := _add()
	var op := _tok()
	if (
		op.kind == &"=="
		or op.kind == &"!="
		or op.kind == &"<"
		or op.kind == &"<="
		or op.kind == &">"
		or op.kind == &">="
		or op.kind == &"in"
	):
		_advance()
		return _binary(op, left, _add())
	return left


func _add() -> WyrdExprNode:
	var left := _mul()
	while _tok().kind == &"+" or _tok().kind == &"-":
		var op := _tok()
		_advance()
		left = _binary(op, left, _mul())
	return left


func _mul() -> WyrdExprNode:
	var left := _unary()
	while _tok().kind == &"*" or _tok().kind == &"/":
		var op := _tok()
		_advance()
		left = _binary(op, left, _unary())
	return left


func _unary() -> WyrdExprNode:
	if _tok().kind != &"-":
		return _primary()
	var op := _tok()
	_advance()
	var node := _node(&"unary", op)
	node.text = "-"
	node.a = _unary()
	_finish(node, node.a)
	return node


func _primary() -> WyrdExprNode:
	var left := _atom()
	if not _eat(&".."):
		return left
	var right := _atom()
	var node := WyrdExprNode.new()
	node.kind = &"range"
	node.a = left
	node.b = right
	node.line = left.line
	node.col = left.col
	node.end_line = right.end_line
	node.end_col = right.end_col
	return node


func _atom() -> WyrdExprNode:
	var token := _tok()
	if token.kind == &"(":
		_advance()
		if _tok().kind == &")":
			_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected expression", token)
			_advance()
			return _error_at(token)
		var inner := _ternary()
		if _eat(&")"):
			inner.end_line = _prev().end_line
			inner.end_col = _prev().end_col
		else:
			_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % _tok().display(), _tok())
		return inner
	if token.kind == &"[":
		return _set_literal()
	if token.kind == &"int" or token.kind == &"float":
		var number := _node(token.kind, token)
		number.value = int(token.text) if token.kind == &"int" else float(token.text)
		_advance()
		return number
	if token.kind == &"unit":
		var unit := _node(&"unit", token)
		_advance()
		return unit
	if token.kind == &"true" or token.kind == &"false":
		var flag := _node(&"bool", token)
		flag.value = token.kind == &"true"
		_advance()
		return flag
	if token.kind == &"ident":
		return _ident_expr()
	if token.kind == &"error":
		_advance()
		return _error_at(token)
	if token.kind == &"eof":
		_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected expression", token)
		return _error_at(token)
	_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % token.display(), token)
	_advance()
	return _error_at(token)


func _ident_expr() -> WyrdExprNode:
	var first := _tok()
	_advance()
	if first.text == "fact" and _tok().kind == &"(":
		return _fact(first)
	if _tok().kind == &"(":
		return _postfix(_call(first))
	var path := _node(&"path", first)
	path.kids.append(_seg(first))
	while _eat(&"."):
		if _eat(&"{"):
			var expr := _ternary()
			if _eat(&"}"):
				path.end_line = _prev().end_line
				path.end_col = _prev().end_col
			else:
				_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected \"}\" after a key segment", _tok())
			path.kids.append(expr)
		elif _tok().kind == &"ident":
			var seg := _tok()
			_advance()
			path.kids.append(_seg(seg))
			path.end_line = seg.end_line
			path.end_col = seg.end_col
		else:
			_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected a key segment", _tok())
			break
	return path


func _fact(token: WyrdToken) -> WyrdExprNode:
	var node := _node(&"fact", token)
	_advance()
	var args := _args()
	for arg in args:
		if arg.text != "":
			_diagnostics.add(
				WyrdDiagnostic.E_EXPR_SYNTAX,
				"fact segments are positional",
				_path,
				arg.line,
				arg.col
			)
		if arg.a != null:
			node.kids.append(arg.a)
	if _eat(&")"):
		node.end_line = _prev().end_line
		node.end_col = _prev().end_col
	else:
		_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % _tok().display(), _tok())
	return node


func _call(token: WyrdToken) -> WyrdExprNode:
	var node := _node(&"call", token)
	_advance()
	node.kids = _args()
	if _eat(&")"):
		node.end_line = _prev().end_line
		node.end_col = _prev().end_col
	else:
		_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % _tok().display(), _tok())
	return node


func _args() -> Array[WyrdExprNode]:
	var args: Array[WyrdExprNode] = []
	if _tok().kind == &")" or _tok().kind == &"eof":
		return args
	var named := false
	while true:
		var arg := WyrdExprNode.new()
		arg.kind = &"arg"
		if _tok().kind == &"ident" and _lookahead() == &":":
			named = true
			var name := _tok()
			_advance()
			_advance()
			arg.text = name.text
			arg.line = name.line
			arg.col = name.col
			arg.a = _ternary()
		else:
			if named:
				_fail(
					WyrdDiagnostic.E_EXPR_ARG_ORDER,
					"positional argument follows a named argument",
					_tok()
				)
			arg.a = _ternary()
			if arg.a != null:
				arg.line = arg.a.line
				arg.col = arg.a.col
		if arg.a != null:
			arg.end_line = arg.a.end_line
			arg.end_col = arg.a.end_col
		args.append(arg)
		if not _eat(&","):
			break
		if _tok().kind == &")":
			_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \",\"", _prev())
			break
	return args


func _postfix(node: WyrdExprNode) -> WyrdExprNode:
	while _eat(&"."):
		if _tok().kind != &"ident":
			_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected a field name", _tok())
			break
		var field := _tok()
		_advance()
		var wrap := _node(&"field", field)
		wrap.a = node
		wrap.line = node.line
		wrap.col = node.col
		wrap.end_line = field.end_line
		wrap.end_col = field.end_col
		node = wrap
	return node


func _set_literal() -> WyrdExprNode:
	var open := _tok()
	_advance()
	var node := _node(&"set", open)
	if _tok().kind == &"]":
		_fail(WyrdDiagnostic.E_EXPR_SYNTAX, "expected expression", _tok())
	else:
		while _tok().kind != &"]" and _tok().kind != &"eof":
			node.kids.append(_ternary())
			if not _eat(&","):
				break
	if _eat(&"]"):
		node.end_line = _prev().end_line
		node.end_col = _prev().end_col
	else:
		_fail(WyrdDiagnostic.E_EXPR_UNEXPECTED, "unexpected token \"%s\"" % _tok().display(), _tok())
	return node


func _binary(op: WyrdToken, left: WyrdExprNode, right: WyrdExprNode) -> WyrdExprNode:
	var node := _node(&"binary", op)
	node.a = left
	node.b = right
	node.line = left.line
	node.col = left.col
	node.end_line = right.end_line
	node.end_col = right.end_col
	return node


func _seg(token: WyrdToken) -> WyrdExprNode:
	var node := _node(&"name", token)
	return node


func _node(kind: StringName, token: WyrdToken) -> WyrdExprNode:
	var node := WyrdExprNode.new()
	node.kind = kind
	node.text = token.text
	node.line = token.line
	node.col = token.col
	node.end_line = token.end_line
	node.end_col = token.end_col
	return node


func _error_at(token: WyrdToken) -> WyrdExprNode:
	var node := _node(&"error", token)
	node.type_name = &"error"
	return node


func _finish(node: WyrdExprNode, child: WyrdExprNode) -> void:
	if child == null:
		return
	node.end_line = child.end_line
	node.end_col = child.end_col


func _fail(code: StringName, message: String, token: WyrdToken) -> void:
	_diagnostics.add(code, message, _path, token.line, token.col)


func _eat(kind: StringName) -> bool:
	if _tok().kind != kind:
		return false
	_advance()
	return true


func _lookahead() -> StringName:
	if _index + 1 >= _tokens.size():
		return &"eof"
	return _tokens[_index + 1].kind


func _tok() -> WyrdToken:
	if _index >= _tokens.size():
		return _tokens[_tokens.size() - 1]
	return _tokens[_index]


func _prev() -> WyrdToken:
	return _tokens[maxi(_index - 1, 0)]


func _advance() -> void:
	if _index < _tokens.size():
		_index += 1
