class_name WyrdOpcodes
extends RefCounted

## Flat instruction set for a compiled condition.
##
## @experimental
## [code]and[/code], [code]or[/code], and [code]?:[/code] are jumps, not opcodes.
## [code]LOAD_FACT[/code] loads one const key. [code]LOAD_KEY[/code] joins [code]n[/code]
## segment values already on the stack. [code]CALL[/code] is a name const then an argument count.
## [code]IN_RANGE[/code] is inclusive. [code]IN_SET[/code]'s operand is the element count.
## [code]MAKE_SET[/code]'s operand is the element count. It leaves the set on the stack.

const PUSH_CONST := 1
const PUSH_TRUE := 2
const PUSH_FALSE := 3
const PUSH_NIL := 4
const LOAD_FACT := 5
const LOAD_KEY := 6
const NEG := 7
const ADD := 8
const SUB := 9
const MUL := 10
const DIV := 11
const EQ := 12
const NE := 13
const LT := 14
const LE := 15
const GT := 16
const GE := 17
const NOT := 18
const IN_SET := 19
const IN_RANGE := 20
const CALL := 21
const JUMP := 22
const JUMP_IF_FALSE := 23
const JUMP_IF_TRUE := 24
const MAKE_SET := 25

const NAMES: PackedStringArray = [
	"",
	"PUSH_CONST",
	"PUSH_TRUE",
	"PUSH_FALSE",
	"PUSH_NIL",
	"LOAD_FACT",
	"LOAD_KEY",
	"NEG",
	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"EQ",
	"NE",
	"LT",
	"LE",
	"GT",
	"GE",
	"NOT",
	"IN_SET",
	"IN_RANGE",
	"CALL",
	"JUMP",
	"JUMP_IF_FALSE",
	"JUMP_IF_TRUE",
	"MAKE_SET",
]


static func disasm(code: PackedInt32Array, consts: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		var name := "OP%d" % op
		if op >= 0 and op < NAMES.size() and NAMES[op] != "":
			name = NAMES[op]
		var extra := ""
		var width := 1
		if op == PUSH_CONST or op == LOAD_FACT:
			extra = " " + _show(consts[code[ip + 1]])
			width = 2
		elif op == LOAD_KEY or op == IN_SET or op == MAKE_SET:
			extra = " %d" % code[ip + 1]
			width = 2
		elif op == CALL:
			extra = " %s %d" % [_show(consts[code[ip + 1]]), code[ip + 2]]
			width = 3
		elif op == JUMP or op == JUMP_IF_FALSE or op == JUMP_IF_TRUE:
			extra = " %d" % code[ip + 1]
			width = 2
		lines.append("%04d %s%s" % [ip, name, extra])
		ip += width
	return lines


static func _show(value: Variant) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % String(value)
	return str(value)
