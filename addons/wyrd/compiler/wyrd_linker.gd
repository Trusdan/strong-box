class_name WyrdLinker
extends RefCounted

## Links one pack: symbols, line ids, commands, and the fact cross-reference.
##
## @experimental
## Files are already sorted. Diagnostics are added to the shared collector;
## [WyrdPack] sorts them. An [code]unlock topic[/code] or [code]lock topic[/code]
## with no [code]scope: topic[/code] storylet warns [code]W_TOPIC_NO_STORYLET[/code].

var _pack_id: String = ""
var _commands: WyrdCommandSchema
var _note_path: String = ""
var _diagnostics: WyrdDiagnostics
var _scenes: Dictionary = {}
var _roles: Dictionary = {}
var _document_defs: Dictionary = {}
var _template_ids: Dictionary = {}
var _quest_ids: Dictionary = {}
var _skip_commands_note: bool = false


func link(
	units: Array,
	schema: WyrdFactSchema,
	pack_id: String,
	language_version: int,
	commands: WyrdCommandSchema,
	note_path: String,
	skip_commands_note: bool,
	diagnostics: WyrdDiagnostics
) -> WyrdLinkedPack:
	_pack_id = pack_id
	_commands = commands
	_note_path = note_path
	_skip_commands_note = skip_commands_note
	_diagnostics = diagnostics
	_scenes = {}
	_document_defs = {}
	_template_ids = {}
	_quest_ids = {}
	var pack := WyrdLinkedPack.new()
	pack.pack_id = pack_id
	pack.language_version = language_version
	pack.schema = schema
	pack.units = units
	_index_symbols(units)
	_aliases(units, pack)
	_template_refs(units)
	_document_refs(units)
	_storylet_ties(units)
	_template_ties(units)
	_lines(units)
	_host_steps(units)
	_quests(units, pack)
	_quest_flow(units)
	_warn_unreachable(units)
	_role_refs(units)
	_topic_refs(units)
	_scenes_of(units)
	_commands_of(units)
	_warn_holder_gaps(units)
	pack.xref = WyrdFactXref.new()
	pack.storylet_index = _storylet_index(units)
	return pack


func finish_xref(pack: WyrdLinkedPack, fact_paths: Dictionary) -> void:
	if pack.xref == null:
		pack.xref = WyrdFactXref.new()
	var declared: Dictionary = {}
	if pack.events != null:
		declared = pack.events
	pack.xref.build(pack.schema, pack.units, fact_paths, _diagnostics, declared)


func _storylet_index(units: Array) -> WyrdStoryletIndex:
	var stories: Array = []
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for storylet in file.storylets:
			stories.append(storylet)
	var index := WyrdStoryletIndex.new()
	index.build(stories)
	return index


func _index_symbols(units: Array) -> void:
	var quests := {}
	var roles := {}
	var storylets := {}
	var sequences := {}
	var documents := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			if not quest.id.is_empty():
				_quest_ids[quest.id] = true
			_claim(quests, quest.id, path, quest.line, quest.col, WyrdDiagnostic.E_QUEST_DUPLICATE, "quest")
		for template in file.templates:
			if not template.id.is_empty():
				_template_ids[template.id] = true
			_claim(quests, template.id, path, template.line, template.col, WyrdDiagnostic.E_QUEST_DUPLICATE, "template")
		for role in file.roles:
			_claim(roles, role.id, path, role.line, role.col, WyrdDiagnostic.E_ROLE_DUPLICATE, "role")
		for storylet in file.storylets:
			_claim(storylets, storylet.id, path, storylet.line, storylet.col, WyrdDiagnostic.E_STORYLET_DUPLICATE, "storylet")
		for sequence in file.sequences:
			_claim(sequences, sequence.id, path, sequence.line, sequence.col, WyrdDiagnostic.E_SEQUENCE_DUPLICATE, "sequence")
		for document in file.documents:
			_claim(documents, document.id, path, document.line, document.col, WyrdDiagnostic.E_DOCUMENT_DUPLICATE, "document")
			if not document.id.is_empty():
				_document_defs[document.id] = document
		for scene in file.scenes:
			if scene.id.is_empty():
				continue
			if _scenes.has(scene.id):
				var prior: Dictionary = _scenes[scene.id]
				_diagnostics.add(
					WyrdDiagnostic.E_SCENE_DUPLICATE,
					"duplicate scene \"%s\" also declared in %s:%d:%d" % [scene.id, str(prior["path"]), int(prior["line"]), int(prior["col"])],
					path,
					scene.line,
					scene.col
				)
				continue
			_scenes[scene.id] = {"col": scene.col, "line": scene.line, "path": path, "scene": scene}
	_roles = roles


func _aliases(units: Array, pack: WyrdLinkedPack) -> void:
	var verbs := _live_verbs(units)
	var roles := {}
	var documents := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for role in file.roles:
			if not role.id.is_empty():
				roles[role.id] = true
		for document in file.documents:
			if not document.id.is_empty():
				documents[document.id] = true
	var aliases := {}
	var stages := _alias_stages(units)
	if not stages.is_empty():
		aliases["stage"] = stages
	var role_table := _alias_resolve("role", roles, _role_claims(units))
	if not role_table.is_empty():
		aliases["role"] = role_table
	var document_table := _alias_resolve("document", documents, _document_claims(units))
	if not document_table.is_empty():
		aliases["document"] = document_table
	var verb_table := _alias_resolve("verb", verbs, _verb_claims(units))
	if not verb_table.is_empty():
		aliases["verb"] = verb_table
	pack.aliases = aliases


func _alias_stages(units: Array) -> Dictionary:
	var tables := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quests:
			_alias_stage_scope(quest, path, tables)
		for template in file.templates:
			_alias_stage_scope(template, path, tables)
	return tables


func _alias_stage_scope(quest: WyrdQuestDef, path: String, tables: Dictionary) -> void:
	if quest == null or quest.id.is_empty():
		return
	var live := {}
	for stage in quest.stages:
		_collect_stage_ids(stage, live)
	var claims: Array = []
	for stage in quest.stages:
		_push_was(claims, stage.was_ids, stage.was_lines, stage.was_cols, stage.id, stage.line, stage.col, path)
	var resolved := _alias_resolve("stage", live, claims)
	if not resolved.is_empty():
		tables[quest.id] = resolved


func _collect_stage_ids(stage: WyrdStageDef, into: Dictionary) -> void:
	if stage == null:
		return
	if not stage.id.is_empty():
		into[stage.id] = true
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_collect_stage_ids(child, into)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null:
			_collect_stage_ids(variant.body, into)


func _role_claims(units: Array) -> Array:
	var claims: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for role in file.roles:
			_push_was(claims, role.was_ids, role.was_lines, role.was_cols, role.id, role.line, role.col, path)
	return claims


func _document_claims(units: Array) -> Array:
	var claims: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for document in file.documents:
			_push_was(claims, document.was_ids, document.was_lines, document.was_cols, document.id, document.line, document.col, path)
	return claims


func _verb_claims(units: Array) -> Array:
	var claims: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for row in file.verb_aliases:
			var body: Dictionary = row
			var olds: Array = body.get("olds", [])
			for old in olds:
				var item: Dictionary = old
				claims.append({
					"col": int(item.get("col", 1)),
					"line": int(item.get("line", 1)),
					"new_id": String(body.get("id", "")),
					"old": String(item.get("id", "")),
					"path": path,
					"stmt_col": int(body.get("col", 1)),
					"stmt_line": int(body.get("line", 1)),
					"stmt_path": path,
				})
	return claims


