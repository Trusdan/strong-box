class_name WyrdStageDef
extends WyrdStmtSpan

## One quest stage, or the statement body of a variant.
##
## @experimental
## [member scenes] entries are [code]id[/code], [code]with[/code], and a span.
## [member hosts] entries are [code]screen[/code], [code]fields[/code], and a span.
## [member transitions] entries are [code]target[/code], [code]when[/code], [code]expr[/code], and a span.
## [member variants] holds [WyrdVariantDef] records. The array is untyped so the
## stage and variant records can name each other.

var id: String = ""
## Old stage ids from a top-level [code]was:[/code] list, with the token position of each.
var was_ids: PackedStringArray = PackedStringArray()
var was_lines: PackedInt32Array = PackedInt32Array()
var was_cols: PackedInt32Array = PackedInt32Array()
var waits_until: WyrdCompiledCondition = null
var waits_text: String = ""
var journals: Array[WyrdLineDef] = []
var scenes: Array = []
var transitions: Array = []
var effects: Array[WyrdEffectDef] = []
var hosts: Array = []
var variants: Array = []
var handlers: Array[WyrdOnEventDef] = []
## [WyrdRegionDef] records. Untyped so a stage and a region can name each other.
var regions: Array = []

const _SLOT_CALLS: Dictionary = {"filled": true, "holder": true, "slot_state": true}


## Slots this stage references, and which of them an [code]empty[/code] or
## [code]locked_gone[/code] variant covers. [param used], [param empty_covered],
## and [param gone_covered] map a name to true. A reference is a scene
## [code]with[/code] name, a variant slot, or a [code]holder[/code],
## [code]filled[/code], or [code]slot_state[/code] call in a step or condition.
## Variant bodies and region stages count. [WyrdLinker] and [WyrdQuestRunner]
## share this walk. [code]contested[/code] does not cover empty.
static func mark_coverage(stage: WyrdStageDef, used: Dictionary, empty_covered: Dictionary, gone_covered: Dictionary) -> void:
	if stage == null:
		return
	for ref in stage.scenes:
		for entry in ref.get("with", []):
			var name := str(entry.get("name", ""))
			if not name.is_empty():
				used[name] = true
	_note_condition(stage.waits_until, used)
	for journal in stage.journals:
		_note_line(journal, used)
	for effect in stage.effects:
		_note_effect(effect, used)
	_note_whens(stage.transitions, used)
	for handler in stage.handlers:
		_note_condition(handler.where_cond, used)
		for effect in handler.effects:
			_note_effect(effect, used)
		_note_whens(handler.transitions, used)
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant == null:
			continue
		if not variant.slot.is_empty():
			used[variant.slot] = true
		if variant.state == &"empty":
			empty_covered[variant.slot] = true
		elif variant.state == &"locked_gone":
			gone_covered[variant.slot] = true
		_note_condition(variant.condition, used)
		if variant.body != null:
			mark_coverage(variant.body, used, empty_covered, gone_covered)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			mark_coverage(child, used, empty_covered, gone_covered)


static func _note_line(line_def: WyrdLineDef, used: Dictionary) -> void:
	if line_def == null:
		return
	if not line_def.variant_slot.is_empty():
		used[line_def.variant_slot] = true
	_note_condition(line_def.condition, used)
	_note_prose(line_def.prose, used)


static func _note_effect(effect: WyrdEffectDef, used: Dictionary) -> void:
	if effect == null:
		return
	_note_condition(effect.target, used)
	_note_condition(effect.value, used)
	_note_condition(effect.entity, used)
	_note_condition(effect.a, used)
	_note_condition(effect.b, used)
	for arg in effect.args:
		if arg is Dictionary:
			var compiled: Variant = (arg as Dictionary).get("compiled", null)
			if compiled is WyrdCompiledCondition:
				_note_condition(compiled, used)


static func _note_whens(rows: Array, used: Dictionary) -> void:
	for row in rows:
		if row is Dictionary:
			var when: Variant = (row as Dictionary).get("when", null)
			if when is WyrdCompiledCondition:
				_note_condition(when, used)


static func _note_prose(node: WyrdExprNode, used: Dictionary) -> void:
	if node == null:
		return
	if node.payload is WyrdCompiledCondition:
		_note_condition(node.payload, used)
	_note_prose(node.a, used)
	_note_prose(node.b, used)
	_note_prose(node.c, used)
	for kid in node.kids:
		_note_prose(kid, used)


static func _note_condition(cond: WyrdCompiledCondition, used: Dictionary) -> void:
	if cond == null:
		return
	var code := cond.code
	var consts := cond.consts
	var stack: Array[String] = []
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		if op == WyrdOpcodes.PUSH_CONST:
			stack.append(_symbol(consts, code[ip + 1]))
			ip += 2
		elif op == WyrdOpcodes.LOAD_FACT:
			stack.append("")
			ip += 2
		elif op == WyrdOpcodes.LOAD_KEY or op == WyrdOpcodes.MAKE_SET:
			_drop(stack, code[ip + 1])
			stack.append("")
			ip += 2
		elif op == WyrdOpcodes.IN_SET:
			_drop(stack, code[ip + 1] + 1)
			stack.append("")
			ip += 2
		elif op == WyrdOpcodes.CALL:
			var call_name := _symbol(consts, code[ip + 1])
			var argc := code[ip + 2]
			var args := _take_args(stack, argc)
			if argc > 0 and _SLOT_CALLS.has(call_name) and not args[0].is_empty():
				used[args[0]] = true
			stack.append("")
			ip += 3
		elif op == WyrdOpcodes.JUMP:
			ip += 2
		elif op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			_drop(stack, 1)
			ip += 2
		elif op == WyrdOpcodes.IN_RANGE:
			_drop(stack, 3)
			stack.append("")
			ip += 1
		elif op == WyrdOpcodes.NEG or op == WyrdOpcodes.NOT:
			_drop(stack, 1)
			stack.append("")
			ip += 1
		elif op >= WyrdOpcodes.ADD and op <= WyrdOpcodes.GE:
			_drop(stack, 2)
			stack.append("")
			ip += 1
		else:
			stack.append("")
			ip += 1


static func _symbol(consts: Array, index: int) -> String:
	if index < 0 or index >= consts.size():
		return ""
	var value: Variant = consts[index]
	if value is String or value is StringName:
		return String(value)
	return ""


static func _take_args(stack: Array, argc: int) -> PackedStringArray:
	var args := PackedStringArray()
	args.resize(argc)
	for i in argc:
		var at := argc - 1 - i
		if stack.is_empty():
			args[at] = ""
		else:
			args[at] = String(stack[stack.size() - 1])
			stack.resize(stack.size() - 1)
	return args


static func _drop(stack: Array, count: int) -> void:
	var left := stack.size() - count
	if left < 0:
		left = 0
	stack.resize(left)
