class_name WyrdTypeChecker
extends RefCounted

## Type-checks one expression against a fact schema and function signatures.
##
## @experimental
## [code]int[/code] widens to [code]float[/code]. A bare name satisfies [code]symbol[/code]
## or [code]entity[/code] from the parameter that expects it. [code]m[/code] is minutes or
## metres only when that parameter expects a duration or a distance.

const _WAIT: StringName = &"wait_trigger_or_eligibility"
## Synthetic read. [method WyrdRuntime.invalidate_groups] marks this key.
const _MEMBERSHIP_READ: StringName = &"group.membership"

var schema: WyrdFactSchema
var signatures: WyrdSignatures
var diagnostics: WyrdDiagnostics
var path: String = ""
var context: StringName = &"storylet_or_choice"
var minutes_per_day: int = 1440
var reads: Array[StringName] = []
var uses_chance: bool = false
var uses_spatial: bool = false
## Wait context may name [code]nearby[/code], [code]can_perceive[/code], and
## [code]can_reach[/code] when the caller is an [code]on[/code] handler or a
## [code]waits_until[/code] that a later check ties to one.
var allow_spatial: bool = false
## Field name to type for [code]event.<field>[/code] inside an [code]on[/code] handler.
var event_fields: Dictionary = {}
## [code]event[/code] or [code]deed[/code]. Deed fields use the same table.
var binding_prefix: String = "event"
## Bare name to type. Eligibility compiles [code]candidate[/code] as an entity.
var bindings: Dictionary = {}


func check(node: WyrdExprNode, expected: StringName) -> void:
	_check(node, expected)
	if expected == WyrdSignatures.T_BOOL and node.type_name != WyrdSignatures.T_BOOL and node.type_name != &"error":
		_error(WyrdDiagnostic.E_NOT_BOOL, "condition is %s, expected bool" % node.type_name, node)


func _check(node: WyrdExprNode, expected: StringName) -> void:
	if node == null:
		return
	match node.kind:
		&"error":
			node.type_name = &"error"
		&"bool":
			node.type_name = WyrdSignatures.T_BOOL
		&"int":
			node.type_name = WyrdSignatures.T_INT
		&"float":
			node.type_name = WyrdSignatures.T_FLOAT
		&"unit":
			_unit(node, expected)
		&"unary":
			_unary(node, expected)
		&"binary":
			_binary(node)
		&"ternary":
			_ternary(node, expected)
		&"set":
			_check_set(node)
		&"range":
			_range(node)
		&"call":
			_call(node)
		&"field":
			_field(node)
		&"fact":
			_resolve(node, expected, true)
		&"path", &"name":
			_resolve(node, expected, false)
		_:
			node.type_name = &"error"


func _unit(node: WyrdExprNode, expected: StringName) -> void:
	var suffix := node.text.substr(node.text.length() - 1, 1)
	var amount := float(node.text.substr(0, node.text.length() - 1))
	if suffix == "m" and expected != WyrdSignatures.T_DURATION and expected != WyrdSignatures.T_DISTANCE:
		_error(WyrdDiagnostic.E_EXPR_UNIT, "unit \"m\" needs a duration or distance parameter", node)
		node.type_name = &"error"
		return
	if suffix == "m" and expected == WyrdSignatures.T_DISTANCE:
		node.kind = &"distance"
		node.type_name = WyrdSignatures.T_DISTANCE
		node.value = amount
		return
	var minutes := amount
	if suffix == "h":
		minutes = amount * 60.0
	elif suffix == "d":
		minutes = amount * float(minutes_per_day)
	node.kind = &"duration"
	node.type_name = WyrdSignatures.T_DURATION
	if is_equal_approx(minutes, floor(minutes)):
		node.value = int(round(minutes))
	else:
		node.value = minutes


func _unary(node: WyrdExprNode, expected: StringName) -> void:
	if node.text == "not":
		_check(node.a, WyrdSignatures.T_BOOL)
		node.type_name = WyrdSignatures.T_BOOL
		if node.a.type_name != WyrdSignatures.T_BOOL and node.a.type_name != &"error":
			_error(WyrdDiagnostic.E_OP_TYPE, "operator \"not\" does not accept %s" % node.a.type_name, node)
		return
	_check(node.a, expected)
	node.type_name = node.a.type_name
	if node.type_name == &"error":
		return
	if not _numeric(node.type_name) and node.type_name != WyrdSignatures.T_DURATION and node.type_name != WyrdSignatures.T_DISTANCE:
		node.type_name = &"error"
		_error(WyrdDiagnostic.E_OP_TYPE, "operator \"-\" does not accept %s" % node.a.type_name, node)