func _push_was(
	claims: Array,
	ids: PackedStringArray,
	lines: PackedInt32Array,
	cols: PackedInt32Array,
	new_id: String,
	stmt_line: int,
	stmt_col: int,
	path: String
) -> void:
	for i in ids.size():
		claims.append({
			"col": int(cols[i]),
			"line": int(lines[i]),
			"new_id": new_id,
			"old": String(ids[i]),
			"path": path,
			"stmt_col": stmt_col,
			"stmt_line": stmt_line,
			"stmt_path": path,
		})


func _alias_resolve(kind: String, live: Dictionary, claims: Array) -> Dictionary:
	var grouped := {}
	for claim in claims:
		var old := String(claim["old"])
		if not grouped.has(old):
			grouped[old] = []
		var bucket: Array = grouped[old]
		bucket.append(claim)
	var dropped := {}
	var names: Array = grouped.keys()
	names.sort()
	for old in names:
		var group: Array = grouped[old]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _alias_before(a, b)
		)
		if group.size() > 1:
			dropped[String(old)] = true
			var first: Dictionary = group[0]
			for index in range(1, group.size()):
				var later: Dictionary = group[index]
				_diagnostics.add(
					WyrdDiagnostic.E_ALIAS_DUPLICATE,
					"alias \"%s\" is claimed by \"%s\" and \"%s\"" % [String(old), String(first["new_id"]), String(later["new_id"])],
					String(later["path"]),
					int(later["line"]),
					int(later["col"])
				)
		for claim in group:
			var body: Dictionary = claim
			if live.has(String(body["old"])):
				dropped[String(body["old"])] = true
				_diagnostics.add(
					WyrdDiagnostic.E_ALIAS_CONFLICT,
					"alias \"%s\" is still a live %s" % [String(body["old"]), kind],
					String(body["path"]),
					int(body["line"]),
					int(body["col"])
				)
	var edges := {}
	var stmt := {}
	for claim in claims:
		var body: Dictionary = claim
		var old := String(body["old"])
		if dropped.has(old) or old.is_empty() or String(body["new_id"]).is_empty():
			continue
		edges[old] = String(body["new_id"])
		var new_id := String(body["new_id"])
		var site := {"col": int(body["stmt_col"]), "line": int(body["stmt_line"]), "path": String(body["stmt_path"])}
		if not stmt.has(new_id) or _alias_site_before(site, stmt[new_id]):
			stmt[new_id] = site
	_alias_cycles(edges, stmt)
	var resolved := {}
	var olds: Array = edges.keys()
	olds.sort()
	for old in olds:
		var final_id := _alias_final(String(old), edges)
		if final_id.is_empty() or final_id == String(old):
			continue
		resolved[String(old)] = final_id
	return resolved


func _alias_before(a: Dictionary, b: Dictionary) -> bool:
	var path_a := String(a["path"])
	var path_b := String(b["path"])
	if path_a != path_b:
		return path_a < path_b
	if int(a["line"]) != int(b["line"]):
		return int(a["line"]) < int(b["line"])
	if int(a["col"]) != int(b["col"]):
		return int(a["col"]) < int(b["col"])
	return String(a["new_id"]) < String(b["new_id"])


func _alias_site_before(a: Dictionary, b: Dictionary) -> bool:
	var path_a := String(a["path"])
	var path_b := String(b["path"])
	if path_a != path_b:
		return path_a < path_b
	if int(a["line"]) != int(b["line"]):
		return int(a["line"]) < int(b["line"])
	return int(a["col"]) < int(b["col"])


func _alias_cycles(edges: Dictionary, stmt: Dictionary) -> void:
	var seen := {}
	var starts: Array = edges.keys()
	starts.sort()
	for start in starts:
		if seen.has(start):
			continue
		var stack: Array = []
		var index := {}
		var node := String(start)
		var cycle: Array = []
		while edges.has(node) and not seen.has(node):
			if index.has(node):
				cycle = stack.slice(int(index[node]))
				break
			index[node] = stack.size()
			stack.append(node)
			node = String(edges[node])
		for item in stack:
			seen[String(item)] = true
		if cycle.is_empty():
			continue
		for item in cycle:
			seen[String(item)] = true
		var best := 0
		for i in cycle.size():
			if _alias_cycle_before(String(cycle[i]), String(cycle[best]), stmt):
				best = i
		var ordered: Array = []
		for i in cycle.size():
			ordered.append(String(cycle[(best + i) % cycle.size()]))
		var parts: PackedStringArray = PackedStringArray()
		for id in ordered:
			parts.append(String(id))
		parts.append(String(ordered[0]))
		var start_id := String(ordered[0])
		for id in ordered:
			edges.erase(String(id))
		var site: Dictionary = stmt.get(start_id, {"col": 1, "line": 1, "path": ""})
		_diagnostics.add(
			WyrdDiagnostic.E_ALIAS_CYCLE,
			"alias cycle: %s" % " -> ".join(parts),
			String(site.get("path", "")),
			int(site.get("line", 1)),
			int(site.get("col", 1))
		)


func _alias_cycle_before(id: String, other: String, stmt: Dictionary) -> bool:
	if not stmt.has(id):
		return false
	if not stmt.has(other):
		return true
	return _alias_site_before(stmt[id], stmt[other])


func _alias_final(old: String, edges: Dictionary) -> String:
	var seen := {}
	var current := old
	var guard := 0
	while edges.has(current) and guard < 64:
		if seen.has(current):
			return ""
		seen[current] = true
		current = String(edges[current])
		guard += 1
	return current


func _live_verbs(units: Array) -> Dictionary:
	var verbs := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for scene in file.scenes:
			for effect in scene.on_abort:
				_note_verb(verbs, effect)
			for item in scene.items:
				if item.effect != null:
					_note_verb(verbs, item.effect)
				if item.choice != null:
					for effect in item.choice.effects:
						_note_verb(verbs, effect)
		for storylet in file.storylets:
			for effect in storylet.effects:
				_note_verb(verbs, effect)
		for document in file.documents:
			if not document.verb_filter.is_empty():
				verbs[document.verb_filter] = true
			for effect in document.on_first_read:
				_note_verb(verbs, effect)
			for effect in document.on_read:
				_note_verb(verbs, effect)
		for template in file.templates:
			for hook in template.deed_hooks:
				if not hook.verb.is_empty():
					verbs[hook.verb] = true
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_live_stage_verbs(stage, verbs)
	return verbs


