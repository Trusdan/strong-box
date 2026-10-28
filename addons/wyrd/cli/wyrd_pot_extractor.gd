class_name WyrdPotExtractor
extends RefCounted

## Gettext rows for one linked pack's player text.
##
## @experimental
## A plain class with no editor API. [method rows] walks dialogue, choices,
## storylet and journal lines, and document titles and paragraphs. A row with
## an empty line id or empty text is skipped. [method render] writes a POT
## with [code]msgctxt[/code] set to the line id and an empty [code]msgstr[/code].


static func rows(pack: WyrdLinkedPack) -> Array:
	var found: Array = []
	if pack == null:
		return found
	for unit in pack.units:
		var path := _display_path(str(unit["path"]))
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_stage(found, stage, path)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_line(found, item.line_def, item.line_def.speaker, path)
				if item.choice != null:
					_choice(found, item.choice, path)
		for story in file.storylets:
			for line_def in story.lines:
				var who := line_def.speaker if not line_def.speaker.is_empty() else story.speaker
				_line(found, line_def, who, path)
		for document in file.documents:
			_document(found, document, path)
	found.sort_custom(_before)
	return found


static func render(pack: WyrdLinkedPack) -> String:
	var blocks := PackedStringArray()
	var pack_id := ""
	if pack != null:
		pack_id = pack.pack_id
	blocks.append(_header(pack_id))
	for row in rows(pack):
		blocks.append(_entry(row))
	return "\n\n".join(blocks) + "\n"


static func _stage(found: Array, stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_line(found, journal, journal.speaker, path)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.body != null:
			_stage(found, variant.body, path)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_stage(found, child, path)


static func _line(found: Array, line: WyrdLineDef, speaker: String, path: String) -> void:
	if line == null:
		return
	_add(found, line.line_id, WyrdLineDef.source_of(line.prose), speaker, path, line.line, line.prose)
	for item in line.variants:
		var variant := item as WyrdLineDef
		if variant == null:
			continue
		_line(found, variant, speaker, path)


static func _choice(found: Array, choice: WyrdChoiceDef, path: String) -> void:
	_add(found, choice.line_id, WyrdLineDef.source_of(choice.label), "", path, choice.line, choice.label)


static func _document(found: Array, document: WyrdDocumentDef, path: String) -> void:
	_add(found, document.line_id, document.title, "", path, document.line, null)
	for page in document.pages:
		var paragraphs: Array = page["paragraphs"]
		for paragraph in paragraphs:
			var prose: WyrdExprNode = paragraph["prose"]
			_add(found, str(paragraph["line_id"]), WyrdLineDef.source_of(prose), "", path, int(paragraph["line"]), prose)


static func _add(
	found: Array,
	line_id: String,
	text: String,
	speaker: String,
	path: String,
	line_no: int,
	prose: Variant
) -> void:
	if prose is WyrdExprNode and WyrdLineDef.has_spans(prose):
		text = WyrdLineDef.template_of(prose)
	if line_id.is_empty() or text.is_empty():
		return
	found.append({
		"line": line_no,
		"msgctxt": line_id,
		"msgid": text,
		"path": path,
		"prose": prose,
		"speaker": speaker,
	})


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if str(a["path"]) != str(b["path"]):
		return str(a["path"]) < str(b["path"])
	if int(a["line"]) != int(b["line"]):
		return int(a["line"]) < int(b["line"])
	return str(a["msgctxt"]) < str(b["msgctxt"])


static func _header(pack_id: String) -> String:
	return "\n".join(PackedStringArray([
		"msgid \"\"",
		"msgstr \"\"",
		"\"Project-Id-Version: %s\\n\"" % _escape(pack_id),
		"\"MIME-Version: 1.0\\n\"",
		"\"Content-Type: text/plain; charset=UTF-8\\n\"",
		"\"Content-Transfer-Encoding: 8bit\\n\"",
		"\"X-Generator: wyrd pot\\n\"",
	]))


static func _entry(row: Dictionary) -> String:
	var lines := PackedStringArray()
	var speaker := str(row["speaker"])
	if not speaker.is_empty():
		lines.append("#. %s" % speaker)
	lines.append("#: %s:%d" % [str(row["path"]), int(row["line"])])
	lines.append("msgctxt \"%s\"" % _escape(str(row["msgctxt"])))
	lines.append("msgid \"%s\"" % _escape(str(row["msgid"])))
	lines.append("msgstr \"\"")
	return "\n".join(lines)


static func _display_path(path: String) -> String:
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	return path


static func _escape(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "\\":
			out += "\\\\"
		elif ch == "\"":
			out += "\\\""
		elif ch == "\t":
			out += "\\t"
		elif ch == "\n":
			out += "\\n"
		else:
			out += ch
	return out