func _binary(node: WyrdExprNode) -> void:
	var op := node.text
	if op == "and" or op == "or":
		_check(node.a, WyrdSignatures.T_BOOL)
		_check(node.b, WyrdSignatures.T_BOOL)
		node.type_name = WyrdSignatures.T_BOOL
		if _bad_bool(node.a) or _bad_bool(node.b):
			_op2(node)
		return
	if op == "in":
		_check_in(node)
		return
	if op == "==" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=":
		_check_cmp(node, op != "==" and op != "!=")
		return
	_check(node.a, &"")
	_check(node.b, &"")
	if node.a.type_name == &"error" or node.b.type_name == &"error":
		node.type_name = &"error"
		return
	if not _numeric(node.a.type_name) or not _numeric(node.b.type_name):
		node.type_name = &"error"
		_op2(node)
		return
	var widened := node.a.type_name == WyrdSignatures.T_FLOAT or node.b.type_name == WyrdSignatures.T_FLOAT
	if op == "/":
		node.type_name = WyrdSignatures.T_FLOAT if widened else WyrdSignatures.T_INT
	else:
		node.type_name = WyrdSignatures.T_FLOAT if widened else WyrdSignatures.T_INT


func _check_cmp(node: WyrdExprNode, ordered: bool) -> void:
	_as_belief_value(node.a)
	_as_belief_value(node.b)
	node.type_name = WyrdSignatures.T_BOOL
	var left_t := _infer(node.a)
	var right_t := _infer(node.b)
	if left_t == &"name" and right_t != &"name" and right_t != &"error":
		_check(node.b, &"")
		_check(node.a, _name_expect(node.b.type_name))
	elif right_t == &"name" and left_t != &"name" and left_t != &"error":
		_check(node.a, &"")
		_check(node.b, _name_expect(node.a.type_name))
	elif _binding_type(node.a) == WyrdSignatures.T_ENTITY and right_t == &"name":
		# deed.target is not a fact, so both sides infer as a name. Check the
		# field first, then the bare name as that entity.
		_check(node.a, &"")
		_check(node.b, _name_expect(node.a.type_name))
	elif _binding_type(node.b) == WyrdSignatures.T_ENTITY and left_t == &"name":
		_check(node.b, &"")
		_check(node.a, _name_expect(node.b.type_name))
	else:
		_check(node.a, &"")
		_check(node.b, &"")
	if node.a.type_name == &"error" or node.b.type_name == &"error":
		return
	if _cmp_ok(node.a.type_name, node.b.type_name, ordered):
		return
	_op2(node)


func _check_in(node: WyrdExprNode) -> void:
	_as_belief_value(node.a)
	node.type_name = WyrdSignatures.T_BOOL
	var right := node.b
	if right.kind == &"range":
		_check(right.a, &"")
		_check(right.b, &"")
		right.type_name = &"range"
		if right.a.type_name == &"error" or right.b.type_name == &"error":
			return
		if not _numeric(right.a.type_name) or not _numeric(right.b.type_name):
			_op2(node)
			return
		var elem := WyrdSignatures.T_FLOAT if right.a.type_name == WyrdSignatures.T_FLOAT or right.b.type_name == WyrdSignatures.T_FLOAT else WyrdSignatures.T_INT
		_check(node.a, elem)
		if node.a.type_name != &"error" and not _numeric(node.a.type_name):
			_op2(node)
		return
	if right.kind == &"set":
		var left_t := _infer(node.a)
		var elem := WyrdSignatures.T_SYMBOL
		if left_t != &"name" and left_t != &"error":
			_check(node.a, &"")
			elem = node.a.type_name
			var want := _name_expect(elem)
			_check_set(right, want if want != &"" else elem)
		else:
			_check_set(right, &"")
			if not right.kids.is_empty():
				elem = right.kids[0].type_name
			_check(node.a, elem)
		if node.a.type_name != &"error" and right.type_name != &"error" and not _fits(node.a.type_name, elem):
			_op2(node)
		return
	_check(right, &"")
	_check(node.a, &"")
	if node.a.type_name != &"error" and right.type_name != &"error":
		_op2(node)


