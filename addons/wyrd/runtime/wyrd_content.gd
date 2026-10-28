class_name WyrdContent
extends RefCounted

## Runtime index of one compiled pack. Built at load. Not a save document.
##
## @experimental
## Quests, scenes, storylets, and lines are the compiler's plain records, keyed by id.
## A storylet [code]when[/code] is compiled and is not added to the tick queue.
## [member conditions] is every gating condition, in source order, with a
## parallel [member records] / [member sites] pair. [code]chance[/code] uses
## [code]<record>:<site>[/code]. [member manifest_hash] folds the pack id and
## each unit hash with [method WyrdHash.combine], paths sorted.
## When [member aliases] is not empty, it also folds [method alias_text].

var pack_id: String = ""
var language_version: int = 1
var manifest_hash: int = 0
var schema: WyrdFactSchema
var events: Dictionary = {}
var quests: Dictionary = {}
## Template id to [WyrdTemplateDef]. Filled by [method from_pack]. Not a save document.
var templates: Dictionary = {}
var scenes: Dictionary = {}
## Role id to [WyrdRoleDef]. Compiled with the pack. Not a save document.
var roles: Dictionary = {}
## Storylet id to [WyrdStoryletDef]. Compiled with the pack. Not a save document.
var storylets: Dictionary = {}
## Sorted ids per scope and speaker. Built at link. Not a save field.
## Null means a director query scans [member storylets] instead.
var storylet_index: WyrdStoryletIndex
## Sequence id to [WyrdSequenceDef]. Compiled with the pack. Not a save document.
var sequences: Dictionary = {}
## Document id to [WyrdDocumentDef]. Compiled with the pack. Not a save document.
var documents: Dictionary = {}
## Topic ids recorded by the linker, including unlock effects. Not a save field.
var topic_ids: PackedStringArray = PackedStringArray()
## Resolved [code]was:[/code] tables copied from the linked pack. Not a save field.
## Load rewrites saved quest stages (and their trail), role ids, deed verbs,
## document ids, periodic publish state, and in-flight rumor verbs through
## these tables. Empty when the pack declared no alias.
var aliases: Dictionary = {}
var lines: Dictionary = {}
## Opted-in line id to [code]owner[/code] ([code]scene[/code] or [code]storylet[/code]),
## owner [code]id[/code], and that owner's [code]ai_context[/code] keys.
## Empty when no line opts in. Not saved.
var ai_lines: Dictionary = {}
## Catalog rows for coverage: [code]kind[/code], [code]id[/code], [code]path[/code], [code]line[/code].
var coverage_sites: Array = []
var files: Array = []
var conditions: Array[WyrdCompiledCondition] = []
var records: PackedStringArray = PackedStringArray()
var sites: PackedStringArray = PackedStringArray()
var deps: WyrdDepIndex
## 1 when the condition has no call and no computed key. Not saved.
var pure: PackedByteArray = PackedByteArray()
var _by_cond: Dictionary = {}
## Call name to condition indexes. Built for the names the tick queue watches.
var _calls: Dictionary = {}
## Event name to spatial [code]waits_until[/code] indexes. Woken on that emit.
var _spatial_waits: Dictionary = {}


