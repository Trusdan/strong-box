class_name WyrdExprLexer
extends RefCounted

## Lexer for one condition or interpolation expression.
##
## @experimental
## [param base_line] and [param base_col] are the source position of [param text]'s first character.
## A number glued to [code]m[/code], [code]h[/code], or [code]d[/code] is one [code]unit[/code] token.

var _text: String = ""
var _path: String = ""
var _diagnostics: WyrdDiagnostics
var _line: int = 1
var _col: int = 1
var _index: int = 0
var _tokens: Array[WyrdToken] = []


func tokenize(
	text: String,
	source_path: String,
	base_line: int,
	base_col: int,
	diagnostics: WyrdDiagnostics
) -> Array[WyrdToken]:
	_text = text
	_path = source_path
	_diagnostics = diagnostics
	_line = maxi(base_line, 1)
	_col = maxi(base_col, 1)
	_index = 0
	_tokens = []
	while _index < _text.length():
		var ch := _text[_index]
		if ch == " " or ch == "\t" or ch == "\r":
			_bump()
			continue
		if ch == "\n":
			_index += 1
			_line += 1
			_col = 1
			continue
		if ch == "\"":
			_string()
			continue
		if _is_digit(ch):
			_number()
			continue
		if _is_ident_start(ch):
			_ident()
			continue
		if ch == "$":
			_binding()
			continue
		if _two():
			continue
		_punct(ch)
	_tokens.append(WyrdToken.new(&"eof", "", _line, _col, _line, _col))
	return _tokens


func _number() -> void:
	var start_line := _line
	var start_col := _col
	var start := _index
	while _index < _text.length() and _is_digit(_text[_index]):
		_bump()
	var is_float := false
	if (
		_index + 1 < _text.length()
		and _text[_index] == "."
		and _is_digit(_text[_index + 1])
	):
		is_float = true
		_bump()
		while _index < _text.length() and _is_digit(_text[_index]):
			_bump()
	if _index < _text.length() and _is_ident_start(_text[_index]):
		var id_at := _index
		var id_col := _col
		while _index < _text.length() and _is_ident_cont(_text[_index]):
			_bump()
		var suffix := _text.substr(id_at, _index - id_at)
		if suffix == "m" or suffix == "h" or suffix == "d":
			var lexeme := _text.substr(start, _index - start)
			_tokens.append(WyrdToken.new(&"unit", lexeme, start_line, start_col, _line, _col))
			return
		_index = id_at
		_col = id_col
	var number := _text.substr(start, _index - start)
	var kind: StringName = &"float" if is_float else &"int"
	_tokens.append(WyrdToken.new(kind, number, start_line, start_col, _line, _col))


func _ident() -> void:
	var start_line := _line
	var start_col := _col
	var start := _index
	_bump()
	while _index < _text.length() and _is_ident_cont(_text[_index]):
		_bump()
	var word := _text.substr(start, _index - start)
	var kind: StringName = &"ident"
	if word == "and" or word == "or" or word == "not" or word == "in" or word == "true" or word == "false":
		kind = StringName(word)
	_tokens.append(WyrdToken.new(kind, word, start_line, start_col, _line, _col))


func _binding() -> void:
	var start_line := _line
	var start_col := _col
	var start := _index
	_bump()
	if _index >= _text.length() or not _is_ident_start(_text[_index]):
		_diagnostics.add(
			WyrdDiagnostic.E_EXPR_UNEXPECTED,
			"unexpected token \"$\"",
			_path,
			start_line,
			start_col
		)
		_tokens.append(WyrdToken.new(&"error", "$", start_line, start_col, _line, _col))
		return
	while _index < _text.length() and _is_ident_cont(_text[_index]):
		_bump()
	var word := _text.substr(start, _index - start)
	_tokens.append(WyrdToken.new(&"ident", word, start_line, start_col, _line, _col))


func _string() -> void:
	var start_line := _line
	var start_col := _col
	_diagnostics.add(
		WyrdDiagnostic.E_EXPR_SYNTAX,
		"string literals are not allowed in conditions",
		_path,
		start_line,
		start_col
	)
	_bump()
	while _index < _text.length() and _text[_index] != "\"" and _text[_index] != "\n":
		if _text[_index] == "\\":
			_bump()
		if _index < _text.length() and _text[_index] != "\n":
			_bump()
	if _index < _text.length() and _text[_index] == "\"":
		_bump()
	_tokens.append(WyrdToken.new(&"error", "\"", start_line, start_col, _line, _col))


func _two() -> bool:
	if _index + 1 >= _text.length():
		return false
	var pair := _text.substr(_index, 2)
	if pair != "==" and pair != "!=" and pair != "<=" and pair != ">=" and pair != "..":
		return false
	var start_line := _line
	var start_col := _col
	_bump()
	_bump()
	_tokens.append(WyrdToken.new(StringName(pair), pair, start_line, start_col, _line, _col))
	return true


func _punct(ch: String) -> void:
	var start_line := _line
	var start_col := _col
	if "()[]{},.?:+-*/<>|".contains(ch):
		_bump()
		_tokens.append(WyrdToken.new(StringName(ch), ch, start_line, start_col, _line, _col))
		return
	_diagnostics.add(
		WyrdDiagnostic.E_EXPR_UNEXPECTED,
		"unexpected token \"%s\"" % ch,
		_path,
		start_line,
		start_col
	)
	_bump()
	_tokens.append(WyrdToken.new(&"error", ch, start_line, start_col, _line, _col))


func _bump() -> void:
	_index += 1
	_col += 1


func _is_ident_start(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


func _is_ident_cont(ch: String) -> bool:
	return _is_ident_start(ch) or _is_digit(ch)


func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"