func _check_set(node: WyrdExprNode, expected: StringName = &"") -> void:
	node.type_name = WyrdSignatures.T_SET
	if node.kids.is_empty():
		return
	var elem := expected
	if elem == &"":
		_check(node.kids[0], &"")
		elem = node.kids[0].type_name
		if elem == &"name":
			elem = WyrdSignatures.T_SYMBOL
			node.kids[0].type_name = WyrdSignatures.T_SYMBOL
	else:
		_check(node.kids[0], elem)
	for i in range(1, node.kids.size()):
		_check(node.kids[i], elem)
		if not _fits(node.kids[i].type_name, elem):
			_error(
				WyrdDiagnostic.E_OP_TYPE,
				"set element is %s, expected %s" % [node.kids[i].type_name, elem],
				node.kids[i]
			)


func _range(node: WyrdExprNode) -> void:
	_check(node.a, &"")
	_check(node.b, &"")
	node.type_name = &"range"


func _ternary(node: WyrdExprNode, expected: StringName) -> void:
	_check(node.a, WyrdSignatures.T_BOOL)
	if node.a.type_name != WyrdSignatures.T_BOOL and node.a.type_name != &"error":
		_error(WyrdDiagnostic.E_OP_TYPE, "operator \"?:\" does not accept %s" % node.a.type_name, node.a)
	_check(node.b, expected)
	var other := expected if expected != &"" else node.b.type_name
	_check(node.c, other)
	if node.b.type_name == &"error" or node.c.type_name == &"error":
		node.type_name = &"error"
		return
	if node.b.type_name == node.c.type_name:
		node.type_name = node.b.type_name
	elif _numeric(node.b.type_name) and _numeric(node.c.type_name):
		node.type_name = WyrdSignatures.T_FLOAT if node.b.type_name == WyrdSignatures.T_FLOAT or node.c.type_name == WyrdSignatures.T_FLOAT else WyrdSignatures.T_INT
	else:
		node.type_name = &"error"
		_error(
			WyrdDiagnostic.E_OP_TYPE,
			"operator \"?:\" does not accept %s and %s" % [node.b.type_name, node.c.type_name],
			node
		)


func _call(node: WyrdExprNode) -> void:
	if node.text == "known":
		_error(WyrdDiagnostic.E_KNOWN_REMOVED, "known was removed in 1.0; use knows(agent, key)", node)
		node.type_name = &"error"
		for arg in node.kids:
			if arg.a != null:
				_check(arg.a, &"")
		return
	var sig := signatures.signature(StringName(node.text))
	if sig.is_empty():
		_error(WyrdDiagnostic.E_UNKNOWN_FUNCTION, "unknown function \"%s\"" % node.text, node)
		node.type_name = &"error"
		for arg in node.kids:
			if arg.a != null:
				_check(arg.a, &"")
		return
	if node.text == "chance":
		uses_chance = true
		if context == _WAIT:
			_error(
				WyrdDiagnostic.E_CHANCE_CONTEXT,
				"chance is not allowed in a wait, trigger, or eligibility condition",
				node
			)
	if node.text == "nearby" or node.text == "can_perceive" or node.text == "can_reach":
		uses_spatial = true
		if context == _WAIT and not allow_spatial:
			_error(
				WyrdDiagnostic.E_SPATIAL_CONTEXT,
				"%s is not allowed in a wait, trigger, or eligibility condition" % node.text,
				node
			)
	var params: Array = sig["params"]
	var bound: Array = []
	bound.resize(params.size())
	var positional := 0
	for arg in node.kids:
		if arg.text == "":
			if positional >= params.size():
				_error(
					WyrdDiagnostic.E_ARG_TYPE,
					"function \"%s\" expects at most %d arguments" % [node.text, params.size()],
					arg
				)
				if arg.a != null:
					_check(arg.a, &"")
			else:
				bound[positional] = arg
				positional += 1
		else:
			var idx := _param_index(params, arg.text)
			if idx < 0:
				_error(
					WyrdDiagnostic.E_ARG_NAME,
					"function \"%s\" has no argument \"%s\"" % [node.text, arg.text],
					arg
				)
				if arg.a != null:
					_check(arg.a, &"")
			elif bound[idx] != null:
				_error(
					WyrdDiagnostic.E_ARG_NAME,
					"function \"%s\" argument \"%s\" is duplicated" % [node.text, arg.text],
					arg
				)
			else:
				bound[idx] = arg
	var slots: Array = []
	for i in params.size():
		var param: Dictionary = params[i]
		var pname := String(param["name"])
		var ptype := StringName(param["type"])
		if bound[i] == null:
			if not bool(param["optional"]):
				_error(
					WyrdDiagnostic.E_ARG_TYPE,
					"function \"%s\" missing argument \"%s\"" % [node.text, pname],
					node
				)
			var omit := WyrdExprNode.new()
			omit.kind = &"omit"
			slots.append(omit)
			continue
		var arg: WyrdExprNode = bound[i]
		_check(arg.a, ptype)
		if not _fits(arg.a.type_name, ptype):
			_error(
				WyrdDiagnostic.E_ARG_TYPE,
				"function \"%s\" argument \"%s\" expects %s, got %s" % [node.text, pname, ptype, arg.a.type_name],
				arg.a
			)
		arg.type_name = arg.a.type_name
		slots.append(arg.a)
	node.payload = slots
	node.type_name = sig["return"]
	if node.text == "belief":
		node.type_name = _belief_type(slots)
	if node.text == "belief" or node.text == "believes" or node.text == "conflicted":
		if not reads.has(_MEMBERSHIP_READ):
			reads.append(_MEMBERSHIP_READ)


