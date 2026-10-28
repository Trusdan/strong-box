class_name WyrdToken
extends RefCounted

## One lexer token. [member line] and [member col] are 1-based.
##
## @experimental
## [member end_col] is the column just after the token's last source character.

var kind: StringName = &""
var text: String = ""
var line: int = 1
var col: int = 1
var end_line: int = 1
var end_col: int = 1


func _init(
	token_kind: StringName = &"",
	token_text: String = "",
	token_line: int = 1,
	token_col: int = 1,
	token_end_line: int = 1,
	token_end_col: int = 1
) -> void:
	kind = token_kind
	text = token_text
	line = token_line
	col = token_col
	end_line = token_end_line
	end_col = token_end_col


func display() -> String:
	match kind:
		&"ident", &"int", &"prose", &"interp", &"error":
			return text
		&"string":
			return "\"%s\"" % text
		&"line_tag":
			return "#line:%s" % text
		&"tag":
			return "#tag:%s" % text
		&"dot":
			return "."
		&"colon":
			return ":"
		&"star":
			return "*"
		&"tilde":
			return "~"
		&"arrow":
			return "->"
		&"eq":
			return "="
		&"lparen":
			return "("
		&"rparen":
			return ")"
		&"lbrace":
			return "{"
		&"rbrace":
			return "}"
		&"lbracket":
			return "["
		&"rbracket":
			return "]"
		&"comma":
			return ","
		&"gt":
			return ">"
		&"lt":
			return "<"
		&"plus":
			return "+"
		&"minus":
			return "-"
		&"slash":
			return "/"
		&"question":
			return "?"
		&"pipe":
			return "|"
		&"indent":
			return "indent"
		&"dedent":
			return "dedent"
		&"newline":
			return "newline"
		&"eof":
			return "eof"
		_:
			return text
