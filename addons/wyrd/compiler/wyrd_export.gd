class_name WyrdExport
extends RefCounted

## Debug JSON for a linked pack. Not the runtime load format.
##
## @experimental
## Keys are sorted. A second export of the same pack is byte-identical.
## Line ids are exported as [code]<pack>/<id>[/code].

const VERSION := 1


static func hash_text(text: String) -> String:
	return _hex64(WyrdHash.of_string_name(StringName(text)))


static func to_data(pack: WyrdLinkedPack) -> Dictionary:
	if pack == null:
		return {}
	var files: Array = []
	for unit in pack.units:
		files.append({"hash": str(unit["hash"]), "path": str(unit["path"])})
	var xref := {}
	if pack.xref != null:
		xref = pack.xref.to_data()
	var data := {
		"events": _events(pack),
		"facts": _facts(pack),
		"files": files,
		"language_version": pack.language_version,
		"lines": _lines(pack),
		"pack_id": pack.pack_id,
		"quests": _quests(pack),
		"roles": _roles(pack),
		"scenes": _scenes(pack),
		"wyrd_export": VERSION,
		"xref": xref,
	}
	var storylets := _storylets(pack)
	if not storylets.is_empty():
		data["storylets"] = storylets
	var sequences := _sequences(pack)
	if not sequences.is_empty():
		data["sequences"] = sequences
	var documents := _documents(pack)
	if not documents.is_empty():
		data["documents"] = documents
	var templates := _templates(pack)
	if not templates.is_empty():
		data["templates"] = templates
	if pack.aliases != null and not pack.aliases.is_empty():
		data["aliases"] = pack.aliases
	return data


static func to_json(data: Dictionary) -> String:
	return _encode(data, 0) + "\n"


static func xref_json(pack: WyrdLinkedPack) -> String:
	var xref := {}
	if pack != null and pack.xref != null:
		xref = pack.xref.to_data()
	return to_json(xref)


static func _events(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	var names: Array = pack.events.keys()
	names.sort()
	for name in names:
		var event: WyrdEventDef = pack.events[name]
		if event == null:
			continue
		var fields: Array = []
		for field in event.fields:
			fields.append({"name": str(field.get("name", "")), "type": str(field.get("type", ""))})
		var row := {
			"fields": fields,
			"line": event.line,
			"name": event.name,
		}
		if not event.leaves_key.is_empty():
			var leaves := {"key": event.leaves_key, "value": event.leaves_value}
			if event.decays_minutes > 0:
				leaves["decays"] = event.decays_minutes
			row["leaves"] = leaves
		rows.append(row)
	return rows


static func _handlers(stage: WyrdStageDef) -> Array:
	var rows: Array = []
	if stage == null:
		return rows
	for handler in stage.handlers:
		var transitions: Array = []
		for row in handler.transitions:
			transitions.append({"target": str(row.get("target", "")), "when": str(row.get("expr", ""))})
		rows.append({
			"effects": _effects(handler.effects),
			"event": handler.event_name,
			"transitions": transitions,
			"where": handler.where_text,
		})
	return rows


static func _facts(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack.schema == null:
		return rows
	for fact in pack.schema.entries:
		var row := {
			"doc": fact.doc,
			"invalidate": String(fact.invalidate),
			"invalidate_arg": fact.invalidate_arg,
			"key": fact.key,
			"line": fact.line,
			"origin": String(fact.origin),
			"pattern": fact.is_pattern(),
			"resolver": fact.resolver,
			"source": fact.resolver if fact.origin == &"resolved" else "stored",
			"type": String(fact.type_name),
		}
		if fact.recap:
			row["recap"] = true
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["key"]) < str(b["key"]))
	return rows