static func from_pack(pack: WyrdLinkedPack) -> WyrdContent:
	var content := WyrdContent.new()
	if pack == null:
		content.deps = WyrdDepIndex.new()
		return content
	content.pack_id = pack.pack_id
	content.language_version = pack.language_version
	content.schema = pack.schema
	content.events = pack.events.duplicate()
	content.manifest_hash = hash_pack(pack)
	for unit in pack.units:
		content.files.append({"hash": str(unit["hash"]), "path": str(unit["path"])})
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quests:
			content.quests[quest.id] = quest
			content._add(quest.start_when, quest.id, "start")
			for slot in quest.slots:
				content._add(slot.cast_when, "%s.%s" % [quest.id, slot.name], "cast")
			for stage in quest.stages:
				content._stage(quest.id, stage)
		for template in file.templates:
			if template.id.is_empty():
				continue
			content.templates[template.id] = template
			for slot in template.slots:
				content._add(slot.cast_when, "%s.%s" % [template.id, slot.name], "cast")
			for param in template.params:
				content._add(param.cast_when, "%s.%s" % [template.id, param.name], "cast")
			for stage in template.stages:
				content._stage(template.id, stage)
		for scene in file.scenes:
			content.scenes[scene.id] = scene
			for item in scene.items:
				content._item(scene.id, item)
				if item.line_def != null:
					content._note_ai(item.line_def, "scene", scene.id, scene.ai_context)
		for role in file.roles:
			content.roles[role.id] = role
		for storylet in file.storylets:
			if storylet.id.is_empty():
				continue
			content.storylets[storylet.id] = storylet
			for line_def in storylet.lines:
				content._remember(line_def)
				content._note_ai(line_def, "storylet", storylet.id, storylet.ai_context)
		content._index_coverage(file, str(unit["path"]))
		for sequence in file.sequences:
			if sequence.id.is_empty():
				continue
			content.sequences[sequence.id] = sequence
		for document in file.documents:
			if document.id.is_empty():
				continue
			content.documents[document.id] = document
			content._index_document(document)
	content.deps = WyrdDepIndex.new()
	content.deps.build(content.conditions)
	content._mark_pure()
	content.topic_ids = pack.topics.duplicate()
	content.aliases = pack.aliases.duplicate(true)
	content.storylet_index = pack.storylet_index
	if content.storylet_index == null:
		content.storylet_index = WyrdStoryletIndex.new()
		var stories: Array = []
		for id in content.storylets.keys():
			stories.append(content.storylets[id])
		content.storylet_index.build(stories)
	return content


static func hash_pack(pack: WyrdLinkedPack) -> int:
	if pack == null:
		return 0
	var mixed := WyrdHash.of_string_name(StringName(pack.pack_id))
	var paths := PackedStringArray()
	var hashes := PackedStringArray()
	for unit in pack.units:
		paths.append(str(unit["path"]))
		hashes.append(str(unit["hash"]))
	var order: Array[int] = []
	for i in paths.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return paths[a] < paths[b])
	for i in order:
		mixed = WyrdHash.combine(mixed, _hex_to_int(hashes[i]))
	if pack.aliases != null and not pack.aliases.is_empty():
		mixed = WyrdHash.combine(mixed, WyrdHash.of_text(alias_text(pack.aliases)))
	return mixed


