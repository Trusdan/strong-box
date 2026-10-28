class_name WyrdRpnEval
extends RefCounted

## Stack evaluator for a [WyrdCompiledCondition].
##
## @experimental
## Seed of the S2 evaluator. [param funcs] maps a function name to a [Callable]
## that receives the argument array. A missing fact makes a comparison false.
## Load-time caches, when added, are rebuilt from the saved plain data and are
## never written back. [member WyrdCompiledCondition.code] keeps the documented opcodes.

const _SI_CMP := 100
const _SI_CMP_JUMP := 101

var _stack: Array = []
var _slots: Dictionary = {}
var _plans: Dictionary = {}
## Optional one-argument fact reader. Used when [param facts] has no entry.
## Not saved. The default path is unchanged when this is unset.
var fact_reader: Callable = Callable()
## Key of the latest [code]LOAD_FACT[/code] in the current [method eval].
var last_fact_key: String = ""


## Map fact keys to slots. Derived plans are dropped and rebuilt. Not saved.
func bind_facts(keys: PackedStringArray) -> void:
	_slots.clear()
	_plans.clear()
	for i in keys.size():
		_slots[keys[i]] = i


## Build a slot plan from [param compiled]. Common compare pairs become
## evaluator-only superinstructions. [member WyrdCompiledCondition.code] is unchanged.
func prepare(compiled: WyrdCompiledCondition) -> void:
	var src := compiled.code.duplicate()
	var consts: Array = compiled.consts
	var ip := 0
	while ip < src.size():
		if src[ip] == WyrdOpcodes.LOAD_FACT:
			var key := String(consts[src[ip + 1]])
			src[ip + 1] = int(_slots[key]) if _slots.has(key) else -1
		ip += _width(src[ip])
	var targets := {}
	ip = 0
	while ip < src.size():
		var op := src[ip]
		if op == WyrdOpcodes.JUMP or op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			targets[src[ip + 1]] = true
		ip += _width(op)
	var out: Array[int] = []
	var at := {}
	var patches: Array[int] = []
	ip = 0
	while ip < src.size():
		at[ip] = out.size()
		if _fuse_jump(src, ip, targets):
			out.append(_SI_CMP_JUMP)
			out.append(src[ip + 1])
			out.append(src[ip + 3])
			out.append(src[ip + 4])
			patches.append(out.size())
			patches.append(src[ip + 6])
			out.append(0)
			ip += 7
			continue
		if _fuse_cmp(src, ip, targets):
			out.append(_SI_CMP)
			out.append(src[ip + 1])
			out.append(src[ip + 3])
			out.append(src[ip + 4])
			ip += 5
			continue
		var op := src[ip]
		var width := _width(op)
		for n in width:
			out.append(src[ip + n])
		if op == WyrdOpcodes.JUMP or op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			patches.append(out.size() - 1)
			patches.append(src[ip + 1])
		ip += width
	at[src.size()] = out.size()
	var plan := PackedInt32Array()
	plan.resize(out.size())
	for i in out.size():
		plan[i] = out[i]
	var patch_at := 0
	while patch_at < patches.size():
		plan[patches[patch_at]] = int(at[patches[patch_at + 1]])
		patch_at += 2
	_plans[compiled.get_instance_id()] = plan


func eval(compiled: WyrdCompiledCondition, facts: Dictionary, funcs: Dictionary = {}) -> Variant:
	_stack.clear()
	last_fact_key = ""
	return _walk(compiled.code, compiled.consts, facts, PackedInt32Array(), false, funcs)


## Evaluate a plan from [method prepare]. [param values] is indexed by slot.
## Slots hold ints. Symbols, bools, and floats stay on [method eval].
func eval_bound(compiled: WyrdCompiledCondition, values: PackedInt32Array) -> Variant:
	_stack.clear()
	var plan: PackedInt32Array = _plans[compiled.get_instance_id()]
	return _walk(plan, compiled.consts, {}, values, true, {})


