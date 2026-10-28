class_name WyrdEmitter
extends RefCounted

## Emits a flat instruction array for a typed expression.
##
## @experimental
## [code]and[/code] and [code]or[/code] become conditional jumps. Both arms are still
## listed in [member WyrdCompiledCondition.reads] by the type checker.

var _code: PackedInt32Array = PackedInt32Array()
var _consts: Array = []
var _index: Dictionary = {}


func emit(root: WyrdExprNode) -> WyrdCompiledCondition:
	_code = PackedInt32Array()
	_consts = []
	_index = {}
	_emit(root)
	var compiled := WyrdCompiledCondition.new()
	compiled.code = _code
	compiled.consts = _consts
	return compiled


func _emit(node: WyrdExprNode) -> void:
	if node == null:
		_op(WyrdOpcodes.PUSH_FALSE)
		return
	match node.kind:
		&"bool":
			if bool(node.value):
				_op(WyrdOpcodes.PUSH_TRUE)
			else:
				_op(WyrdOpcodes.PUSH_FALSE)
		&"int", &"float", &"duration", &"distance":
			_const_op(node.value)
		&"name":
			_const_op(StringName(node.text))
		&"fact":
			_fact(node)
		&"unary":
			_emit(node.a)
			if node.text == "not":
				_op(WyrdOpcodes.NOT)
			else:
				_op(WyrdOpcodes.NEG)
		&"binary":
			_binary(node)
		&"ternary":
			_ternary(node)
		&"call":
			_call(node)
		&"field":
			_field(node)
		&"arg":
			_emit(node.a)
		&"omit":
			_op(WyrdOpcodes.PUSH_NIL)
		&"set":
			for kid in node.kids:
				_emit(kid)
			_op(WyrdOpcodes.MAKE_SET)
			_operand(node.kids.size())
		_:
			_op(WyrdOpcodes.PUSH_FALSE)


func _fact(node: WyrdExprNode) -> void:
	if node.kids.is_empty():
		_op(WyrdOpcodes.LOAD_FACT)
		_operand(_const(StringName(node.text)))
		return
	for kid in node.kids:
		if kid.kind == &"name":
			_const_op(StringName(kid.text))
		else:
			_emit(kid)
	_op(WyrdOpcodes.LOAD_KEY)
	_operand(node.kids.size())


func _binary(node: WyrdExprNode) -> void:
	var op := node.text
	if op == "and":
		_emit(node.a)
		var skip := _jump(WyrdOpcodes.JUMP_IF_FALSE)
		_emit(node.b)
		var done := _jump(WyrdOpcodes.JUMP)
		_patch(skip)
		_op(WyrdOpcodes.PUSH_FALSE)
		_patch(done)
		return
	if op == "or":
		_emit(node.a)
		var skip := _jump(WyrdOpcodes.JUMP_IF_TRUE)
		_emit(node.b)
		var done := _jump(WyrdOpcodes.JUMP)
		_patch(skip)
		_op(WyrdOpcodes.PUSH_TRUE)
		_patch(done)
		return
	if op == "in":
		_emit(node.a)
		if node.b.kind == &"range":
			_emit(node.b.a)
			_emit(node.b.b)
			_op(WyrdOpcodes.IN_RANGE)
		elif node.b.kind == &"set":
			for kid in node.b.kids:
				_emit(kid)
			_op(WyrdOpcodes.IN_SET)
			_operand(node.b.kids.size())
		else:
			_emit(node.b)
			_op(WyrdOpcodes.EQ)
		return
	_emit(node.a)
	_emit(node.b)
	match op:
		"==":
			_op(WyrdOpcodes.EQ)
		"!=":
			_op(WyrdOpcodes.NE)
		"<":
			_op(WyrdOpcodes.LT)
		"<=":
			_op(WyrdOpcodes.LE)
		">":
			_op(WyrdOpcodes.GT)
		">=":
			_op(WyrdOpcodes.GE)
		"+":
			_op(WyrdOpcodes.ADD)
		"-":
			_op(WyrdOpcodes.SUB)
		"*":
			_op(WyrdOpcodes.MUL)
		"/":
			_op(WyrdOpcodes.DIV)
		_:
			_op(WyrdOpcodes.EQ)


func _ternary(node: WyrdExprNode) -> void:
	_emit(node.a)
	var skip := _jump(WyrdOpcodes.JUMP_IF_FALSE)
	_emit(node.b)
	var done := _jump(WyrdOpcodes.JUMP)
	_patch(skip)
	_emit(node.c)
	_patch(done)


func _call(node: WyrdExprNode) -> void:
	var slots: Array = node.kids
	if node.payload is Array:
		slots = node.payload
	for slot in slots:
		_emit(slot)
	_op(WyrdOpcodes.CALL)
	_operand(_const(StringName(node.text)))
	_operand(slots.size())


func _field(node: WyrdExprNode) -> void:
	_emit(node.a)
	if node.text == "name":
		_op(WyrdOpcodes.CALL)
		_operand(_const(StringName("display_name")))
		_operand(1)
		return
	_const_op(StringName(node.text))
	_op(WyrdOpcodes.CALL)
	_operand(_const(StringName("attr")))
	_operand(2)


func _const_op(value: Variant) -> void:
	_op(WyrdOpcodes.PUSH_CONST)
	_operand(_const(value))


func _const(value: Variant) -> int:
	var key := ""
	if value is bool:
		key = "b:%s" % str(value)
	elif value is int:
		key = "i:%d" % int(value)
	elif value is float:
		key = "f:%s" % str(value)
	else:
		value = StringName(str(value))
		key = "n:%s" % str(value)
	if _index.has(key):
		return int(_index[key])
	var at := _consts.size()
	_consts.append(value)
	_index[key] = at
	return at


func _op(opcode: int) -> void:
	_code.append(opcode)


func _operand(value: int) -> int:
	var at := _code.size()
	_code.append(value)
	return at


func _jump(opcode: int) -> int:
	_op(opcode)
	return _operand(0)


func _patch(at: int) -> void:
	_code[at] = _code.size()
