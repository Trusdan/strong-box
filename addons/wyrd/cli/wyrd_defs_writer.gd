class_name WyrdDefsWriter
extends RefCounted

## Sorted Exuberant-ctags tags for one linked pack.
##
## @experimental
## Kinds are quest [code]q[/code], template [code]p[/code], stage [code]s[/code],
## scene [code]g[/code], role [code]r[/code], storylet [code]t[/code], document
## [code]d[/code], and fact [code]f[/code]. Each stage is listed as
## [code]quest.stage[/code] or [code]template.stage[/code] and as its bare id.
## Variant bodies are not stages. Events and sequences are omitted.
## The text depends only on the pack.


static func render(pack: WyrdLinkedPack) -> String:
	var rows: Array = []
	if pack != null:
		_collect(pack, rows)
	rows.sort_custom(_before)
	var lines := PackedStringArray()
	lines.append("!_TAG_FILE_FORMAT\t2\t//")
	lines.append("!_TAG_FILE_SORTED\t1\t//")
	lines.append("!_TAG_PROGRAM_NAME\twyrd defs\t//")
	var previous := ""
	for row in rows:
		var line := "%s\t%s\t%d;\"\t%s" % [str(row["name"]), str(row["file"]), int(row["line"]), str(row["kind"])]
		if line == previous:
			continue
		previous = line
		lines.append(line)
	return "\n".join(lines) + "\n"


static func _collect(pack: WyrdLinkedPack, rows: Array) -> void:
	for unit in pack.units:
		var path := _file(str(unit["path"]))
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quests:
			_add(rows, quest.id, path, quest.line, "q")
			for stage in quest.stages:
				_stage(rows, quest.id, stage, path)
		for template in file.templates:
			_add(rows, template.id, path, template.line, "p")
			for stage in template.stages:
				_stage(rows, template.id, stage, path)
		for scene in file.scenes:
			_add(rows, scene.id, path, scene.line, "g")
		for role in file.roles:
			_add(rows, role.id, path, role.line, "r")
		for storylet in file.storylets:
			_add(rows, storylet.id, path, storylet.line, "t")
		for document in file.documents:
			_add(rows, document.id, path, document.line, "d")
	if pack.xref == null:
		return
	for fact in pack.xref.facts:
		_add(rows, str(fact["key"]), _file(str(fact["file"])), int(fact["line"]), "f")


static func _stage(rows: Array, quest_id: String, stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	if not stage.id.is_empty():
		if not quest_id.is_empty():
			_add(rows, "%s.%s" % [quest_id, stage.id], path, stage.line, "s")
		_add(rows, stage.id, path, stage.line, "s")
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_stage(rows, quest_id, child, path)


static func _add(rows: Array, name: String, path: String, line: int, kind: String) -> void:
	if name.is_empty():
		return
	rows.append({"file": path, "kind": kind, "line": line, "name": name})


static func _file(path: String) -> String:
	var text := path.replace("\\", "/")
	if text.begins_with("res://"):
		return text.substr(6)
	return text


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var a_name := str(a["name"])
	var b_name := str(b["name"])
	if a_name != b_name:
		return a_name < b_name
	var a_file := str(a["file"])
	var b_file := str(b["file"])
	if a_file != b_file:
		return a_file < b_file
	if int(a["line"]) != int(b["line"]):
		return int(a["line"]) < int(b["line"])
	return str(a["kind"]) < str(b["kind"])