func _walk(code: PackedInt32Array, consts: Array, facts: Dictionary, values: PackedInt32Array, bound: bool, funcs: Dictionary) -> Variant:
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		if op == _SI_CMP_JUMP:
			var slot := code[ip]
			var right: Variant = consts[code[ip + 1]]
			var cmp := code[ip + 2]
			var dest := code[ip + 3]
			ip += 4
			if _slot_fails(cmp, slot, values, right):
				ip = dest
		elif op == _SI_CMP:
			var slot := code[ip]
			var right: Variant = consts[code[ip + 1]]
			var cmp := code[ip + 2]
			ip += 3
			_stack.append(not _slot_fails(cmp, slot, values, right))
		elif op == WyrdOpcodes.LOAD_FACT:
			var slot := code[ip]
			ip += 1
			if bound:
				_stack.append(null if slot < 0 else values[slot])
			else:
				_stack.append(_load(facts, consts[slot]))
		elif op == WyrdOpcodes.PUSH_CONST:
			_stack.append(consts[code[ip]])
			ip += 1
		elif op == WyrdOpcodes.GE or op == WyrdOpcodes.GT or op == WyrdOpcodes.LE or op == WyrdOpcodes.LT or op == WyrdOpcodes.EQ or op == WyrdOpcodes.NE:
			var right: Variant = _pop()
			var left: Variant = _pop()
			_stack.append(_cmp(op, left, right))
		elif op == WyrdOpcodes.JUMP_IF_FALSE:
			var failed := code[ip]
			ip += 1
			if _pop() != true:
				ip = failed
		elif op == WyrdOpcodes.JUMP:
			ip = code[ip]
		elif op == WyrdOpcodes.PUSH_FALSE:
			_stack.append(false)
		elif op == WyrdOpcodes.PUSH_TRUE:
			_stack.append(true)
		elif op == WyrdOpcodes.PUSH_NIL:
			_stack.append(null)
		elif op == WyrdOpcodes.LOAD_KEY:
			_stack.append(_load_key(facts, code[ip]))
			ip += 1
		elif op == WyrdOpcodes.NEG:
			_stack.append(_neg(_pop()))
		elif op == WyrdOpcodes.ADD or op == WyrdOpcodes.SUB or op == WyrdOpcodes.MUL or op == WyrdOpcodes.DIV:
			var rhs: Variant = _pop()
			var lhs: Variant = _pop()
			_stack.append(_arith(op, lhs, rhs))
		elif op == WyrdOpcodes.NOT:
			_stack.append(_pop() != true)
		elif op == WyrdOpcodes.IN_SET:
			_stack.append(_in_set(code[ip]))
			ip += 1
		elif op == WyrdOpcodes.MAKE_SET:
			_stack.append(_make_set(code[ip]))
			ip += 1
		elif op == WyrdOpcodes.IN_RANGE:
			var hi: Variant = _pop()
			var lo: Variant = _pop()
			var needle: Variant = _pop()
			_stack.append(_in_range(needle, lo, hi))
		elif op == WyrdOpcodes.CALL:
			var fname: StringName = consts[code[ip]]
			var argc := code[ip + 1]
			ip += 2
			_stack.append(_call(fname, argc, funcs))
		elif op == WyrdOpcodes.JUMP_IF_TRUE:
			var taken := code[ip]
			ip += 1
			if _pop() == true:
				ip = taken
		else:
			return null
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]


func _fuse_jump(src: PackedInt32Array, ip: int, targets: Dictionary) -> bool:
	if ip + 6 >= src.size():
		return false
	if src[ip] != WyrdOpcodes.LOAD_FACT or src[ip + 2] != WyrdOpcodes.PUSH_CONST:
		return false
	if not _is_cmp(src[ip + 4]) or src[ip + 5] != WyrdOpcodes.JUMP_IF_FALSE:
		return false
	return not targets.has(ip + 2) and not targets.has(ip + 4) and not targets.has(ip + 5)


func _fuse_cmp(src: PackedInt32Array, ip: int, targets: Dictionary) -> bool:
	if ip + 4 >= src.size():
		return false
	if src[ip] != WyrdOpcodes.LOAD_FACT or src[ip + 2] != WyrdOpcodes.PUSH_CONST or not _is_cmp(src[ip + 4]):
		return false
	return not targets.has(ip + 2) and not targets.has(ip + 4)


func _is_cmp(op: int) -> bool:
	return op >= WyrdOpcodes.EQ and op <= WyrdOpcodes.GE


