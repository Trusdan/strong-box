class_name WyrdStoryletTie
extends RefCounted

## Compile-time warning when two storylets can tie.
##
## @experimental
## A pair warns when the scope matches, the speakers can meet in one query,
## priority and specificity are equal, and the conditions can both be true.
## Weight does not suppress the warning. [code]speaker: any[/code] overlaps
## every speaker in that scope. Two other speakers do not overlap.
## Exclusion is equality on one subject, [code]!=[/code], and [code]not[/code]
## of the same comparison or call. [code]not[/code] of [code]and[/code] or
## [code]or[/code] does not prove exclusion. An [code]or[/code] does not either.

const WILDCARD := "any"


static func warn(diagnostics: WyrdDiagnostics, left: Dictionary, right: Dictionary) -> void:
	var a: WyrdStoryletDef = left["story"]
	var b: WyrdStoryletDef = right["story"]
	if a.id.is_empty() or b.id.is_empty() or a.id == b.id:
		return
	if not _scope_overlaps(a, b):
		return
	if not _speaker_overlaps(a.speaker, b.speaker):
		return
	if a.priority != b.priority or a.specificity != b.specificity:
		return
	if not _can_both(a, b):
		return
	var later := left
	var earlier := right
	if _before(left, right):
		later = right
		earlier = left
	var story: WyrdStoryletDef = later["story"]
	var other: WyrdStoryletDef = earlier["story"]
	var low := a.id if a.id < b.id else b.id
	var high := b.id if a.id < b.id else a.id
	diagnostics.add(
		WyrdDiagnostic.W_STORYLET_TIE,
		"storylet \"%s\" ties \"%s\" on %s speaker %s: priority %d specificity %d weights %d and %d"
		% [
			story.id,
			other.id,
			story.scope_text(),
			_speaker_text(a.speaker, b.speaker),
			story.priority,
			story.specificity,
			_weight_of(a, b, low),
			_weight_of(a, b, high),
		],
		str(later["path"]),
		story.line,
		story.col,
		WyrdDiagnostic.SEVERITY_WARNING
	)


static func and_parts(node: WyrdExprNode) -> Array[WyrdExprNode]:
	var parts: Array[WyrdExprNode] = []
	_and_into(node, parts)
	return parts