## Canonical text of [param aliases] for [method hash_pack].
## One [code]kind<TAB>scope<TAB>old<TAB>new[/code] line per entry, sorted, with a trailing newline.
## [code]scope[/code] is empty except for a stage, where it is the quest or template id.
static func alias_text(aliases: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var kinds: Array = aliases.keys()
	kinds.sort()
	for kind in kinds:
		var body: Variant = aliases[kind]
		if not (body is Dictionary):
			continue
		var table: Dictionary = body
		if String(kind) == "stage":
			var scopes: Array = table.keys()
			scopes.sort()
			for scope in scopes:
				var rows: Variant = table[scope]
				if not (rows is Dictionary):
					continue
				var mapped: Dictionary = rows
				var olds: Array = mapped.keys()
				olds.sort()
				for old in olds:
					lines.append("%s\t%s\t%s\t%s" % [String(kind), String(scope), String(old), String(mapped[old])])
		else:
			var flat_olds: Array = table.keys()
			flat_olds.sort()
			for old in flat_olds:
				lines.append("%s\t\t%s\t%s" % [String(kind), String(old), String(table[old])])
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


func condition_at(index: int) -> Dictionary:
	if index < 0 or index >= conditions.size():
		return {}
	var reads: PackedStringArray = PackedStringArray()
	for read in conditions[index].reads:
		reads.append(String(read))
	return {"reads": reads, "record": records[index], "site": sites[index]}


func _index_document(document: WyrdDocumentDef) -> void:
	if document.mode != "live" and document.mode != "frozen":
		return
	var page_no := 0
	for page in document.pages:
		page_no += 1
		var page_site := "page.%d" % page_no
		_add(page.get("condition"), document.id, page_site)
		var para_no := 0
		for paragraph in page.get("paragraphs", []):
			para_no += 1
			var line_id := str(paragraph.get("line_id", ""))
			var para_site := line_id if not line_id.is_empty() else "p%d.%d" % [page_no, para_no]
			_add(paragraph.get("condition"), document.id, "paragraph." + para_site)
			var count := {"n": 0}
			_index_prose(paragraph.get("prose"), document.id, para_site, count)


func _index_prose(node: WyrdExprNode, document_id: String, para_site: String, count: Dictionary) -> void:
	if node == null:
		return
	if node.kind == &"if" and node.payload is WyrdCompiledCondition:
		count["n"] = int(count["n"]) + 1
		_add(node.payload, document_id, "if.%s.%d" % [para_site, int(count["n"])])
	_index_prose(node.a, document_id, para_site, count)
	_index_prose(node.b, document_id, para_site, count)
	_index_prose(node.c, document_id, para_site, count)
	for kid in node.kids:
		_index_prose(kid, document_id, para_site, count)


func _stage(quest_id: String, stage: WyrdStageDef) -> void:
	if stage == null:
		return
	var prefix := "%s.%s" % [quest_id, stage.id]
	var wait_index := _add(stage.waits_until, prefix, "waits")
	if wait_index >= 0 and stage.waits_until != null and stage.waits_until.uses_spatial:
		for handler in stage.handlers:
			if handler.event_name.is_empty():
				continue
			_note_spatial(handler.event_name, wait_index)
	for row in stage.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition:
			_add(when, prefix, "transition." + str(row.get("target", "")))
	for journal in stage.journals:
		_remember(journal)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null:
			continue
		if variant.condition != null:
			_add(variant.condition, "%s.%s" % [prefix, variant.slot], "variant." + String(variant.state))
		if variant.body != null:
			_stage(quest_id, variant.body)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_stage(quest_id, child)


func _item(scene_id: String, item: WyrdSceneItem) -> void:
	if item.line_def != null:
		var line := item.line_def
		_remember(line)
		_add(line.condition, line.line_id if not line.line_id.is_empty() else scene_id, "when")
	if item.choice != null:
		var choice := item.choice
		if not choice.line_id.is_empty():
			lines[choice.line_id] = choice
		var record := choice.line_id if not choice.line_id.is_empty() else scene_id
		_add(choice.condition, record, "choice")


func _note_ai(line: WyrdLineDef, owner: String, owner_id: String, keys: PackedStringArray) -> void:
	if line == null or line.line_id.is_empty() or not line.is_ai():
		return
	if line.kind != &"spoken" and line.kind != &"storylet":
		return
	ai_lines[line.line_id] = {
		"id": owner_id,
		"keys": keys.duplicate(),
		"owner": owner,
	}


func _remember(line: WyrdLineDef) -> void:
	if line == null:
		return
	if not line.line_id.is_empty():
		lines[line.line_id] = line
	for item in line.variants:
		var variant := item as WyrdLineDef
		_remember(variant)


func _index_coverage(file: WyrdFileDef, path: String) -> void:
	var seen := {}
	for storylet in file.storylets:
		storylet.source_path = path
		if not storylet.id.is_empty():
			_add_site(seen, "storylet", storylet.id, path, storylet.line)
		for line_def in storylet.lines:
			_index_line(seen, line_def, path)
	for scene in file.scenes:
		for item in scene.items:
			if item.line_def != null:
				_index_line(seen, item.line_def, path)
			if item.choice != null:
				item.choice.source_path = path
				if not item.choice.line_id.is_empty():
					_add_site(seen, "line", item.choice.line_id, path, item.choice.line)
	for quest in file.quest_bodies():
		for stage in quest.stages:
			_index_stage(seen, quest.id, stage, path)


func _index_stage(seen: Dictionary, quest_id: String, stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_index_line(seen, journal, path)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null:
			continue
		variant.source_path = path
		var id := "%s.%s.%s.%s" % [quest_id, stage.id, variant.slot, String(variant.state)]
		_add_site(seen, "variant", id, path, variant.line)
		_index_stage(seen, quest_id, variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_index_stage(seen, quest_id, child, path)


func _index_line(seen: Dictionary, line: WyrdLineDef, path: String) -> void:
	if line == null:
		return
	line.source_path = path
	if not line.line_id.is_empty():
		_add_site(seen, "line", line.line_id, path, line.line)
	for item in line.variants:
		_index_line(seen, item as WyrdLineDef, path)


func _add_site(seen: Dictionary, kind: String, id: String, path: String, line_no: int) -> void:
	if id.is_empty():
		return
	var key := "%s\t%s" % [kind, id]
	if seen.has(key):
		return
	seen[key] = true
	coverage_sites.append({"id": id, "kind": kind, "line": line_no, "path": path})


func is_pure(index: int) -> bool:
	return index >= 0 and index < pure.size() and pure[index] != 0


## [param names] are the call spellings [method WyrdRuntime] marks dirty.
func index_calls(names: PackedStringArray) -> void:
	_calls.clear()
	var want := {}
	for name in names:
		want[String(name)] = true
	if want.is_empty():
		return
	for i in conditions.size():
		var cond := conditions[i]
		if cond == null:
			continue
		var found := {}
		for item in cond.consts:
			if not (item is StringName):
				continue
			var text := String(item)
			if not want.has(text) or found.has(text):
				continue
			found[text] = true
			var rows := PackedInt32Array()
			if _calls.has(text):
				rows = _calls[text]
			rows.append(i)
			_calls[text] = rows


## Condition indexes that name one of [param names], in first-seen order.
func indexes_for_calls(names: PackedStringArray) -> PackedInt32Array:
	var seen := {}
	var hits := PackedInt32Array()
	for name in names:
		var key := String(name)
		if not _calls.has(key):
			continue
		var rows: PackedInt32Array = _calls[key]
		for index in rows:
			var at := int(index)
			if seen.has(at):
				continue
			seen[at] = true
			hits.append(at)
	return hits


func _mark_pure() -> void:
	pure = PackedByteArray()
	pure.resize(conditions.size())
	for i in conditions.size():
		pure[i] = 1 if _condition_pure(conditions[i]) else 0


func _condition_pure(cond: WyrdCompiledCondition) -> bool:
	if cond == null or cond.uses_chance:
		return false
	var code := cond.code
	var ip := 0
	while ip < code.size():
		var op := int(code[ip])
		if op == WyrdOpcodes.CALL or op == WyrdOpcodes.LOAD_KEY:
			return false
		if op == WyrdOpcodes.PUSH_CONST or op == WyrdOpcodes.LOAD_FACT or op == WyrdOpcodes.IN_SET or op == WyrdOpcodes.JUMP or op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			ip += 2
		else:
			ip += 1
	return true


## A quest id, or the template behind [code]<template>#<n>[/code].
## Quests win when an id is in both tables.
func quest_def(id: String) -> WyrdQuestDef:
	if quests.has(id):
		return quests[id] as WyrdQuestDef
	var mark := id.find("#")
	if mark <= 0:
		return null
	return templates.get(id.substr(0, mark)) as WyrdQuestDef


func index_of(cond: WyrdCompiledCondition) -> int:
	if cond == null:
		return -1
	var key := cond.get_instance_id()
	if not _by_cond.has(key):
		return -1
	return int(_by_cond[key])


func spatial_waits(event_name: StringName) -> PackedInt32Array:
	var key := String(event_name)
	if not _spatial_waits.has(key):
		return PackedInt32Array()
	return _spatial_waits[key]


func _note_spatial(event_name: String, index: int) -> void:
	var rows := PackedInt32Array()
	if _spatial_waits.has(event_name):
		rows = _spatial_waits[event_name]
	rows.append(index)
	_spatial_waits[event_name] = rows


func _add(cond: WyrdCompiledCondition, record: String, site: String) -> int:
	if cond == null:
		return -1
	var index := conditions.size()
	_by_cond[cond.get_instance_id()] = index
	conditions.append(cond)
	records.append(record)
	sites.append(site)
	return index


static func _hex_to_int(hex: String) -> int:
	if hex.is_empty():
		return 0
	var value := 0
	for i in hex.length():
		var code := hex.unicode_at(i)
		var nibble := -1
		if code >= 48 and code <= 57:
			nibble = code - 48
		elif code >= 97 and code <= 102:
			nibble = code - 87
		elif code >= 65 and code <= 70:
			nibble = code - 55
		if nibble < 0:
			return WyrdHash.of_string_name(StringName(hex))
		value = (value << 4) | nibble
	return value