func _slot_fails(cmp: int, slot: int, values: PackedInt32Array, right: Variant) -> bool:
	if slot < 0:
		return true
	if cmp == WyrdOpcodes.GE and right is int:
		return values[slot] < right
	return not _cmp(cmp, values[slot], right)


func _width(op: int) -> int:
	if op == WyrdOpcodes.CALL:
		return 3
	if op == WyrdOpcodes.PUSH_CONST or op == WyrdOpcodes.LOAD_FACT or op == WyrdOpcodes.LOAD_KEY or op == WyrdOpcodes.IN_SET or op == WyrdOpcodes.MAKE_SET or op == WyrdOpcodes.JUMP or op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
		return 2
	return 1


func _load(facts: Dictionary, key: Variant) -> Variant:
	var text := String(key)
	last_fact_key = text
	if facts.has(text):
		return facts[text]
	if facts.has(key):
		return facts[key]
	if fact_reader.is_valid():
		return fact_reader.call(text)
	return null


func _load_key(facts: Dictionary, count: int) -> Variant:
	var parts := PackedStringArray()
	parts.resize(count)
	for i in range(count - 1, -1, -1):
		parts[i] = str(_pop())
	return _load(facts, ".".join(parts))


func _make_set(count: int) -> Array:
	var items: Array = []
	items.resize(count)
	for i in range(count - 1, -1, -1):
		items[i] = _pop()
	return items


func _in_set(count: int) -> bool:
	var items: Array = []
	items.resize(count)
	for i in range(count - 1, -1, -1):
		items[i] = _pop()
	var needle: Variant = _pop()
	for item in items:
		if _same(needle, item):
			return true
	return false


func _in_range(needle: Variant, lo: Variant, hi: Variant) -> bool:
	if needle == null or lo == null or hi == null:
		return false
	if needle is float or lo is float or hi is float:
		return float(needle) >= float(lo) and float(needle) <= float(hi)
	return needle >= lo and needle <= hi


func _call(fname: StringName, argc: int, funcs: Dictionary) -> Variant:
	var args: Array = []
	args.resize(argc)
	for i in range(argc - 1, -1, -1):
		args[i] = _pop()
	if funcs.has(fname):
		return funcs[fname].call(args)
	if funcs.has(String(fname)):
		return funcs[String(fname)].call(args)
	if String(fname) == "chance" and argc > 0 and args[0] != null:
		return float(args[0]) >= 1.0
	return false


func _arith(op: int, lhs: Variant, rhs: Variant) -> Variant:
	if lhs == null or rhs == null:
		return null
	var ints := lhs is int and rhs is int
	if op == WyrdOpcodes.DIV and ints and int(rhs) == 0:
		return 0
	if op == WyrdOpcodes.DIV and not ints and float(rhs) == 0.0:
		return 0.0
	match op:
		WyrdOpcodes.ADD:
			return lhs + rhs if ints else float(lhs) + float(rhs)
		WyrdOpcodes.SUB:
			return lhs - rhs if ints else float(lhs) - float(rhs)
		WyrdOpcodes.MUL:
			return lhs * rhs if ints else float(lhs) * float(rhs)
		_:
			return int(lhs / rhs) if ints else float(lhs) / float(rhs)


func _cmp(op: int, left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return false
	if op == WyrdOpcodes.EQ:
		return _same(left, right)
	if op == WyrdOpcodes.NE:
		return not _same(left, right)
	var a: Variant = left
	var b: Variant = right
	if (left is int or left is float) and (right is int or right is float):
		if left is float or right is float:
			a = float(left)
			b = float(right)
	match op:
		WyrdOpcodes.LT:
			return a < b
		WyrdOpcodes.LE:
			return a <= b
		WyrdOpcodes.GT:
			return a > b
		_:
			return a >= b


func _same(left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return false
	if (left is int or left is float) and (right is int or right is float):
		if left is float or right is float:
			return is_equal_approx(float(left), float(right))
		return left == right
	if left is bool or right is bool:
		return left == right
	return str(left) == str(right)


func _neg(value: Variant) -> Variant:
	if value == null:
		return null
	return -value


func _pop() -> Variant:
	if _stack.is_empty():
		return null
	return _stack.pop_back()