func _live_stage_verbs(stage: WyrdStageDef, verbs: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		_note_verb(verbs, effect)
	for handler in stage.handlers:
		for effect in handler.effects:
			_note_verb(verbs, effect)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null:
			_live_stage_verbs(variant.body, verbs)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_live_stage_verbs(child, verbs)


func _note_verb(verbs: Dictionary, effect: WyrdEffectDef) -> void:
	if effect != null and not effect.verb.is_empty():
		verbs[effect.verb] = true


func _document_refs(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quest_bodies():
			_check_doc_cond(quest.start_when, path)
			for slot in quest.slots:
				_check_doc_cond(slot.cast_when, path)
			for stage in quest.stages:
				_document_stage(stage, path)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_check_create_document(effect, path)
			for item in scene.items:
				if item.line_def != null:
					_check_doc_cond(item.line_def.condition, path)
					_scan_doc_prose(item.line_def.prose, path)
				if item.effect != null:
					_check_create_document(item.effect, path)
				if item.choice != null:
					_check_doc_cond(item.choice.condition, path)
					_scan_doc_prose(item.choice.label, path)
					for effect in item.choice.effects:
						_check_create_document(effect, path)
		for storylet in file.storylets:
			_check_doc_cond(storylet.condition, path)
			for effect in storylet.effects:
				_check_create_document(effect, path)
			for line_def in storylet.lines:
				_scan_doc_prose(line_def.prose, path)
		for role in file.roles:
			_check_doc_cond(role.eligibility, path)
		for sequence in file.sequences:
			_check_doc_cond(sequence.reset_cond, path)
			for step in sequence.steps:
				if step.where_cond != null:
					_check_doc_cond(step.where_cond, path)
		for document in file.documents:
			for page in document.pages:
				_check_doc_cond(page.get("condition"), path)
				for paragraph in page.get("paragraphs", []):
					_check_doc_cond(paragraph.get("condition"), path)
					_scan_doc_prose(paragraph.get("prose"), path)
			for effect in document.on_first_read:
				_check_create_document(effect, path)
			for effect in document.on_read:
				_check_create_document(effect, path)


func _document_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	_check_doc_cond(stage.waits_until, path)
	for row in stage.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition:
			_check_doc_cond(when, path)
	for effect in stage.effects:
		_check_create_document(effect, path)
	for handler in stage.handlers:
		for effect in handler.effects:
			_check_create_document(effect, path)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null:
			continue
		_check_doc_cond(variant.condition, path)
		_document_stage(variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_document_stage(child, path)


func _check_create_document(effect: WyrdEffectDef, path: String) -> void:
	if effect == null or effect.kind != &"create_document":
		return
	var found: WyrdDocumentDef = _document_defs.get(effect.document_id)
	if found == null:
		_diagnostics.add(WyrdDiagnostic.E_DOCUMENT_UNKNOWN, "unknown document \"%s\"" % effect.document_id, path, effect.line, effect.col)
		return
	if found.mode != "frozen":
		_diagnostics.add(WyrdDiagnostic.E_DOCUMENT_NOT_FROZEN, "document \"%s\" is not frozen" % effect.document_id, path, effect.line, effect.col)


func _check_doc_cond(compiled: Variant, path: String) -> void:
	if not (compiled is WyrdCompiledCondition):
		return
	var cond := compiled as WyrdCompiledCondition
	for doc_id in _has_read_docs(cond):
		if _document_defs.has(doc_id):
			continue
		_diagnostics.add(
			WyrdDiagnostic.E_DOCUMENT_UNKNOWN,
			"unknown document \"%s\"" % doc_id,
			path,
			int(cond.source_span.get("line", 1)),
			int(cond.source_span.get("col", 1))
		)


func _scan_doc_prose(node: Variant, path: String) -> void:
	if not (node is WyrdExprNode):
		return
	var expr := node as WyrdExprNode
	if expr.payload is WyrdCompiledCondition:
		_check_doc_cond(expr.payload, path)
	_scan_doc_prose(expr.a, path)
	_scan_doc_prose(expr.b, path)
	_scan_doc_prose(expr.c, path)
	for kid in expr.kids:
		_scan_doc_prose(kid, path)


func _has_read_docs(compiled: WyrdCompiledCondition) -> PackedStringArray:
	var found := {}
	var stack: Array = []
	var code := compiled.code
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		if op == WyrdOpcodes.PUSH_CONST:
			stack.append(compiled.consts[code[ip]])
			ip += 1
		elif op == WyrdOpcodes.LOAD_FACT:
			stack.append(null)
			ip += 1
		elif op == WyrdOpcodes.PUSH_TRUE or op == WyrdOpcodes.PUSH_FALSE or op == WyrdOpcodes.PUSH_NIL:
			stack.append(null)
		elif op == WyrdOpcodes.LOAD_KEY:
			var count := code[ip]
			ip += 1
			for _i in count:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.NEG or op == WyrdOpcodes.NOT:
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.ADD or op == WyrdOpcodes.SUB or op == WyrdOpcodes.MUL or op == WyrdOpcodes.DIV or op == WyrdOpcodes.EQ or op == WyrdOpcodes.NE or op == WyrdOpcodes.LT or op == WyrdOpcodes.LE or op == WyrdOpcodes.GT or op == WyrdOpcodes.GE:
			if not stack.is_empty():
				stack.pop_back()
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_RANGE:
			for _i in 3:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_SET:
			var set_count := code[ip]
			ip += 1
			for _i in set_count + 1:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.CALL:
			var name := String(compiled.consts[code[ip]])
			var argc := code[ip + 1]
			ip += 2
			var args: Array = []
			for _i in argc:
				if stack.is_empty():
					args.append(null)
				else:
					args.push_front(stack.pop_back())
			if name == "has_read" and args.size() >= 2 and (args[1] is String or args[1] is StringName):
				found[String(args[1])] = true
			stack.append(null)
		elif op == WyrdOpcodes.JUMP:
			ip += 1
		elif op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			if not stack.is_empty():
				stack.pop_back()
			ip += 1
		else:
			break
	var names := PackedStringArray()
	for key in found.keys():
		names.append(String(key))
	names.sort()
	return names


func _claim(table: Dictionary, id: String, path: String, line: int, col: int, code: StringName, noun: String) -> void:
	if id.is_empty():
		return
	if table.has(id):
		var prior: Dictionary = table[id]
		_diagnostics.add(
			code,
			"duplicate %s \"%s\" also declared in %s:%d:%d" % [noun, id, str(prior["path"]), int(prior["line"]), int(prior["col"])],
			path,
			line,
			col
		)
		return
	table[id] = {"col": col, "line": line, "path": path}


func _storylet_ties(units: Array) -> void:
	var rows: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for storylet in file.storylets:
			rows.append({"path": path, "story": storylet})
	for index in rows.size():
		for other in range(index + 1, rows.size()):
			WyrdStoryletTie.warn(_diagnostics, rows[index], rows[other])


func _template_refs(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quest_bodies():
			_scan_template_cond(quest.start_when, path)
			for slot in quest.slots:
				_scan_template_cond(slot.cast_when, path)
			if quest is WyrdTemplateDef:
				var template := quest as WyrdTemplateDef
				_scan_template_cond(template.when_cond, path)
				_scan_template_cond(template.assumes, path)
				for param in template.params:
					_scan_template_cond(param.cast_when, path)
			for stage in quest.stages:
				_scan_template_stage(stage, path)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_scan_template_cond(item.line_def.condition, path)
				if item.choice != null:
					_scan_template_cond(item.choice.condition, path)
		for storylet in file.storylets:
			_scan_template_cond(storylet.condition, path)
			if storylet.scope_kind == &"beat":
				var beat_id := storylet.scope_id
				var dot := beat_id.find(".")
				if dot > 0:
					beat_id = beat_id.substr(0, dot)
				if _template_ids.has(beat_id):
					_template_ref(beat_id, path, storylet.line, storylet.col)
		for role in file.roles:
			_scan_template_cond(role.eligibility, path)
		for sequence in file.sequences:
			_scan_template_cond(sequence.reset_cond, path)
			for step in sequence.steps:
				_scan_template_cond(step.where_cond, path)


func _scan_template_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	_scan_template_cond(stage.waits_until, path)
	for row in stage.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition:
			_scan_template_cond(when, path)
	for handler in stage.handlers:
		_scan_template_cond(handler.where_cond, path)
	for journal in stage.journals:
		_scan_template_cond(journal.condition, path)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null:
			continue
		_scan_template_cond(variant.condition, path)
		_scan_template_stage(variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_scan_template_stage(child, path)


func _scan_template_cond(compiled: Variant, path: String) -> void:
	if not (compiled is WyrdCompiledCondition):
		return
	var cond := compiled as WyrdCompiledCondition
	var line := int(cond.source_span.get("line", 1))
	var col := int(cond.source_span.get("col", 1))
	var stack: Array = []
	var code := cond.code
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		if op == WyrdOpcodes.PUSH_CONST:
			stack.append(cond.consts[code[ip]])
			ip += 1
		elif op == WyrdOpcodes.LOAD_FACT:
			stack.append(null)
			ip += 1
		elif op == WyrdOpcodes.PUSH_TRUE or op == WyrdOpcodes.PUSH_FALSE or op == WyrdOpcodes.PUSH_NIL:
			stack.append(null)
		elif op == WyrdOpcodes.LOAD_KEY:
			var count := code[ip]
			ip += 1
			for _i in count:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.NEG or op == WyrdOpcodes.NOT:
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.ADD or op == WyrdOpcodes.SUB or op == WyrdOpcodes.MUL or op == WyrdOpcodes.DIV or op == WyrdOpcodes.EQ or op == WyrdOpcodes.NE or op == WyrdOpcodes.LT or op == WyrdOpcodes.LE or op == WyrdOpcodes.GT or op == WyrdOpcodes.GE:
			if not stack.is_empty():
				stack.pop_back()
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_RANGE:
			for _i in 3:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_SET:
			var set_count := code[ip]
			ip += 1
			for _i in set_count + 1:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.CALL:
			var name := String(cond.consts[code[ip]])
			var argc := code[ip + 1]
			ip += 2
			var args: Array = []
			for _i in argc:
				if stack.is_empty():
					args.append(null)
				else:
					args.push_front(stack.pop_back())
			_note_template_call(name, args, path, line, col)
			stack.append(null)
		elif op == WyrdOpcodes.JUMP:
			ip += 1
		elif op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			if not stack.is_empty():
				stack.pop_back()
			ip += 1
		else:
			break


func _note_template_call(name: String, args: Array, path: String, line: int, col: int) -> void:
	if args.is_empty():
		return
	var id := _symbol_text(args[0])
	if id.is_empty():
		return
	if name == "quest" or name == "stage" or name == "outcome":
		if _template_ids.has(id):
			_template_ref(id, path, line, col)
		return
	if name == "active_count" and not _template_ids.has(id) and not _quest_ids.has(id):
		_diagnostics.add(WyrdDiagnostic.E_TEMPLATE_UNKNOWN, "unknown template \"%s\"" % id, path, line, col)


func _symbol_text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


func _template_ref(id: String, path: String, line: int, col: int) -> void:
	_diagnostics.add(
		WyrdDiagnostic.E_TEMPLATE_REF,
		"\"%s\" is a template; content cannot name its instances" % id,
		path,
		line,
		col
	)


func _template_ties(units: Array) -> void:
	var rows: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for template in file.templates:
			rows.append({"path": path, "template": template})
	for index in rows.size():
		for other in range(index + 1, rows.size()):
			_template_tie(rows[index], rows[other])


func _template_tie(left: Dictionary, right: Dictionary) -> void:
	var a: WyrdTemplateDef = left["template"]
	var b: WyrdTemplateDef = right["template"]
	if a.id.is_empty() or b.id.is_empty() or a.id == b.id:
		return
	if a.priority != b.priority or a.specificity != b.specificity:
		return
	if not WyrdTemplateDef.tiers_overlap(a, b):
		return
	if not WyrdStoryletTie.clauses_can_both(WyrdStoryletTie.when_clauses(a.when_text), WyrdStoryletTie.when_clauses(b.when_text)):
		return
	var later := left
	var earlier := right
	if _template_before(left, right):
		later = right
		earlier = left
	var template: WyrdTemplateDef = later["template"]
	var other: WyrdTemplateDef = earlier["template"]
	var low := a.id if a.id < b.id else b.id
	var high := b.id if a.id < b.id else a.id
	_diagnostics.add(
		WyrdDiagnostic.W_TEMPLATE_TIE,
		"template \"%s\" ties \"%s\": priority %d specificity %d weights %d and %d" % [
			template.id,
			other.id,
			template.priority,
			template.specificity,
			a.weight if a.id == low else b.weight,
			a.weight if a.id == high else b.weight,
		],
		str(later["path"]),
		template.line,
		template.col,
		WyrdDiagnostic.SEVERITY_WARNING
	)


func _template_before(left: Dictionary, right: Dictionary) -> bool:
	var a: WyrdTemplateDef = left["template"]
	var b: WyrdTemplateDef = right["template"]
	var path_a := str(left["path"])
	var path_b := str(right["path"])
	if path_a != path_b:
		return path_a < path_b
	if a.line != b.line:
		return a.line < b.line
	if a.col != b.col:
		return a.col < b.col
	return a.id < b.id


func _is_param(quest: WyrdQuestDef, name: String) -> bool:
	if not (quest is WyrdTemplateDef):
		return false
	for param in (quest as WyrdTemplateDef).params:
		if param.name == name:
			return true
	return false


func _lines(units: Array) -> void:
	var seen := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_line_stage(stage, path, seen)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_take_line(seen, item.line_def.line_id, path, item.line_def.line, item.line_def.col)
				if item.choice != null:
					_take_line(seen, item.choice.line_id, path, item.choice.line, item.choice.col)
		for storylet in file.storylets:
			for line_def in storylet.lines:
				_take_line(seen, line_def.line_id, path, line_def.line, line_def.col)
		for document in file.documents:
			if document.mode != "live" and document.mode != "frozen":
				continue
			_take_line(seen, document.line_id, path, document.line, document.col)
			for page in document.pages:
				for paragraph in page.get("paragraphs", []):
					_take_line(seen, str(paragraph.get("line_id", "")), path, int(paragraph.get("line", 1)), int(paragraph.get("col", 1)))


func _line_regions(stage: WyrdStageDef, path: String, seen: Dictionary) -> void:
	if stage == null:
		return
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_line_stage(child, path, seen)


func _cover_regions(stage: WyrdStageDef, used: Dictionary, empty_covered: Dictionary, gone_covered: Dictionary) -> void:
	if stage == null:
		return
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_mark_coverage(child, used, empty_covered, gone_covered)


func _line_stage(stage: WyrdStageDef, path: String, seen: Dictionary) -> void:
	for journal in stage.journals:
		_take_line(seen, journal.line_id, path, journal.line, journal.col)
	for variant in stage.variants:
		if variant.body != null:
			_line_stage(variant.body, path, seen)
	_line_regions(stage, path, seen)


func _take_line(seen: Dictionary, id: String, path: String, line: int, col: int) -> void:
	if id.is_empty():
		return
	if not seen.has(id):
		seen[id] = {"col": col, "line": line, "path": path}
		return
	var prior: Dictionary = seen[id]
	if str(prior["path"]) == path:
		return
	_diagnostics.add(
		WyrdDiagnostic.E_LINE_ID_DUPLICATE,
		"duplicate #line: id \"%s\" in %s:%d:%d and %s:%d:%d" % [id, str(prior["path"]), int(prior["line"]), int(prior["col"]), path, line, col],
		path,
		line,
		col
	)


func _quests(units: Array, pack: WyrdLinkedPack) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			var stages := {}
			for stage in quest.stages:
				if not stage.id.is_empty():
					stages[stage.id] = true
			for pack_ref in quest.requires:
				var id := pack_ref.substr(5) if pack_ref.begins_with("pack.") else pack_ref
				if id == _pack_id:
					continue
				_diagnostics.add(
					WyrdDiagnostic.W_PACK_UNKNOWN,
					"pack \"%s\" is not loaded; the quest stays unavailable until it is" % id,
					path,
					quest.requires_line,
					quest.requires_col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
			for stage in quest.stages:
				_quest_stage(quest, stage, stages, path, pack)
			_warn_empty(quest, path)
			_warn_routes(quest, path)


func _quest_flow(units: Array) -> void:
	var stages_of := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			var names := {}
			for stage in quest.stages:
				if not stage.id.is_empty():
					names[stage.id] = true
			stages_of[quest.id] = names
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_flow_stage(stage, path, stages_of)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_flow_effect(effect, path, stages_of)
			for item in scene.items:
				if item.choice == null:
					continue
				for effect in item.choice.effects:
					_flow_effect(effect, path, stages_of)


func _flow_stage(stage: WyrdStageDef, path: String, stages_of: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		_flow_effect(effect, path, stages_of)
	for handler in stage.handlers:
		for effect in handler.effects:
			_flow_effect(effect, path, stages_of)
	for variant in stage.variants:
		if variant.body != null:
			_flow_stage(variant.body, path, stages_of)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_flow_stage(child, path, stages_of)


func _role_refs(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_role_stage(stage, path)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_role_effect(effect, path)
			for item in scene.items:
				if item.effect != null:
					_role_effect(item.effect, path)
				if item.choice == null:
					continue
				for effect in item.choice.effects:
					_role_effect(effect, path)
		for story in file.storylets:
			for effect in story.effects:
				_role_effect(effect, path)


func _role_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		_role_effect(effect, path)
	for handler in stage.handlers:
		for effect in handler.effects:
			_role_effect(effect, path)
	for variant in stage.variants:
		if variant.body != null:
			_role_stage(variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_role_stage(child, path)


func _topic_refs(units: Array) -> void:
	var known := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for story in file.storylets:
			if story.scope_kind == &"topic" and not story.scope_id.is_empty():
				known[story.scope_id] = true
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_topic_stage(stage, path, known)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_topic_effect(effect, path, known)
			for item in scene.items:
				if item.effect != null:
					_topic_effect(item.effect, path, known)
				if item.choice == null:
					continue
				for effect in item.choice.effects:
					_topic_effect(effect, path, known)
		for story in file.storylets:
			for effect in story.effects:
				_topic_effect(effect, path, known)


func _topic_stage(stage: WyrdStageDef, path: String, known: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		_topic_effect(effect, path, known)
	for handler in stage.handlers:
		for effect in handler.effects:
			_topic_effect(effect, path, known)
	for variant in stage.variants:
		if variant.body != null:
			_topic_stage(variant.body, path, known)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_topic_stage(child, path, known)


func _topic_effect(effect: WyrdEffectDef, path: String, known: Dictionary) -> void:
	if effect == null:
		return
	if effect.kind != &"unlock_topic" and effect.kind != &"lock_topic":
		return
	if effect.topic.is_empty() or known.has(effect.topic):
		return
	_diagnostics.add(
		WyrdDiagnostic.W_TOPIC_NO_STORYLET,
		"topic \"%s\" has no storylet" % effect.topic,
		path,
		effect.line,
		effect.col,
		WyrdDiagnostic.SEVERITY_WARNING
	)


func _role_effect(effect: WyrdEffectDef, path: String) -> void:
	if effect.kind != &"assign_role" and effect.kind != &"vacate_role":
		return
	if effect.role.is_empty() or _roles.has(effect.role):
		return
	_diagnostics.add(
		WyrdDiagnostic.W_ROLE_UNKNOWN,
		"unknown role \"%s\"" % effect.role,
		path,
		effect.line,
		effect.col,
		WyrdDiagnostic.SEVERITY_WARNING
	)


func _flow_effect(effect: WyrdEffectDef, path: String, stages_of: Dictionary) -> void:
	if effect.kind != &"start_quest" and effect.kind != &"advance":
		return
	if _template_ids.has(effect.quest):
		_template_ref(effect.quest, path, effect.line, effect.col)
		return
	if effect.quest.is_empty() or not stages_of.has(effect.quest):
		_diagnostics.add(
			WyrdDiagnostic.E_QUEST_UNKNOWN,
			"unknown quest \"%s\"" % effect.quest,
			path,
			effect.line,
			effect.col
		)
		return
	if effect.kind != &"advance":
		return
	var names: Dictionary = stages_of[effect.quest]
	if names.has(effect.stage):
		return
	_diagnostics.add(
		WyrdDiagnostic.E_STAGE_UNKNOWN,
		"unknown stage \"%s\"" % effect.stage,
		path,
		effect.line,
		effect.col
	)


func _warn_empty(quest: WyrdQuestDef, path: String) -> void:
	var reachable := _reachable(quest)
	var used := {}
	var empty_covered := {}
	var gone_covered := {}
	for stage in reachable:
		_mark_coverage(stage, used, empty_covered, gone_covered)
	if quest.on_empty.is_empty():
		for slot in quest.slots:
			if slot.name.is_empty() or not used.has(slot.name) or empty_covered.has(slot.name):
				continue
			_diagnostics.add(
				WyrdDiagnostic.W_EMPTY_UNCOVERED,
				"slot \"%s\" can become empty and has no empty variant or on_empty" % slot.name,
				path,
				slot.line,
				slot.col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
	for slot in quest.slots:
		if slot.mode != &"locked_at" or slot.name.is_empty() or gone_covered.has(slot.name):
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_LOCKED_GONE_UNCOVERED,
			"locked_at slot \"%s\" has no locked_gone variant" % slot.name,
			path,
			slot.line,
			slot.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _warn_routes(quest: WyrdQuestDef, path: String) -> void:
	var branches := {}
	for stage in _reachable(quest):
		_mark_routes(stage, branches)
	var names: Array = branches.keys()
	names.sort()
	for branch in names:
		var row: Dictionary = branches[branch]
		if int(row["closed"]) == 0 or int(row["other"]) > 0:
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_ROUTE_CLOSED,
			"every route of branch \"%s\" closes" % String(branch),
			path,
			int(row["line"]),
			int(row["col"]),
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _reachable(quest: WyrdQuestDef) -> Array:
	var found: Array = []
	if quest.stages.is_empty():
		return found
	var by_id := {}
	for stage in quest.stages:
		if not stage.id.is_empty():
			by_id[stage.id] = stage
	var seen := {}
	var queue: Array = [quest.stages[0]]
	while not queue.is_empty():
		var stage: WyrdStageDef = queue.pop_front()
		if stage == null:
			continue
		var token := stage.id if not stage.id.is_empty() else str(stage.get_instance_id())
		if seen.has(token):
			continue
		seen[token] = true
		if not stage.id.is_empty():
			found.append(stage)
		_enqueue_targets(stage, by_id, queue)
	return found


func _enqueue_targets(stage: WyrdStageDef, by_id: Dictionary, queue: Array) -> void:
	if stage == null:
		return
	for row in stage.transitions:
		var target := str(row.get("target", ""))
		if by_id.has(target):
			queue.append(by_id[target])
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_enqueue_targets(variant.body, by_id, queue)


## A quest stage no [code]->[/code], [code]do … on_fail[/code], [code]advance[/code], or region path reaches.
## [method _reachable] is unchanged. A host [code]advance()[/code] call is not visible here.
func _warn_unreachable(units: Array) -> void:
	var advances := _advance_targets(units)
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			_warn_quest_reach(quest, path, advances)


func _warn_quest_reach(quest: WyrdQuestDef, path: String, advances: Dictionary) -> void:
	if quest.stages.is_empty():
		return
	var by_id := {}
	for stage in quest.stages:
		if not stage.id.is_empty():
			by_id[stage.id] = stage
	var first: WyrdStageDef = quest.stages[0]
	var first_label := "%s.%s" % [quest.id, first.id]
	var seen := {}
	var queue: Array = []
	if not first.id.is_empty():
		queue.append(first)
	var starts: Dictionary = advances.get(quest.id, {})
	for stage_id in starts:
		if by_id.has(stage_id):
			queue.append(by_id[stage_id])
	while not queue.is_empty():
		var stage: WyrdStageDef = queue.pop_front()
		if stage == null or stage.id.is_empty() or seen.has(stage.id):
			continue
		seen[stage.id] = true
		_enqueue_reach(stage, by_id, queue)
		_reach_regions(stage, "%s.%s" % [quest.id, stage.id], first_label, path)
	for stage in quest.stages:
		if stage.id.is_empty() or seen.has(stage.id):
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_STAGE_UNREACHABLE,
			"stage \"%s.%s\" is never reached from \"%s\"" % [quest.id, stage.id, first_label],
			path,
			stage.line,
			stage.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _reach_regions(stage: WyrdStageDef, parent_label: String, first_label: String, path: String) -> void:
	if stage == null:
		return
	for item in stage.regions:
		_reach_region(item as WyrdRegionDef, parent_label, first_label, path)
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_reach_regions(variant.body, parent_label, first_label, path)


func _reach_region(region: WyrdRegionDef, parent_label: String, first_label: String, path: String) -> void:
	if region == null or region.stages.is_empty():
		return
	var by_id := {}
	for child in region.stages:
		if not child.id.is_empty():
			by_id[child.id] = child
	var seen := {}
	var queue: Array = []
	var first: WyrdStageDef = region.stages[0]
	if not first.id.is_empty():
		queue.append(first)
	while not queue.is_empty():
		var child: WyrdStageDef = queue.pop_front()
		if child == null or child.id.is_empty() or seen.has(child.id):
			continue
		seen[child.id] = true
		_enqueue_reach(child, by_id, queue)
		var child_label := "%s.%s.%s" % [parent_label, region.id, child.id]
		_reach_regions(child, child_label, first_label, path)
	for child in region.stages:
		if child.id.is_empty() or seen.has(child.id):
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_STAGE_UNREACHABLE,
			"stage \"%s.%s.%s\" is never reached from \"%s\"" % [parent_label, region.id, child.id, first_label],
			path,
			child.line,
			child.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _enqueue_reach(stage: WyrdStageDef, by_id: Dictionary, queue: Array) -> void:
	if stage == null:
		return
	_enqueue_ids(stage.transitions, by_id, queue)
	_enqueue_fail_targets(stage.effects, by_id, queue)
	for handler in stage.handlers:
		_enqueue_ids(handler.transitions, by_id, queue)
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_enqueue_reach(variant.body, by_id, queue)


func _enqueue_ids(rows: Array, by_id: Dictionary, queue: Array) -> void:
	for row in rows:
		if not (row is Dictionary):
			continue
		var target := str(row.get("target", ""))
		if by_id.has(target):
			queue.append(by_id[target])


## A failed stage [code]do[/code] diverts to its [code]on_fail[/code] stage, so that
## target is an edge. Handler effects are not: they run without a divert.
func _enqueue_fail_targets(effects: Array, by_id: Dictionary, queue: Array) -> void:
	for item in effects:
		var effect := item as WyrdEffectDef
		if effect == null or effect.kind != &"do" or effect.on_fail.is_empty():
			continue
		if by_id.has(effect.on_fail):
			queue.append(by_id[effect.on_fail])


func _advance_targets(units: Array) -> Dictionary:
	var found := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_note_stage_advances(stage, found)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_note_advance(effect, found)
			for item in scene.items:
				if item.effect != null:
					_note_advance(item.effect, found)
				if item.choice == null:
					continue
				for effect in item.choice.effects:
					_note_advance(effect, found)
		for story in file.storylets:
			for effect in story.effects:
				_note_advance(effect, found)
		for document in file.documents:
			for effect in document.on_first_read:
				_note_advance(effect, found)
			for effect in document.on_read:
				_note_advance(effect, found)
	return found


func _note_stage_advances(stage: WyrdStageDef, found: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		_note_advance(effect, found)
	for handler in stage.handlers:
		for effect in handler.effects:
			_note_advance(effect, found)
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_note_stage_advances(variant.body, found)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_note_stage_advances(child, found)


func _note_advance(effect: WyrdEffectDef, found: Dictionary) -> void:
	if effect == null or effect.kind != &"advance":
		return
	if effect.quest.is_empty() or effect.stage.is_empty():
		return
	if not found.has(effect.quest):
		found[effect.quest] = {}
	found[effect.quest][effect.stage] = true


func _mark_coverage(stage: WyrdStageDef, used: Dictionary, empty_covered: Dictionary, gone_covered: Dictionary) -> void:
	if stage == null:
		return
	for ref in stage.scenes:
		for entry in ref.get("with", []):
			var name := str(entry.get("name", ""))
			if not name.is_empty():
				used[name] = true
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant == null:
			continue
		if not variant.slot.is_empty():
			used[variant.slot] = true
		# contested falls back to the empty variant, so it does not cover empty.
		if variant.state == &"empty":
			empty_covered[variant.slot] = true
		elif variant.state == &"locked_gone":
			gone_covered[variant.slot] = true
		if variant.body != null:
			_mark_coverage(variant.body, used, empty_covered, gone_covered)
	_cover_regions(stage, used, empty_covered, gone_covered)


func _mark_routes(stage: WyrdStageDef, branches: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		if effect.kind != &"outcome" or effect.branch.is_empty():
			continue
		if not branches.has(effect.branch):
			branches[effect.branch] = {"closed": 0, "col": effect.col, "line": effect.line, "other": 0}
		var row: Dictionary = branches[effect.branch]
		if effect.outcome == "route_closed":
			row["closed"] = int(row["closed"]) + 1
		else:
			row["other"] = int(row["other"]) + 1
		branches[effect.branch] = row
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_mark_routes(variant.body, branches)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_mark_routes(child, branches)


func _quest_stage(quest: WyrdQuestDef, stage: WyrdStageDef, stages: Dictionary, path: String, pack: WyrdLinkedPack) -> void:
	for ref in stage.scenes:
		var scene_id := str(ref["id"])
		if not _scenes.has(scene_id):
			_diagnostics.add(
				WyrdDiagnostic.E_SCENE_UNKNOWN,
				"unknown scene \"%s\"" % scene_id,
				path,
				int(ref["line"]),
				int(ref["col"])
			)
		elif _scenes[scene_id] is Dictionary:
			_bind(quest, ref, path)
	for effect in stage.effects:
		_topic(effect, pack)
		if effect.kind == &"do" and not effect.on_fail.is_empty() and not stages.has(effect.on_fail):
			_diagnostics.add(
				WyrdDiagnostic.E_STAGE_UNKNOWN,
				"unknown stage \"%s\"" % effect.on_fail,
				path,
				effect.line,
				effect.col
			)
	for variant in stage.variants:
		if variant.body != null:
			_quest_stage(quest, variant.body, stages, path, pack)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		var names := {}
		for child in region.stages:
			if not child.id.is_empty():
				names[child.id] = true
		for child in region.stages:
			_quest_stage(quest, child, names, path, pack)


func _bind(quest: WyrdQuestDef, ref: Dictionary, path: String) -> void:
	var scene_id := str(ref["id"])
	var located: Dictionary = _scenes[scene_id]
	var scene: WyrdSceneDef = located["scene"]
	var slot_names := {}
	for slot in quest.slots:
		slot_names[slot.name] = true
	var passed := {}
	for entry in ref["with"]:
		var name := str(entry["name"])
		passed[name] = true
		if not _uses(scene, name):
			var noun := "param" if _is_param(quest, name) else "slot"
			_diagnostics.add(
				WyrdDiagnostic.W_SLOT_UNUSED,
				"%s \"%s\" is not used in scene \"%s\"" % [noun, name, scene_id],
				path,
				int(entry["line"]),
				int(entry["col"]),
				WyrdDiagnostic.SEVERITY_WARNING
			)
	for speaker in _speakers(scene):
		var name := str(speaker["name"])
		if slot_names.has(name) and not passed.has(name):
			_diagnostics.add(
				WyrdDiagnostic.E_SPEAKER_UNBOUND,
				"slot speaker \"%s\" is not passed to scene \"%s\"" % [name, scene_id],
				str(located["path"]),
				int(speaker["line"]),
				int(speaker["col"])
			)


func _scenes_of(units: Array) -> void:
	var run: Dictionary = {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_mark_runs(stage, run)
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			if scene.id.is_empty() or run.has(scene.id):
				continue
			_diagnostics.add(
				WyrdDiagnostic.W_SCENE_UNUSED,
				"scene \"%s\" is not run by a quest" % scene.id,
				path,
				scene.line,
				scene.col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
			for item in scene.items:
				if item.divert_kind == &"scene" and not item.target.is_empty() and not _scenes.has(item.target):
					_diagnostics.add(
						WyrdDiagnostic.E_SCENE_UNKNOWN,
						"unknown scene \"%s\"" % item.target,
						path,
						item.line,
						item.col
					)
		for scene in file.scenes:
			if scene.id.is_empty() or not run.has(scene.id):
				continue
			for item in scene.items:
				if item.divert_kind != &"scene" or item.target.is_empty():
					continue
				if not _scenes.has(item.target):
					_diagnostics.add(
						WyrdDiagnostic.E_SCENE_UNKNOWN,
						"unknown scene \"%s\"" % item.target,
						path,
						item.line,
						item.col
					)
		for storylet in file.storylets:
			if storylet.body_kind != &"scene" or storylet.scene_id.is_empty():
				continue
			if _scenes.has(storylet.scene_id):
				continue
			_diagnostics.add(
				WyrdDiagnostic.E_SCENE_UNKNOWN,
				"unknown scene \"%s\"" % storylet.scene_id,
				path,
				storylet.line,
				storylet.col
			)


func _mark_runs(stage: WyrdStageDef, run: Dictionary) -> void:
	for ref in stage.scenes:
		var scene_id := str(ref["id"])
		if _scenes.has(scene_id):
			run[scene_id] = true
	for variant in stage.variants:
		if variant.body != null:
			_mark_runs(variant.body, run)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_mark_runs(child, run)


func _commands_of(units: Array) -> void:
	var saw := false
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				if _command_stage(stage, path):
					saw = true
		for scene in file.scenes:
			for effect in scene.on_abort:
				if _command(effect, path):
					saw = true
			for item in scene.items:
				if item.choice == null:
					continue
				_skill(item.choice, path)
				for effect in item.choice.effects:
					if _command(effect, path):
						saw = true
	if saw and _commands == null and not _skip_commands_note:
		var path := _note_path
		if path.is_empty() and not units.is_empty():
			path = str(units[0]["path"])
		_diagnostics.add(
			WyrdDiagnostic.I_COMMANDS_SKIPPED,
			"command schemas skipped; no wyrd_commands.json beside the manifest",
			path,
			1,
			1,
			WyrdDiagnostic.SEVERITY_INFO
		)


func _command_stage(stage: WyrdStageDef, path: String) -> bool:
	var saw := false
	for effect in stage.effects:
		if _command(effect, path):
			saw = true
	for variant in stage.variants:
		if variant.body != null and _command_stage(variant.body, path):
			saw = true
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			if _command_stage(child, path):
				saw = true
	return saw


func _skill(choice: WyrdChoiceDef, path: String) -> void:
	if choice.check_skill.is_empty() or _commands == null or not _commands.checks_skills:
		return
	if _commands.has_skill(StringName(choice.check_skill)):
		return
	_diagnostics.add(
		WyrdDiagnostic.E_SKILL_UNKNOWN,
		"unknown skill \"%s\"" % choice.check_skill,
		path,
		choice.check_line,
		choice.check_col
	)


func _command(effect: WyrdEffectDef, path: String) -> bool:
	if effect.kind != &"do":
		return false
	if _commands != null and not _commands.has_command(StringName(effect.command)):
		_diagnostics.add(
			WyrdDiagnostic.E_COMMAND_UNKNOWN,
			"unknown command \"%s\"" % effect.command,
			path,
			effect.line,
			effect.col
		)
	return true


func _topic(effect: WyrdEffectDef, pack: WyrdLinkedPack) -> void:
	if effect.kind != &"unlock_topic" or effect.topic.is_empty():
		return
	if not pack.topics.has(effect.topic):
		pack.topics.append(effect.topic)


func _speakers(scene: WyrdSceneDef) -> Array:
	var rows: Array = []
	for item in scene.items:
		if item.line_def == null:
			continue
		var name := item.line_def.speaker
		if name.is_empty() or name == "narrator" or name.contains("."):
			continue
		rows.append({"col": item.line_def.col, "line": item.line_def.line, "name": name})
	return rows


func _uses(scene: WyrdSceneDef, slot_name: String) -> bool:
	for item in scene.items:
		if item.line_def != null and item.line_def.speaker == slot_name:
			return true
	return false


func _warn_holder_gaps(units: Array) -> void:
	# holder(slot) in prose is safe when the line's when requires filled(slot),
	# or when an empty variant replaces the branch that contains the prose.
	var sites: Dictionary = {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			var slots := _slot_set(quest)
			for stage in quest.stages:
				_holder_stage(stage, {}, slots, path, sites)
	_spread_diverts(sites)
	for scene_id in sites.keys():
		_holder_scene(String(scene_id), sites[scene_id])


func _holder_stage(
	stage: WyrdStageDef,
	inherited: Dictionary,
	slots: Dictionary,
	path: String,
	sites: Dictionary
) -> void:
	if stage == null:
		return
	var excluded := inherited.duplicate()
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.state == &"empty" and slots.has(variant.slot):
			excluded[variant.slot] = true
	var here: Array = [{"excluded": excluded, "slots": slots}]
	for journal in stage.journals:
		_warn_holder_prose(journal.prose, "", here, path)
	for ref in stage.scenes:
		_add_holder_site(sites, str(ref["id"]), excluded, slots)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null or variant.body == null:
			continue
		var child := inherited.duplicate()
		if variant.state == &"empty":
			child.erase(variant.slot)
		else:
			child = excluded.duplicate()
		_holder_stage(variant.body, child, slots, path, sites)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for nested in region.stages:
			_holder_stage(nested, excluded, slots, path, sites)


func _holder_scene(scene_id: String, site_map: Dictionary) -> void:
	if not _scenes.has(scene_id):
		return
	var located: Dictionary = _scenes[scene_id]
	var scene: WyrdSceneDef = located["scene"]
	var path := str(located["path"])
	var sites: Array = site_map.values()
	if sites.is_empty():
		return
	for item in scene.items:
		if item.line_def != null:
			_warn_holder_prose(item.line_def.prose, item.line_def.condition_text, sites, path)
		if item.choice != null:
			_warn_holder_prose(item.choice.label, item.choice.condition_text, sites, path)


func _warn_holder_prose(node: WyrdExprNode, condition: String, sites: Array, path: String) -> void:
	if node == null:
		return
	if node.kind == &"value" and node.payload is WyrdCompiledCondition:
		for slot_name in _holder_slots(node.payload as WyrdCompiledCondition):
			if _holder_exposed(sites, slot_name, condition):
				_diagnostics.add(
					WyrdDiagnostic.W_HOLDER_UNGUARDED,
					"holder(\"%s\") is interpolated where slot \"%s\" can be empty" % [slot_name, slot_name],
					path,
					node.line,
					node.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
	_warn_holder_prose(node.a, condition, sites, path)
	_warn_holder_prose(node.b, condition, sites, path)
	_warn_holder_prose(node.c, condition, sites, path)
	for kid in node.kids:
		_warn_holder_prose(kid, condition, sites, path)


func _holder_exposed(sites: Array, slot_name: String, condition: String) -> bool:
	if _implies_filled(condition, slot_name):
		return false
	for site in sites:
		var slots: Dictionary = site["slots"]
		var excluded: Dictionary = site["excluded"]
		if slots.has(slot_name) and not excluded.has(slot_name):
			return true
	return false


func _implies_filled(expr: String, slot_name: String) -> bool:
	var text := expr.strip_edges()
	if text.is_empty():
		return false
	var unwrapped := _unwrap_parens(text)
	if unwrapped != text:
		return _implies_filled(unwrapped, slot_name)
	var ands := _split_top(text, " and ")
	if ands.size() > 1:
		for part in ands:
			if _implies_filled(part, slot_name):
				return true
		return false
	var ors := _split_top(text, " or ")
	if ors.size() > 1:
		for part in ors:
			if not _implies_filled(part, slot_name):
				return false
		return true
	return text.replace(" ", "") == "filled(%s)" % slot_name


func _unwrap_parens(text: String) -> String:
	if text.length() < 2 or not text.begins_with("(") or not text.ends_with(")"):
		return text
	var depth := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth == 0 and i < text.length() - 1:
				return text
	return text.substr(1, text.length() - 2).strip_edges()


func _split_top(text: String, op: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var depth := 0
	var start := 0
	var i := 0
	while i < text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
			i += 1
			continue
		if ch == ")":
			depth -= 1
			i += 1
			continue
		if depth == 0 and text.substr(i).begins_with(op):
			parts.append(text.substr(start, i - start).strip_edges())
			i += op.length()
			start = i
			continue
		i += 1
	parts.append(text.substr(start).strip_edges())
	return parts


func _holder_slots(compiled: WyrdCompiledCondition) -> PackedStringArray:
	var found := {}
	var stack: Array = []
	var code := compiled.code
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		if op == WyrdOpcodes.PUSH_CONST:
			stack.append(compiled.consts[code[ip]])
			ip += 1
		elif op == WyrdOpcodes.LOAD_FACT:
			stack.append(null)
			ip += 1
		elif op == WyrdOpcodes.PUSH_TRUE or op == WyrdOpcodes.PUSH_FALSE or op == WyrdOpcodes.PUSH_NIL:
			stack.append(null)
		elif op == WyrdOpcodes.LOAD_KEY:
			var count := code[ip]
			ip += 1
			for _i in count:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.NEG or op == WyrdOpcodes.NOT:
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.ADD or op == WyrdOpcodes.SUB or op == WyrdOpcodes.MUL or op == WyrdOpcodes.DIV or op == WyrdOpcodes.EQ or op == WyrdOpcodes.NE or op == WyrdOpcodes.LT or op == WyrdOpcodes.LE or op == WyrdOpcodes.GT or op == WyrdOpcodes.GE:
			if not stack.is_empty():
				stack.pop_back()
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_RANGE:
			for _i in 3:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_SET:
			var count := code[ip]
			ip += 1
			for _i in count + 1:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.CALL:
			var name := String(compiled.consts[code[ip]])
			var argc := code[ip + 1]
			ip += 2
			var args: Array = []
			for _i in argc:
				if stack.is_empty():
					args.append(null)
				else:
					args.push_front(stack.pop_back())
			if name == "holder" and args.size() == 1 and (args[0] is String or args[0] is StringName):
				found[String(args[0])] = true
			stack.append(null)
		elif op == WyrdOpcodes.JUMP:
			ip += 1
		elif op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			if not stack.is_empty():
				stack.pop_back()
			ip += 1
		else:
			break
	var names := PackedStringArray()
	for key in found.keys():
		names.append(String(key))
	names.sort()
	return names


func _add_holder_site(sites: Dictionary, scene_id: String, excluded: Dictionary, slots: Dictionary) -> void:
	if scene_id.is_empty():
		return
	if not sites.has(scene_id):
		sites[scene_id] = {}
	var bag: Dictionary = sites[scene_id]
	var key := "s:%s|e:%s" % [_dict_keys(slots), _dict_keys(excluded)]
	bag[key] = {"excluded": excluded.duplicate(), "slots": slots.duplicate()}


func _spread_diverts(sites: Dictionary) -> void:
	var growing := true
	var guard := 0
	while growing and guard < 32:
		guard += 1
		growing = false
		for scene_id in _scenes.keys():
			if not sites.has(scene_id):
				continue
			var scene: WyrdSceneDef = (_scenes[scene_id] as Dictionary)["scene"]
			for item in scene.items:
				if item.divert_kind != &"scene" or item.target.is_empty():
					continue
				if not sites.has(item.target):
					sites[item.target] = {}
				var dest: Dictionary = sites[item.target]
				var source: Dictionary = sites[scene_id]
				for key in source.keys():
					if dest.has(key):
						continue
					dest[key] = source[key]
					growing = true


func _slot_set(quest: WyrdQuestDef) -> Dictionary:
	var slots := {}
	for slot in quest.slots:
		if not slot.name.is_empty():
			slots[slot.name] = true
	return slots


func _dict_keys(bag: Dictionary) -> String:
	var names: Array = bag.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names:
		parts.append(String(name))
	return ",".join(parts)


func _host_steps(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_host_stage(stage, path)


func _host_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for host in stage.hosts:
		var seen := {}
		var fields: PackedStringArray = host.get("fields", PackedStringArray())
		for field in fields:
			if seen.has(field):
				_diagnostics.add(
					WyrdDiagnostic.E_STMT_UNKNOWN,
					"duplicate await_host field \"%s\"" % field,
					path,
					int(host.get("line", 1)),
					int(host.get("col", 1))
				)
			seen[field] = true
		if String(host.get("screen", "")).is_empty():
			_diagnostics.add(
				WyrdDiagnostic.E_STMT_UNKNOWN,
				"await_host needs a screen id",
				path,
				int(host.get("line", 1)),
				int(host.get("col", 1))
			)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.body != null:
			_host_stage(variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_host_stage(child, path)


static func warn_pressure(pack: WyrdLinkedPack, diagnostics: WyrdDiagnostics, tiers: PackedStringArray) -> void:
	if pack == null or diagnostics == null or tiers.is_empty():
		return
	var rank := {}
	for index in tiers.size():
		rank[String(tiers[index])] = index
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		var path := str(unit["path"])
		for template in file.templates:
			if template.tier_low.is_empty() and not template.tier_range:
				continue
			var low := template.tier_low
			var high := template.tier_high if template.tier_range else ""
			if not low.is_empty() and not rank.has(low):
				diagnostics.add(
					WyrdDiagnostic.W_TEMPLATE_TIER_UNKNOWN,
					"unknown pressure tier \"%s\"" % low,
					path,
					template.line,
					template.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
			if template.tier_range and not high.is_empty() and not rank.has(high):
				diagnostics.add(
					WyrdDiagnostic.W_TEMPLATE_TIER_UNKNOWN,
					"unknown pressure tier \"%s\"" % high,
					path,
					template.line,
					template.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
			if template.tier_range and rank.has(low) and rank.has(high) and int(rank[low]) > int(rank[high]):
				diagnostics.add(
					WyrdDiagnostic.W_TEMPLATE_TIER_ORDER,
					"pressure tier \"%s\" is above \"%s\"" % [low, high],
					path,
					template.line,
					template.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