func _field(node: WyrdExprNode) -> void:
	_check(node.a, WyrdSignatures.T_ENTITY)
	node.type_name = WyrdSignatures.T_SYMBOL
	if node.a.type_name != WyrdSignatures.T_ENTITY and node.a.type_name != &"error":
		_error(WyrdDiagnostic.E_OP_TYPE, "operator \".\" does not accept %s" % node.a.type_name, node)


func _static_text(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"name":
		return node.text
	if node.kind == &"path" and node.kids.size() == 1:
		return _static_text(node.kids[0])
	return ""


func _resolve(node: WyrdExprNode, expected: StringName, force_fact: bool) -> void:
	var dynamic := false
	for kid in node.kids:
		if _static_text(kid).is_empty():
			dynamic = true
			break
	# A call such as alive(candidate) expects an entity and would otherwise
	# become a constant name before the binding table is consulted.
	if not dynamic and _bound_name(node):
		return
	if not dynamic and _unbound_dollar(node):
		return
	if not force_fact and not dynamic and (expected == WyrdSignatures.T_SYMBOL or expected == WyrdSignatures.T_ENTITY):
		_as_name(node, expected)
		return
	var query := PackedStringArray()
	var rebuilt: Array[WyrdExprNode] = []
	for kid in node.kids:
		var text := _static_text(kid)
		if not text.is_empty():
			query.append(text)
			rebuilt.append(_segment_name(kid, text))
		else:
			dynamic = true
			query.append("{id}")
			_check(kid, &"")
			if not _segment_ok(kid.type_name):
				_error(
					WyrdDiagnostic.E_OP_TYPE,
					"key segment is %s, expected symbol or entity" % kid.type_name,
					kid
				)
			rebuilt.append(kid)
	if query.is_empty() and node.kind == &"name" and node.text != "":
		query.append(node.text)
	if _named_binding(node, query):
		return
	if _event_binding(node, query, binding_prefix):
		return
	var fact := schema.lookup(query)
	if fact == null:
		if not force_fact and not dynamic and query.size() == 1 and expected != WyrdSignatures.T_FACT_KEY:
			_as_name(node, WyrdSignatures.T_ENTITY if expected == WyrdSignatures.T_ENTITY else WyrdSignatures.T_SYMBOL)
			return
		var key := ".".join(query)
		_error(WyrdDiagnostic.E_UNKNOWN_FACT, "unknown fact \"%s\"" % key, node)
		node.kind = &"fact"
		node.text = key
		node.type_name = &"error"
		if dynamic:
			node.kids = rebuilt
		else:
			node.kids.clear()
		return
	_note(fact, node)
	node.kind = &"fact"
	node.text = fact.key
	# Reads stay on the pattern key. A concrete key under that pattern still has
	# to load its own segments, or the id is lost and the resolver cannot run.
	if dynamic or fact.is_pattern():
		node.kids = rebuilt
	else:
		node.kids.clear()
	node.type_name = WyrdSignatures.T_SYMBOL if expected == WyrdSignatures.T_FACT_KEY else fact.type_name


func _segment_name(kid: WyrdExprNode, text: String) -> WyrdExprNode:
	var seg := WyrdExprNode.new()
	seg.kind = &"name"
	seg.text = text
	seg.type_name = WyrdSignatures.T_SYMBOL
	seg.line = kid.line
	seg.col = kid.col
	seg.end_line = kid.end_line
	seg.end_col = kid.end_col
	return seg


func _as_name(node: WyrdExprNode, type_name: StringName) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for kid in node.kids:
		var text := _static_text(kid)
		if text.is_empty():
			text = kid.text
		parts.append(text)
	if parts.is_empty() and node.text != "":
		parts.append(node.text)
	node.kind = &"name"
	node.text = ".".join(parts)
	node.type_name = type_name
	node.kids.clear()


func _unbound_dollar(node: WyrdExprNode) -> bool:
	var key := _bare_key(node)
	if not key.begins_with("$") or bindings.has(key):
		return false
	_error(WyrdDiagnostic.E_EXPR_UNEXPECTED, "\"%s\" is only valid in an unwilling condition" % key, node)
	node.kind = &"error"
	node.type_name = &"error"
	node.kids.clear()
	return true


func _bare_key(node: WyrdExprNode) -> String:
	if node.kind == &"name" and node.text != "":
		return node.text
	if node.kids.size() == 1:
		return _static_text(node.kids[0])
	return ""


func _bound_name(node: WyrdExprNode) -> bool:
	var key := ""
	if node.kind == &"name" and node.text != "":
		key = node.text
	elif node.kids.size() == 1:
		key = _static_text(node.kids[0])
	if key.is_empty() or not bindings.has(key):
		return false
	node.kind = &"fact"
	node.text = key
	node.kids.clear()
	node.type_name = StringName(bindings[key])
	return true


func _named_binding(node: WyrdExprNode, query: PackedStringArray) -> bool:
	if query.size() != 1 or not bindings.has(query[0]):
		return false
	node.kind = &"fact"
	node.text = query[0]
	node.kids.clear()
	node.type_name = StringName(bindings[query[0]])
	return true


func _event_binding(node: WyrdExprNode, query: PackedStringArray, prefix: String = "event") -> bool:
	if query.size() != 2 or query[0] != prefix:
		return false
	if prefix == "event" and event_fields.is_empty():
		return false
	var field := query[1]
	node.kind = &"fact"
	node.text = "%s.%s" % [prefix, field]
	node.kids.clear()
	if not event_fields.has(field):
		var noun := "deed" if prefix == "deed" else "event"
		_error(WyrdDiagnostic.E_EVENT_ARG, "unknown %s field \"%s\"" % [noun, field], node)
		node.type_name = &"error"
		return true
	node.type_name = StringName(event_fields[field])
	return true


func _note(fact: WyrdFact, node: WyrdExprNode) -> void:
	var key := StringName(fact.key)
	if not reads.has(key):
		reads.append(key)
	if context != _WAIT or fact.origin != &"resolved":
		return
	if fact.invalidate == &"" or fact.invalidate == &"per_query":
		_error(
			WyrdDiagnostic.E_WAIT_RESOLVER_MODE,
			"resolved fact \"%s\" needs on_event or poll invalidation" % fact.key,
			node
		)


func _infer(node: WyrdExprNode) -> StringName:
	if node == null:
		return &"error"
	match node.kind:
		&"bool":
			return WyrdSignatures.T_BOOL
		&"int":
			return WyrdSignatures.T_INT
		&"float":
			return WyrdSignatures.T_FLOAT
		&"unit":
			if node.text.ends_with("h") or node.text.ends_with("d"):
				return WyrdSignatures.T_DURATION
			return &"unit"
		&"unary":
			return WyrdSignatures.T_BOOL if node.text == "not" else _infer(node.a)
		&"binary":
			if node.text == "+" or node.text == "-" or node.text == "*" or node.text == "/":
				return WyrdSignatures.T_INT
			return WyrdSignatures.T_BOOL
		&"call":
			var sig := signatures.signature(StringName(node.text))
			if sig.is_empty():
				return &"error"
			return sig["return"]
		&"field":
			return WyrdSignatures.T_SYMBOL
		&"path", &"fact", &"name":
			return _infer_path(node)
		&"ternary":
			return _infer(node.b)
		_:
			return &"error"


func _infer_path(node: WyrdExprNode) -> StringName:
	var query := PackedStringArray()
	for kid in node.kids:
		var text := _static_text(kid)
		if text.is_empty():
			query.append("{id}")
		else:
			query.append(text)
	if query.is_empty() and node.text != "":
		query.append(node.text)
	var fact := schema.lookup(query)
	if fact != null:
		return fact.type_name
	return &"name"


func _binding_type(node: WyrdExprNode) -> StringName:
	if node == null or (node.kind != &"path" and node.kind != &"name" and node.kind != &"fact"):
		return &""
	if binding_prefix == "event" and event_fields.is_empty():
		return &""
	var query := PackedStringArray()
	for kid in node.kids:
		var text := _static_text(kid)
		if text.is_empty():
			return &""
		query.append(text)
	if query.is_empty() and node.text != "":
		query.append(node.text)
	if query.size() != 2 or query[0] != binding_prefix or not event_fields.has(query[1]):
		return &""
	return StringName(event_fields[query[1]])


func _name_expect(type_name: StringName) -> StringName:
	if type_name == WyrdSignatures.T_SYMBOL or type_name == WyrdSignatures.T_ENTITY:
		return type_name
	return &""


func _param_index(params: Array, arg_name: String) -> int:
	for i in params.size():
		var param: Dictionary = params[i]
		if String(param["name"]) == arg_name:
			return i
	return -1


func _fits(actual: StringName, expected: StringName) -> bool:
	if expected == &"" or actual == expected or actual == &"error":
		return true
	if actual == WyrdSignatures.T_INT and expected == WyrdSignatures.T_FLOAT:
		return true
	if expected == WyrdSignatures.T_FACT_KEY and actual == WyrdSignatures.T_SYMBOL:
		return true
	if actual == &"name" and (expected == WyrdSignatures.T_SYMBOL or expected == WyrdSignatures.T_ENTITY):
		return true
	return false


func _cmp_ok(left: StringName, right: StringName, ordered: bool) -> bool:
	if _numeric(left) and _numeric(right):
		return true
	if left != right:
		return false
	if left == WyrdSignatures.T_DURATION or left == WyrdSignatures.T_DISTANCE:
		return true
	if ordered:
		return false
	return (
		left == WyrdSignatures.T_BOOL
		or left == WyrdSignatures.T_SYMBOL
		or left == WyrdSignatures.T_ENTITY
	)


func _segment_ok(type_name: StringName) -> bool:
	return (
		type_name == &"error"
		or type_name == &"name"
		or type_name == WyrdSignatures.T_SYMBOL
		or type_name == WyrdSignatures.T_ENTITY
	)


func _bad_bool(node: WyrdExprNode) -> bool:
	return node.type_name != WyrdSignatures.T_BOOL and node.type_name != &"error"


func _numeric(type_name: StringName) -> bool:
	return type_name == WyrdSignatures.T_INT or type_name == WyrdSignatures.T_FLOAT


func _op2(node: WyrdExprNode) -> void:
	_error(
		WyrdDiagnostic.E_OP_TYPE,
		"operator \"%s\" does not accept %s and %s" % [node.text, node.a.type_name, node.b.type_name],
		node
	)


## A comparison reads the stored value. The bool form stays [code]believes[/code].
func _as_belief_value(node: WyrdExprNode) -> void:
	if node != null and node.kind == &"call" and node.text == "believes":
		node.text = "belief"


func _belief_type(slots: Array) -> StringName:
	if schema == null or slots.size() < 2 or not (slots[1] is WyrdExprNode):
		return WyrdSignatures.T_SYMBOL
	var key_node := slots[1] as WyrdExprNode
	if key_node.kind != &"fact" or key_node.text.contains("{") or not key_node.kids.is_empty():
		return WyrdSignatures.T_SYMBOL
	var fact := schema.lookup(String(key_node.text).split("."))
	if fact == null:
		return WyrdSignatures.T_SYMBOL
	return fact.type_name


func _warn(code: StringName, message: String, node: WyrdExprNode) -> void:
	diagnostics.add(code, message, path, node.line, node.col, WyrdDiagnostic.SEVERITY_WARNING)


func _error(code: StringName, message: String, node: WyrdExprNode) -> void:
	diagnostics.add(code, message, path, node.line, node.col)