static func _quests(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			var slots: Array = []
			for slot in quest.slots:
				var slot_row := {
					"locked_stage": slot.locked_stage,
					"mode": String(slot.mode),
					"name": slot.name,
					"role": slot.role,
				}
				if not slot.kind.is_empty():
					slot_row["cast_tag"] = slot.cast_tag
					slot_row["kind"] = slot.kind
				slots.append(slot_row)
			var stages: Array = []
			for stage in quest.stages:
				stages.append(_stage(stage))
			var row := {
				"file": str(unit["path"]),
				"id": quest.id,
				"on_empty": quest.on_empty,
				"requires": _strings(quest.requires),
				"slots": slots,
				"stages": stages,
				"start": _cond(quest.start_when),
				"title": quest.title,
			}
			if not quest.on_missing_stage.is_empty():
				row["on_missing_stage"] = quest.on_missing_stage
			rows.append(row)
	return rows


static func _templates(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for template in file.templates:
			var slots: Array = []
			for slot in template.slots:
				var slot_row := {
					"locked_stage": slot.locked_stage,
					"mode": String(slot.mode),
					"name": slot.name,
					"role": slot.role,
				}
				if not slot.kind.is_empty():
					slot_row["cast_tag"] = slot.cast_tag
					slot_row["kind"] = slot.kind
				slots.append(slot_row)
			var params: Array = []
			for param in template.params:
				params.append({
					"cast_tag": param.cast_tag,
					"cast_text": param.cast_text,
					"kind": param.kind,
					"name": param.name,
				})
			var stages: Array = []
			for stage in template.stages:
				stages.append(_stage(stage))
			var hooks: Array = []
			for hook in template.deed_hooks:
				hooks.append({"verb": hook.verb, "where": hook.where_text})
			var row := {
				"allow_protected": template.allow_protected,
				"assumes": template.assumes_text,
				"file": str(unit["path"]),
				"id": template.id,
				"max_active": template.max_active,
				"on_empty": template.on_empty,
				"params": params,
				"priority": template.priority,
				"requires": _strings(template.requires),
				"slots": slots,
				"specificity": template.specificity,
				"stages": stages,
				"tier_high": template.tier_high,
				"tier_low": template.tier_low,
				"tier_range": template.tier_range,
				"title": template.title,
				"weight": template.weight,
				"when": template.when_text,
			}
			if not template.on_missing_stage.is_empty():
				row["on_missing_stage"] = template.on_missing_stage
			if not hooks.is_empty():
				row["on_deed"] = hooks
			rows.append(row)
	return rows


static func _stage(stage: WyrdStageDef) -> Dictionary:
	var scenes: Array = []
	for ref in stage.scenes:
		var with_names: Array = []
		for entry in ref["with"]:
			with_names.append(str(entry["name"]))
		scenes.append({"id": str(ref["id"]), "with": with_names})
	var transitions: Array = []
	for row in stage.transitions:
		transitions.append({"target": str(row["target"]), "when": str(row["expr"])})
	var journals: Array = []
	for journal in stage.journals:
		journals.append(journal.line_id)
	var variants: Array = []
	for variant in stage.variants:
		variants.append({
			"body": _stage(variant.body) if variant.body != null else {},
			"slot": variant.slot,
			"state": String(variant.state),
		})
	var data := {
		"effects": _effects(stage.effects),
		"id": stage.id,
		"journals": journals,
		"scenes": scenes,
		"transitions": transitions,
		"variants": variants,
		"waits": stage.waits_text,
	}
	var handlers := _handlers(stage)
	if not handlers.is_empty():
		data["handlers"] = handlers
	var regions := _regions(stage)
	if not regions.is_empty():
		data["regions"] = regions
	if stage.hosts.size() > 0:
		var hosts: Array = []
		for host in stage.hosts:
			var fields: Array = []
			var packed: PackedStringArray = host.get("fields", PackedStringArray())
			for field in packed:
				fields.append(String(field))
			hosts.append({"fields": fields, "screen": String(host.get("screen", ""))})
		data["hosts"] = hosts
	return data


static func _regions(stage: WyrdStageDef) -> Array:
	var rows: Array = []
	if stage == null:
		return rows
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		var stages: Array = []
		for child in region.stages:
			stages.append(_stage(child))
		rows.append({"id": region.id, "stages": stages})
	return rows


static func _sequences(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for sequence in file.sequences:
			var steps: Array = []
			for step in sequence.steps:
				steps.append({"event": step.event_name, "where": step.where_text})
			rows.append({
				"file": str(unit["path"]),
				"id": sequence.id,
				"mode": String(sequence.mode),
				"need": sequence.need,
				"of": sequence.total,
				"reset": sequence.reset_text,
				"steps": steps,
				"within": sequence.within_minutes,
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


static func _roles(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for role in file.roles:
			var kinds: Array = []
			for kind in role.kinds:
				kinds.append(String(kind))
			rows.append({
				"default_holder": role.default_holder,
				"eligibility": role.eligibility_text,
				"file": str(unit["path"]),
				"id": role.id,
				"kinds": kinds,
				"scope": role.scope,
				"scope_id": role.scope_id,
				"strategy": role.strategy,
				"succession": role.succession_text,
				"succession_arg": role.succession_arg,
				"vacancy": role.vacancy,
				"visibility": role.visibility,
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s\t%s" % [str(a["id"]), str(a["file"])]
		var right := "%s\t%s" % [str(b["id"]), str(b["file"])]
		return left < right
	)
	return rows


static func _scenes(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			var items: Array = []
			for item in scene.items:
				items.append(_item(item))
			var row := {
				"file": str(unit["path"]),
				"id": scene.id,
				"items": items,
				"on_abort": _effects(scene.on_abort),
			}
			if not scene.ai_context.is_empty():
				row["ai_context"] = _strings(scene.ai_context)
			rows.append(row)
	return rows


static func _item(item: WyrdSceneItem) -> Dictionary:
	var data := {
		"divert": String(item.divert_kind),
		"kind": String(item.kind),
		"label": item.label,
		"target": item.target,
	}
	if item.line_def != null:
		data["line_id"] = item.line_def.line_id
		data["speaker"] = item.line_def.speaker
	if item.choice != null:
		data["choice_id"] = item.choice.line_id
		data["effects"] = _effects(item.choice.effects)
		data["target"] = item.choice.target
		if not item.choice.disabled_when.is_empty():
			data["show_disabled_when"] = item.choice.disabled_when
		if not item.choice.disabled_reason.is_empty():
			data["disabled_reason"] = item.choice.disabled_reason
		if not item.choice.check_skill.is_empty():
			var check_args: Array = []
			for arg in item.choice.check_args:
				check_args.append({"name": str(arg["name"]), "text": str(arg["text"])})
			data["check"] = {
				"args": check_args,
				"on_fail": item.choice.check_on_fail,
				"skill": item.choice.check_skill,
			}
	if item.effect != null:
		var rows := _effects([item.effect])
		if not rows.is_empty():
			data["effect"] = rows[0]
	return data


static func _storylets(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for story in file.storylets:
			var line_ids: Array = []
			for line_def in story.lines:
				line_ids.append(line_def.line_id)
			var row := {
				"body": String(story.body_kind),
				"cooldown": story.cooldown_minutes,
				"file": str(unit["path"]),
				"generic": story.generic,
				"id": story.id,
				"line_ids": line_ids,
				"priority": story.priority,
				"scene": story.scene_id,
				"scope": story.scope_text(),
				"speaker": story.speaker,
				"speaker_cooldown": story.speaker_cooldown_minutes,
				"specificity": story.specificity,
				"weight": story.weight,
				"when": story.when_text,
			}
			if not story.secrecy.is_empty():
				row["secrecy"] = story.secrecy
			if not story.ai_context.is_empty():
				row["ai_context"] = _strings(story.ai_context)
			if not story.effects.is_empty():
				row["effects"] = _effects(story.effects)
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


static func _lines(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	for unit in pack.units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_line_stage(rows, stage, path, pack.pack_id)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					rows.append(_line_row(item.line_def.line_id, "spoken", path, pack.pack_id, scene.id, item.line_def.speaker, item.line_def.condition, item.line_def.tags, item.line_def.secrecy))
					_append_variants(rows, item.line_def, path, pack.pack_id, scene.id)
				if item.choice != null and not item.choice.line_id.is_empty():
					rows.append(_line_row(item.choice.line_id, "choice", path, pack.pack_id, scene.id, "", item.choice.condition, item.choice.tags, item.choice.secrecy))
		for story in file.storylets:
			for line_def in story.lines:
				rows.append(_line_row(line_def.line_id, "storylet", path, pack.pack_id, "", line_def.speaker, null, line_def.tags, line_def.secrecy))
				_append_variants(rows, line_def, path, pack.pack_id, "")
	return rows


static func _line_stage(rows: Array, stage: WyrdStageDef, path: String, pack_id: String) -> void:
	for journal in stage.journals:
		rows.append(_line_row(journal.line_id, "journal", path, pack_id, "", "", journal.condition, journal.tags, journal.secrecy))
		_append_variants(rows, journal, path, pack_id, "")
	for variant in stage.variants:
		if variant.body != null:
			_line_stage(rows, variant.body, path, pack_id)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_line_stage(rows, child, path, pack_id)


static func _append_variants(rows: Array, line: WyrdLineDef, path: String, pack_id: String, scene_id: String) -> void:
	if line == null:
		return
	for item in line.variants:
		var variant := item as WyrdLineDef
		if variant == null:
			continue
		var row := _line_row(variant.line_id, "variant", path, pack_id, scene_id, variant.speaker, null, variant.tags, variant.secrecy)
		row["holder"] = variant.holder
		rows.append(row)


static func _line_row(
	local_id: String,
	kind: String,
	path: String,
	pack_id: String,
	scene_id: String,
	speaker: String,
	condition: WyrdCompiledCondition,
	tags: PackedStringArray,
	secrecy: String = ""
) -> Dictionary:
	var row := {
		"condition": _cond(condition),
		"file": path,
		"id": "%s/%s" % [pack_id, local_id],
		"kind": kind,
		"scene": scene_id,
		"speaker": speaker,
		"tags": _strings(tags),
	}
	if not secrecy.is_empty():
		row["secrecy"] = secrecy
	return row


static func _documents(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for document in file.documents:
			if document.mode != "live" and document.mode != "frozen":
				continue
			var pages: Array = []
			for page in document.pages:
				var paragraphs: Array = []
				for paragraph in page.get("paragraphs", []):
					var para := {
						"id": str(paragraph.get("line_id", "")),
						"when": str(paragraph.get("condition_text", "")),
					}
					var secrecy := str(paragraph.get("secrecy", ""))
					if not secrecy.is_empty():
						para["secrecy"] = secrecy
					var tags: PackedStringArray = paragraph.get("tags", PackedStringArray())
					if not tags.is_empty():
						para["tags"] = _strings(tags)
					paragraphs.append(para)
				pages.append({
					"paragraphs": paragraphs,
					"when": str(page.get("condition_text", "")),
				})
			var row := {
				"id": document.id,
				"meta": document.meta.duplicate(true),
				"mode": document.mode,
				"on_first_read": _effects(document.on_first_read),
				"on_read": _effects(document.on_read),
				"pages": pages,
				"tags": _strings(document.tags),
				"title_id": document.line_id,
			}
			if not document.secrecy.is_empty():
				row["secrecy"] = document.secrecy
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


static func _effects(effects: Array) -> Array:
	var rows: Array = []
	for effect in effects:
		var args: Array = []
		for arg in effect.args:
			args.append({"name": str(arg["name"]), "text": str(arg["text"])})
		var row := {
			"agent": effect.agent,
			"args": args,
			"branch": effect.branch,
			"command": effect.command,
			"fact_key": effect.fact_key,
			"kind": String(effect.kind),
			"on_fail": effect.on_fail,
			"outcome": effect.outcome,
			"target": _cond(effect.target),
			"topic": effect.topic,
			"value": _cond(effect.value),
			"verb": effect.verb,
		}
		if effect.kind == &"start_quest" or effect.kind == &"advance":
			row["quest"] = effect.quest
		if effect.kind == &"advance":
			row["stage"] = effect.stage
		if effect.kind == &"assign_role" or effect.kind == &"vacate_role":
			row["role"] = effect.role
		if effect.kind == &"assign_role":
			row["entity"] = _cond(effect.entity)
		if effect.kind == &"adjust_baseline":
			row["a"] = _cond(effect.a)
			row["axis"] = effect.axis
			row["b"] = _cond(effect.b)
		if effect.kind == &"create_document":
			row["copy"] = effect.copy_id
			row["document"] = effect.document_id
		rows.append(row)
	return rows


static func _cond(cond: WyrdCompiledCondition) -> Variant:
	if cond == null:
		return null
	var code: Array = []
	for op in cond.code:
		code.append(int(op))
	var consts: Array = []
	for item in cond.consts:
		consts.append(_const(item))
	var reads: Array = []
	for read in cond.reads:
		reads.append(String(read))
	return {
		"code": code,
		"consts": consts,
		"reads": reads,
		"specificity": cond.specificity,
		"uses_chance": cond.uses_chance,
	}


static func _const(item: Variant) -> Dictionary:
	if item is bool:
		return {"t": "bool", "v": item}
	if item is int:
		return {"t": "int", "v": item}
	if item is float:
		return {"t": "float", "v": item}
	return {"t": "name", "v": String(item)}


static func _strings(values: PackedStringArray) -> Array:
	var rows: Array = []
	for item in values:
		rows.append(item)
	return rows


static func _hex64(value: int) -> String:
	var digits := "0123456789abcdef"
	var out := ""
	var bits := value
	for _i in 16:
		out = digits[bits & 0xF] + out
		bits >>= 4
	return out


static func _encode(value: Variant, indent: int) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int and not value is float:
		return str(value)
	if value is float:
		return _float(value)
	if value is String:
		return _string(value)
	if value is Array:
		return _array(value, indent)
	if value is Dictionary:
		return _dict(value, indent)
	return _string(str(value))


static func _float(value: float) -> String:
	if is_nan(value) or is_inf(value):
		return "null"
	return str(value)


static func _dict(dict: Dictionary, indent: int) -> String:
	var keys: PackedStringArray = PackedStringArray()
	for key in dict.keys():
		keys.append(str(key))
	keys.sort()
	if keys.is_empty():
		return "{}"
	var pad := "  ".repeat(indent + 1)
	var lines: PackedStringArray = PackedStringArray()
	for i in keys.size():
		var key := keys[i]
		var line := "%s%s: %s" % [pad, _string(key), _encode(dict[key], indent + 1)]
		if i < keys.size() - 1:
			line += ","
		lines.append(line)
	return "{\n" + "\n".join(lines) + "\n" + "  ".repeat(indent) + "}"


static func _array(items: Array, indent: int) -> String:
	if items.is_empty():
		return "[]"
	var pad := "  ".repeat(indent + 1)
	var lines: PackedStringArray = PackedStringArray()
	for i in items.size():
		var line := "%s%s" % [pad, _encode(items[i], indent + 1)]
		if i < items.size() - 1:
			line += ","
		lines.append(line)
	return "[\n" + "\n".join(lines) + "\n" + "  ".repeat(indent) + "]"


static func _string(value: String) -> String:
	var out := "\""
	for i in value.length():
		var ch := value[i]
		var code := value.unicode_at(i)
		if ch == "\\":
			out += "\\\\"
		elif ch == "\"":
			out += "\\\""
		elif ch == "\n":
			out += "\\n"
		elif ch == "\r":
			out += "\\r"
		elif ch == "\t":
			out += "\\t"
		elif code < 32:
			out += "\\u%04x" % code
		else:
			out += ch
	return out + "\""