static func render(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	match node.kind:
		&"bool":
			return "true" if bool(node.value) else "false"
		&"int":
			return str(int(node.value))
		&"float":
			return str(float(node.value))
		&"name", &"unit":
			return node.text
		&"path":
			var segments: PackedStringArray = PackedStringArray()
			for kid in node.kids:
				if kid.kind == &"name":
					segments.append(kid.text)
				else:
					segments.append("{%s}" % render(kid))
			return ".".join(segments)
		&"call":
			var args: PackedStringArray = PackedStringArray()
			for kid in node.kids:
				args.append(_arg(kid))
			return "%s(%s)" % [node.text, ", ".join(args)]
		&"arg":
			return _arg(node)
		&"unary":
			if node.text == "not":
				return "not %s" % render(node.a)
			return "%s%s" % [node.text, render(node.a)]
		&"binary":
			return "%s %s %s" % [render(node.a), node.text, render(node.b)]
		_:
			if not node.text.is_empty():
				return node.text
			return String(node.kind)


static func _and_into(node: WyrdExprNode, parts: Array[WyrdExprNode]) -> void:
	if node != null and node.kind == &"binary" and node.text == "and":
		_and_into(node.a, parts)
		_and_into(node.b, parts)
		return
	if node != null:
		parts.append(node)


static func _arg(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"arg":
		var inner := render(node.a)
		if node.text.is_empty():
			return inner
		return "%s: %s" % [node.text, inner]
	return render(node)


static func _scope_overlaps(a: WyrdStoryletDef, b: WyrdStoryletDef) -> bool:
	if a.scope_kind != b.scope_kind:
		return false
	if a.scope_kind == &"bark":
		return true
	return a.scope_id == b.scope_id


static func _speaker_overlaps(left: String, right: String) -> bool:
	if left == right:
		return true
	return left == WILDCARD or right == WILDCARD


static func _speaker_text(left: String, right: String) -> String:
	if left == right:
		return left
	if left == WILDCARD:
		return "%s/%s" % [left, right]
	if right == WILDCARD:
		return "%s/%s" % [right, left]
	return left


static func _weight_of(a: WyrdStoryletDef, b: WyrdStoryletDef, id: String) -> int:
	if a.id == id:
		return a.weight
	return b.weight


static func _before(left: Dictionary, right: Dictionary) -> bool:
	var a: WyrdStoryletDef = left["story"]
	var b: WyrdStoryletDef = right["story"]
	var path_a := str(left["path"])
	var path_b := str(right["path"])
	if path_a != path_b:
		return path_a < path_b
	if a.line != b.line:
		return a.line < b.line
	if a.col != b.col:
		return a.col < b.col
	return a.id < b.id


## True when the two clause lists can be true together.
## An empty list, a generic storylet, or a condition that does not parse
## contributes no constraint, the same as an omitted [code]when[/code].
static func clauses_can_both(left: Array, right: Array) -> bool:
	return not bool(_merge(_from_clauses(left), _from_clauses(right)).get("never", false))


## Top-level [code]and[/code] parts of [param text]. [param generic] yields none.
static func when_clauses(text: String, generic: bool = false) -> Array:
	var parts: Array = []
	if generic or text.strip_edges().is_empty():
		return parts
	var diagnostics := WyrdDiagnostics.new()
	var tokens := WyrdExprLexer.new().tokenize(text, "", 1, 1, diagnostics)
	if diagnostics.has_errors():
		return parts
	var ast := WyrdExprParser.new().parse(tokens, diagnostics, "")
	if diagnostics.has_errors() or ast == null or ast.kind == &"error":
		return parts
	for part in and_parts(ast):
		parts.append(part)
	return parts


static func _can_both(a: WyrdStoryletDef, b: WyrdStoryletDef) -> bool:
	return clauses_can_both(when_clauses(a.when_text, a.generic), when_clauses(b.when_text, b.generic))


static func _from_clauses(parts: Array) -> Dictionary:
	var row := _blank()
	for part in parts:
		if part is WyrdExprNode:
			row = _merge(row, _from(part))
	return row


static func _from(node: WyrdExprNode) -> Dictionary:
	if node == null or node.kind == &"error":
		return _blank()
	var folded: Variant = WyrdCondition.const_bool(node)
	if folded == true:
		return _blank()
	if folded == false:
		return _never()
	match node.kind:
		&"binary":
			if node.text == "and":
				return _merge(_from(node.a), _from(node.b))
			if node.text == "or":
				return _blank()
			if node.text == "==":
				return _equality(node, true)
			if node.text == "!=":
				return _equality(node, false)
			return _literal(node, true)
		&"unary":
			if node.text == "not":
				return _negated(node.a)
			return _literal(node, true)
		_:
			return _literal(node, true)


static func _negated(node: WyrdExprNode) -> Dictionary:
	if node == null:
		return _blank()
	var folded: Variant = WyrdCondition.const_bool(node)
	if folded == true:
		return _never()
	if folded == false:
		return _blank()
	if node.kind == &"binary" and node.text == "==":
		return _equality(node, false)
	if node.kind == &"binary" and node.text == "!=":
		return _equality(node, true)
	if node.kind == &"unary" and node.text == "not":
		return _from(node.a)
	if node.kind == &"binary" and (node.text == "and" or node.text == "or"):
		return _blank()
	return _literal(node, false)


static func _equality(node: WyrdExprNode, required: bool) -> Dictionary:
	var left := render(node.a)
	var right := render(node.b)
	var subject := left
	var value := right
	if _subject(right) and not _subject(left):
		subject = right
		value = left
	var row := _blank()
	if required:
		(row["eq"] as Dictionary)[subject] = value
	else:
		var banned: Dictionary = (row["forbid_eq"] as Dictionary).get(subject, {})
		banned[value] = true
		(row["forbid_eq"] as Dictionary)[subject] = banned
	return row


static func _literal(node: WyrdExprNode, required: bool) -> Dictionary:
	var row := _blank()
	var text := render(node)
	if required:
		(row["must"] as Dictionary)[text] = true
	else:
		(row["forbid"] as Dictionary)[text] = true
	return row


static func _subject(text: String) -> bool:
	return text.contains(".") or text.contains("(")


static func _merge(left: Dictionary, right: Dictionary) -> Dictionary:
	if bool(left.get("never", false)) or bool(right.get("never", false)):
		return _never()
	var eq: Dictionary = (left["eq"] as Dictionary).duplicate()
	var more: Dictionary = right["eq"]
	for subject in more.keys():
		if eq.has(subject) and str(eq[subject]) != str(more[subject]):
			return _never()
		eq[subject] = more[subject]
	var forbid_eq: Dictionary = {}
	_copy_forbid(forbid_eq, left["forbid_eq"])
	_copy_forbid(forbid_eq, right["forbid_eq"])
	for subject in eq.keys():
		var banned: Dictionary = forbid_eq.get(subject, {})
		if banned.has(str(eq[subject])):
			return _never()
	var must: Dictionary = (left["must"] as Dictionary).duplicate()
	for key in (right["must"] as Dictionary).keys():
		must[key] = true
	var forbid: Dictionary = (left["forbid"] as Dictionary).duplicate()
	for key in (right["forbid"] as Dictionary).keys():
		forbid[key] = true
	for key in must.keys():
		if forbid.has(key):
			return _never()
	return {"eq": eq, "forbid": forbid, "forbid_eq": forbid_eq, "must": must, "never": false}


static func _copy_forbid(into: Dictionary, source: Dictionary) -> void:
	for subject in source.keys():
		var banned: Dictionary = into.get(subject, {})
		var more: Dictionary = source[subject]
		for value in more.keys():
			banned[value] = true
		into[subject] = banned


static func _blank() -> Dictionary:
	return {"eq": {}, "forbid": {}, "forbid_eq": {}, "must": {}, "never": false}


static func _never() -> Dictionary:
	var row := _blank()
	row["never"] = true
	return row
