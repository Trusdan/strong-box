class_name WyrdSecrecyLint
extends RefCounted

## Compile-time secrecy check. Runs only when [code]check --tiers[/code] passes a list.
##
## @experimental
## [code]W_SECRECY_LEAK[/code] warns when visible text at a lower tier interpolates
## a stored fact that every writer which can run sets at a higher tier.
## An empty tier is the lowest. A name missing from the list is locked:
## that text is skipped, and that writer is ignored. [code]{if}[/code] conditions
## are not values.

static func warn(pack: WyrdLinkedPack, diagnostics: WyrdDiagnostics, tiers: PackedStringArray) -> void:
	if pack == null or diagnostics == null or tiers.is_empty() or pack.xref == null:
		return
	var lint := WyrdSecrecyLint.new()
	lint._run(pack, diagnostics, tiers)


var _schema: WyrdFactSchema
var _tiers: PackedStringArray
var _diagnostics: WyrdDiagnostics
var _xref: WyrdFactXref


func _run(pack: WyrdLinkedPack, diagnostics: WyrdDiagnostics, tiers: PackedStringArray) -> void:
	_schema = pack.schema
	_tiers = tiers
	_diagnostics = diagnostics
	_xref = pack.xref
	for unit in pack.units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_stage(stage, path)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_prose(item.line_def.prose, path, item.line_def.secrecy, "")
				if item.choice != null:
					_prose(item.choice.label, path, item.choice.secrecy, "")
		for storylet in file.storylets:
			for line_def in storylet.lines:
				_prose(line_def.prose, path, line_def.secrecy, storylet.secrecy)
		for document in file.documents:
			if document.mode != "live" and document.mode != "frozen":
				continue
			for page in document.pages:
				for paragraph in page.get("paragraphs", []):
					_prose(paragraph.get("prose"), path, str(paragraph.get("secrecy", "")), document.secrecy)


func _stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_prose(journal.prose, path, journal.secrecy, "")
	for variant in stage.variants:
		if variant.body != null:
			_stage(variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_stage(child, path)


func _prose(node: WyrdExprNode, path: String, own: String, container: String) -> void:
	var tier := _effective(own, container)
	if bool(tier["skip"]):
		return
	_walk(node, path, int(tier["index"]), str(tier["name"]))


func _walk(node: WyrdExprNode, path: String, tier_index: int, tier_name: String) -> void:
	if node == null:
		return
	if node.kind == &"if":
		_walk(node.b, path, tier_index, tier_name)
		_walk(node.c, path, tier_index, tier_name)
		return
	if node.kind == &"value" or node.kind == &"variants":
		_warn_span(node, path, tier_index, tier_name)
	_walk(node.a, path, tier_index, tier_name)
	_walk(node.b, path, tier_index, tier_name)
	_walk(node.c, path, tier_index, tier_name)
	for kid in node.kids:
		_walk(kid, path, tier_index, tier_name)


func _warn_span(node: WyrdExprNode, path: String, tier_index: int, tier_name: String) -> void:
	var keys: Array = _world_keys(node.a).keys()
	keys.sort()
	for key in keys:
		var text := String(key)
		if not _stored_concrete(text):
			continue
		var lowest := _lowest(_xref.writer_tiers(text))
		if not bool(lowest["any"]) or tier_index >= int(lowest["index"]):
			continue
		var where := "text with no secrecy"
		if tier_index >= 0:
			where = "text at secrecy \"%s\"" % tier_name
		_diagnostics.add(
			WyrdDiagnostic.W_SECRECY_LEAK,
			"%s shows \"%s\", which is only set at secrecy \"%s\" or higher" % [where, text, str(lowest["name"])],
			path,
			node.line,
			node.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _effective(own: String, container: String) -> Dictionary:
	var own_at := _index_of(own)
	var box_at := _index_of(container)
	if own_at < -1 or box_at < -1:
		return {"index": -1, "name": "", "skip": true}
	var index := own_at if own_at > box_at else box_at
	var name := _tiers[index] if index >= 0 else ""
	return {"index": index, "name": name, "skip": false}


func _lowest(names: Array) -> Dictionary:
	var best := 0x7fffffff
	var best_name := ""
	var any := false
	for raw in names:
		var index := _index_of(str(raw))
		if index < -1:
			continue
		any = true
		if index < best:
			best = index
			best_name = _tiers[index] if index >= 0 else ""
	return {"any": any, "index": best, "name": best_name}


func _index_of(name: String) -> int:
	if name.is_empty():
		return -1
	var at := _tiers.find(name)
	if at < 0:
		return -2
	return at


func _stored_concrete(key: String) -> bool:
	if _schema == null or key.is_empty() or key.contains("{"):
		return false
	var fact := _schema.lookup(PackedStringArray(key.split(".")))
	return fact != null and fact.origin == &"stored" and not fact.is_pattern()


func _world_keys(node: WyrdExprNode) -> Dictionary:
	var found := {"claim": {}, "knows": {}, "world": {}}
	_walk_perspective(node, "", found)
	return found["world"]


func _walk_perspective(node: WyrdExprNode, mode: String, found: Dictionary) -> void:
	if node == null:
		return
	if node.kind == &"call":
		var next := ""
		if node.text == "belief" or node.text == "believes" or node.text == "held":
			next = "claim"
		elif node.text == "knows":
			next = "knows"
		var slots := _call_slots(node)
		for i in slots.size():
			_walk_perspective(slots[i], next if i == 1 else "", found)
		return
	if node.kind == &"arg":
		_walk_perspective(node.a, mode, found)
		return
	if node.kind == &"fact":
		if mode != "" and not node.text.contains("{"):
			found[mode][node.text] = true
		elif mode == "" and not node.text.contains("{"):
			found["world"][node.text] = true
		return
	_walk_perspective(node.a, "", found)
	_walk_perspective(node.b, "", found)
	_walk_perspective(node.c, "", found)
	for kid in node.kids:
		_walk_perspective(kid, "", found)


func _call_slots(node: WyrdExprNode) -> Array:
	var rows: Array = []
	if node.payload is Array:
		for item in node.payload:
			if item is WyrdExprNode:
				rows.append(item)
		if not rows.is_empty():
			return rows
	for kid in node.kids:
		if kid.a != null:
			rows.append(kid.a)
	return rows
