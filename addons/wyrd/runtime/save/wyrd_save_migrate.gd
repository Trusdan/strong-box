class_name WyrdSaveMigrate
extends RefCounted

## Rewrites saved ids through a pack's resolved [code]was:[/code] tables.
##
## @experimental
## [method apply_aliases] is pure. It does not change [param doc] or
## [param aliases], and it does not read a runtime, a config, a clock, or an
## RNG. The same inputs always return the same document, rows, and diagnostics.
## Empty tables return [param doc] itself and no rows. A second call on the
## returned document adds no rows: chains are already resolved, so one lookup
## is the final id.
##
## The return value is [code]doc[/code] (a rewritten copy, or [param doc] when
## nothing changed), [code]rows[/code], and [code]diagnostics[/code]. Each row
## matches [method WyrdLoadReport.add_row]: [code]kind[/code] is [code]alias[/code],
## [code]id[/code] is [code]stage:<quest row id>[/code], [code]trail:<quest row id>:<old>[/code],
## [code]role:<old>[/code], [code]document:<old>[/code], or [code]verb:<old>[/code],
## [code]from[/code] is the old id, and [code]to[/code] is the final id. A rewrite
## row has an empty [code]code[/code]. A dropped old id has [code]W_SAVE_ALIAS[/code].
## [code]count[/code] is how many saved entries were rewritten or dropped.
## Each diagnostic is [code]code[/code], [code]message[/code], and
## [code]severity[/code] ([code]warning[/code]).


static func apply_aliases(doc: Dictionary, aliases: Dictionary) -> Dictionary:
	if not _has_table(aliases):
		return _none(doc)
	if not _aliases_touch(doc, aliases):
		return _none(doc)
	var copy: Dictionary = doc.duplicate(true)
	var rewrites: Dictionary = {}
	var drops: Dictionary = {}
	_rewrite_stages(copy, _kind(aliases, "stage"), rewrites)
	_rewrite_roles(copy, _kind(aliases, "role"), rewrites, drops)
	_rewrite_verbs(copy, _kind(aliases, "verb"), rewrites)
	_rewrite_documents(copy, _kind(aliases, "document"), rewrites, drops)
	if rewrites.is_empty() and drops.is_empty():
		return _none(doc)
	return {
		"diagnostics": _diagnostics(drops),
		"doc": copy,
		"rows": _rows(rewrites, drops),
	}


## Moves a quest off a stage the content no longer has, and restarts a region
## whose leaf is gone. Pure: it does not change [param doc] or [param content],
## and it does not read a runtime, a config, a clock, or an RNG. A refused load
## never calls it. A second call on the returned document adds no rows.
##
## The new stage is [code]on_missing_stage[/code], else the last [code]trail[/code]
## entry that is still a stage, else the first declared stage. The row arrives
## entered, with entry steps already counted, so nothing runs. Each move adds
## one [code]missing_stage[/code] row and one [code]W_SAVE_STAGE[/code] warning.
static func resolve_stages(doc: Dictionary, content: WyrdContent) -> Dictionary:
	if content == null:
		return _none(doc)
	var quests: Variant = doc.get("quests", {})
	if not (quests is Dictionary) or (quests as Dictionary).is_empty():
		return _none(doc)
	if not _stages_move(quests as Dictionary, content):
		return _none(doc)
	var copy: Dictionary = doc.duplicate(true)
	var block: Dictionary = copy["quests"]
	var ids: Array = block.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var rows: Array = []
	for quest_id in ids:
		var item: Variant = block[quest_id]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var stage_id := str(row.get("stage", ""))
		if stage_id.is_empty():
			continue
		var quest := _quest_def(content, String(quest_id), row)
		if quest == null:
			continue
		var names := _stage_names(quest)
		if not names.has(stage_id):
			var target := _fallback_stage(quest, row, names)
			if target.is_empty():
				continue
			var moved_from := stage_id
			_arrive(row, quest, target)
			_note_move(rows, String(quest_id), moved_from, target)
			stage_id = target
		var stage := _top_stage(quest, stage_id)
		var body := WyrdQuestRunner.stage_body(stage, str(row.get("variant", "")))
		var packed: Variant = row.get("regions", null)
		if body != null and packed is Dictionary:
			_repair_regions(String(quest_id), body, packed, "", rows)
	if rows.is_empty():
		return _none(doc)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a := String(a.get("id", ""))
		var id_b := String(b.get("id", ""))
		if id_a != id_b:
			return id_a < id_b
		return String(a.get("code", "")) < String(b.get("code", ""))
	)
	var notes: Array = []
	for moved in rows:
		var body_row: Dictionary = moved
		notes.append({
			"code": String(WyrdDiagnostic.W_SAVE_STAGE),
			"message": "saved stage \"%s\" of \"%s\" is gone; moved to \"%s\"" % [String(body_row.get("from", "")), String(body_row.get("id", "")), String(body_row.get("to", ""))],
			"severity": "warning",
		})
	return {"diagnostics": notes, "doc": copy, "rows": rows}


static func _none(doc: Dictionary) -> Dictionary:
	return {"diagnostics": [], "doc": doc, "rows": []}


## True when the rewrite below would return a row. A miss would drop a rewrite,
## so an uncertain id counts as a touch and the copy still runs.
static func _aliases_touch(doc: Dictionary, aliases: Dictionary) -> bool:
	if _stages_touch(doc, _kind(aliases, "stage")):
		return true
	if _roles_touch(doc, _kind(aliases, "role")):
		return true
	if _verbs_touch(doc, _kind(aliases, "verb")):
		return true
	return _documents_touch(doc, _kind(aliases, "document"))


static func _stages_touch(doc: Dictionary, tables: Dictionary) -> bool:
	if tables.is_empty():
		return false
	var quests: Variant = doc.get("quests", {})
	if not (quests is Dictionary):
		return false
	var block: Dictionary = quests
	for quest_id in block.keys():
		var item: Variant = block[quest_id]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var found: Variant = tables.get(_stage_scope(String(quest_id), row), {})
		if not (found is Dictionary):
			continue
		var table: Dictionary = found
		if not _mapped(table, str(row.get("stage", ""))).is_empty():
			return true
		if _trail_touch(row, table):
			return true
	return false


static func _trail_touch(row: Dictionary, table: Dictionary) -> bool:
	var trail_raw: Variant = row.get("trail", null)
	if not (trail_raw is Array):
		return false
	for entry in trail_raw:
		if not _mapped(table, str(entry)).is_empty():
			return true
	return false


static func _roles_touch(doc: Dictionary, table: Dictionary) -> bool:
	if table.is_empty():
		return false
	var roles: Variant = doc.get("roles", {})
	if not (roles is Dictionary):
		return false
	var block: Dictionary = roles
	for name in ["bindings", "defs", "pending", "told"]:
		var bag: Variant = block.get(name, {})
		if not (bag is Dictionary):
			continue
		for key in (bag as Dictionary).keys():
			if not _mapped(table, String(key)).is_empty():
				return true
	var abolished: Variant = block.get("abolished", [])
	if abolished is Array:
		for item in abolished:
			if not _mapped(table, str(item)).is_empty():
				return true
	return false


static func _verbs_touch(doc: Dictionary, table: Dictionary) -> bool:
	if table.is_empty():
		return false
	var deeds: Variant = doc.get("deeds", {})
	if deeds is Dictionary:
		var rows: Variant = (deeds as Dictionary).get("rows", [])
		if rows is Array and _verb_rows_touch(rows, table):
			return true
	var flight: Variant = doc.get("flight", {})
	if not (flight is Dictionary):
		return false
	var rumor: Variant = (flight as Dictionary).get("rumor", {})
	if not (rumor is Dictionary):
		return false
	var block: Dictionary = rumor
	if block.get("jobs") is Array and _verb_rows_touch(block["jobs"], table):
		return true
	if block.get("reach") is Array and _verb_rows_touch(block["reach"], table):
		return true
	return false


static func _verb_rows_touch(rows: Array, table: Dictionary) -> bool:
	for item in rows:
		if not (item is Dictionary):
			continue
		if not _mapped(table, str((item as Dictionary).get("verb", ""))).is_empty():
			return true
	return false


static func _documents_touch(doc: Dictionary, table: Dictionary) -> bool:
	if table.is_empty():
		return false
	var documents: Variant = doc.get("documents", {})
	if not (documents is Dictionary):
		return false
	var block: Dictionary = documents
	if block.get("read") is Array and _doc_rows_touch(block["read"], table):
		return true
	if block.get("copies") is Array and _doc_rows_touch(block["copies"], table):
		return true
	return _publish_touch(doc, table)


static func _doc_rows_touch(items: Array, table: Dictionary) -> bool:
	for item in items:
		if not (item is Dictionary):
			continue
		if not _mapped(table, str((item as Dictionary).get("doc", ""))).is_empty():
			return true
	return false


static func _publish_touch(doc: Dictionary, table: Dictionary) -> bool:
	var flight: Variant = doc.get("flight", {})
	if not (flight is Dictionary):
		return false
	var ids := _publish_ids(flight)
	for name in ids.keys():
		if not _mapped(table, String(name)).is_empty():
			return true
	return false


## True when a quest row would move off a missing stage or a missing region leaf.
static func _stages_move(quests: Dictionary, content: WyrdContent) -> bool:
	for quest_id in quests.keys():
		var item: Variant = quests[quest_id]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var stage_id := str(row.get("stage", ""))
		if stage_id.is_empty():
			continue
		var quest := _quest_def(content, String(quest_id), row)
		if quest == null:
			continue
		var names := _stage_names(quest)
		if not names.has(stage_id):
			if not _fallback_stage(quest, row, names).is_empty():
				return true
			continue
		var body := WyrdQuestRunner.stage_body(_top_stage(quest, stage_id), str(row.get("variant", "")))
		var packed: Variant = row.get("regions", null)
		if body != null and packed is Dictionary and _regions_move(body, packed):
			return true
	return false


static func _regions_move(body: WyrdStageDef, saved: Dictionary) -> bool:
	if body == null:
		return false
	var declared := {}
	for item in body.regions:
		var region := item as WyrdRegionDef
		if region != null and not region.id.is_empty():
			declared[region.id] = region
	for key in saved.keys():
		var region_id := String(key)
		if not declared.has(region_id) or not (saved[key] is Dictionary):
			continue
		var region: WyrdRegionDef = declared[region_id]
		var row: Dictionary = saved[key]
		var leaf := _region_leaf(region, str(row.get("stage", "")))
		if leaf == null:
			if not region.stages.is_empty():
				return true
			continue
		var packed: Variant = row.get("regions", null)
		if packed is Dictionary and _regions_move(leaf, packed):
			return true
	return false


static func _has_table(aliases: Dictionary) -> bool:
	for kind in ["document", "role", "stage", "verb"]:
		var table: Variant = aliases.get(kind, {})
		if table is Dictionary and not (table as Dictionary).is_empty():
			return true
	return false


static func _kind(aliases: Dictionary, kind: String) -> Dictionary:
	var table: Variant = aliases.get(kind, {})
	if table is Dictionary:
		return table
	return {}


static func _mapped(table: Dictionary, old: String) -> String:
	if old.is_empty() or not table.has(old):
		return ""
	var new_id := String(table[old])
	if new_id.is_empty() or new_id == old:
		return ""
	return new_id


static func _subject(kind: String, old: String, quest_id: String = "") -> String:
	if kind == "stage":
		return "stage:%s" % quest_id
	return "%s:%s" % [kind, old]


static func _bump(bag: Dictionary, subject: String, kind: String, old: String, new_id: String) -> void:
	if not bag.has(subject):
		bag[subject] = {"count": 0, "from": old, "kind": kind, "to": new_id}
	var row: Dictionary = bag[subject]
	row["count"] = int(row["count"]) + 1


static func _stage_scope(quest_id: String, row: Dictionary) -> String:
	var named := str(row.get("template", ""))
	if named != "":
		return named
	var hash := quest_id.find("#")
	if hash > 0:
		return quest_id.substr(0, hash)
	return quest_id


static func _rewrite_stages(doc: Dictionary, tables: Dictionary, rewrites: Dictionary) -> void:
	if tables.is_empty():
		return
	var quests: Variant = doc.get("quests", {})
	if not (quests is Dictionary):
		return
	var block: Dictionary = quests
	var ids: Array = block.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for quest_id in ids:
		var item: Variant = block[quest_id]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var scope := _stage_scope(String(quest_id), row)
		var found: Variant = tables.get(scope, {})
		if not (found is Dictionary):
			continue
		var old := str(row.get("stage", ""))
		var new_id := _mapped(found, old)
		if not new_id.is_empty():
			row["stage"] = new_id
			_bump(rewrites, _subject("stage", old, String(quest_id)), "stage", old, new_id)
		_rewrite_trail(row, found, String(quest_id), rewrites)


static func _rewrite_roles(doc: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	if table.is_empty():
		return
	var roles: Variant = doc.get("roles", {})
	if not (roles is Dictionary):
		return
	var block: Dictionary = roles
	for name in ["bindings", "defs", "pending", "told"]:
		var bag: Variant = block.get(name, {})
		if bag is Dictionary:
			_remap_map(bag, table, rewrites, drops)
	var abolished: Variant = block.get("abolished", [])
	if abolished is Array:
		block["abolished"] = _remap_list(abolished, table, rewrites, drops)


static func _remap_map(bag: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	var names: Array = bag.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var original: Dictionary = {}
	for name in names:
		original[String(name)] = true
	var placed: Dictionary = {}
	for name in names:
		var old := String(name)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			continue
		var subject := _subject("role", old)
		if original.has(new_id) or placed.has(new_id):
			bag.erase(name)
			_bump(drops, subject, "role", old, new_id)
			continue
		bag[new_id] = bag[name]
		bag.erase(name)
		placed[new_id] = true
		_bump(rewrites, subject, "role", old, new_id)


static func _remap_list(items: Array, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> Array:
	var original: Dictionary = {}
	for item in items:
		original[str(item)] = true
	var placed: Dictionary = {}
	var out: Array = []
	for item in items:
		var old := str(item)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			out.append(item)
			continue
		var subject := _subject("role", old)
		if original.has(new_id) or placed.has(new_id):
			_bump(drops, subject, "role", old, new_id)
			continue
		out.append(new_id)
		placed[new_id] = true
		_bump(rewrites, subject, "role", old, new_id)
	return out


static func _rewrite_verbs(doc: Dictionary, table: Dictionary, rewrites: Dictionary) -> void:
	if table.is_empty():
		return
	var deeds: Variant = doc.get("deeds", {})
	if deeds is Dictionary:
		var rows: Variant = (deeds as Dictionary).get("rows", [])
		if rows is Array:
			_rewrite_verb_rows(rows, table, rewrites)
	var flight: Variant = doc.get("flight", {})
	if not (flight is Dictionary):
		return
	var rumor: Variant = (flight as Dictionary).get("rumor", {})
	if not (rumor is Dictionary):
		return
	var block: Dictionary = rumor
	if block.get("jobs") is Array:
		_rewrite_verb_rows(block["jobs"], table, rewrites)
	if block.get("reach") is Array:
		_rewrite_verb_rows(block["reach"], table, rewrites)


static func _rewrite_verb_rows(rows: Array, table: Dictionary, rewrites: Dictionary) -> void:
	for item in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var old := str(row.get("verb", ""))
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			continue
		row["verb"] = new_id
		_bump(rewrites, _subject("verb", old), "verb", old, new_id)


static func _rewrite_documents(doc: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	if table.is_empty():
		return
	var documents: Variant = doc.get("documents", {})
	if not (documents is Dictionary):
		return
	var block: Dictionary = documents
	if block.get("read") is Array:
		block["read"] = _remap_doc_rows(block["read"], table, "reader", rewrites, drops)
	if block.get("copies") is Array:
		block["copies"] = _remap_doc_rows(block["copies"], table, "copy", rewrites, drops)
	_rewrite_publish(doc, table, rewrites, drops)


static func _remap_doc_rows(items: Array, table: Dictionary, pair_field: String, rewrites: Dictionary, drops: Dictionary) -> Array:
	var original: Dictionary = {}
	for item in items:
		if item is Dictionary:
			var prior: Dictionary = item
			original[_pair(str(prior.get(pair_field, "")), str(prior.get("doc", "")))] = true
	var placed: Dictionary = {}
	var out: Array = []
	for item in items:
		if not (item is Dictionary):
			out.append(item)
			continue
		var row: Dictionary = item
		var old := str(row.get("doc", ""))
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			out.append(row)
			continue
		var dest := _pair(str(row.get(pair_field, "")), new_id)
		var subject := _subject("document", old)
		if original.has(dest) or placed.has(dest):
			_bump(drops, subject, "document", old, new_id)
			continue
		row["doc"] = new_id
		placed[dest] = true
		out.append(row)
		_bump(rewrites, subject, "document", old, new_id)
	return out


static func _rewrite_trail(row: Dictionary, table: Dictionary, quest_id: String, rewrites: Dictionary) -> void:
	var trail_raw: Variant = row.get("trail", null)
	if not (trail_raw is Array):
		return
	var changed := false
	var mapped: Array = []
	for entry in trail_raw:
		var old := str(entry)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			mapped.append(entry)
			continue
		mapped.append(new_id)
		changed = true
		_bump(rewrites, "trail:%s:%s" % [quest_id, old], "stage", old, new_id)
	if not changed:
		return
	var last := {}
	for index in mapped.size():
		last[str(mapped[index])] = index
	var collapsed: Array = []
	for index in mapped.size():
		if int(last[str(mapped[index])]) == index:
			collapsed.append(str(mapped[index]))
	row["trail"] = collapsed


static func _rewrite_publish(doc: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	var flight: Variant = doc.get("flight", {})
	if not (flight is Dictionary):
		return
	var block: Dictionary = flight
	var original := _publish_ids(block)
	var names: Array = original.keys()
	names.sort()
	var placed := {}
	for name in names:
		var old := String(name)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			continue
		var dropping := original.has(new_id) or placed.has(new_id)
		var count := _move_publish(block, old, new_id, dropping)
		if count <= 0:
			continue
		var bag := drops if dropping else rewrites
		for _i in count:
			_bump(bag, _subject("document", old), "document", old, new_id)
		if not dropping:
			placed[new_id] = true


static func _publish_ids(flight: Dictionary) -> Dictionary:
	var ids := {}
	var publish: Variant = flight.get("publish", {})
	if publish is Dictionary:
		var block: Dictionary = publish
		var counters: Variant = block.get("counters", {})
		if counters is Dictionary:
			for key in (counters as Dictionary).keys():
				ids[String(key)] = true
		var covered: Variant = block.get("covered", {})
		if covered is Dictionary:
			for key in (covered as Dictionary).keys():
				ids[String(key)] = true
		var queued: Variant = block.get("queued", [])
		if queued is Array:
			for item in queued:
				var doc := _queued_doc(str(item))
				if not doc.is_empty():
					ids[doc] = true
		var cursor := _issue_doc(str(block.get("cursor", "")))
		if not cursor.is_empty():
			ids[cursor] = true
	var scheduler: Variant = flight.get("scheduler", {})
	if scheduler is Dictionary:
		var tokens: Variant = (scheduler as Dictionary).get("publish", [])
		if tokens is Array:
			for item in tokens:
				var doc := _issue_doc(str(item))
				if not doc.is_empty():
					ids[doc] = true
	return ids


static func _move_publish(flight: Dictionary, old: String, new_id: String, dropping: bool) -> int:
	var count := 0
	var publish: Variant = flight.get("publish", {})
	if publish is Dictionary:
		var block: Dictionary = publish
		count += _move_int_key(block, "counters", old, new_id, dropping)
		count += _move_int_key(block, "covered", old, new_id, dropping)
		var queued: Variant = block.get("queued", null)
		if queued is Array:
			var next: Array = []
			var seen := false
			for item in queued:
				var text := str(item)
				if _queued_doc(text) != old:
					next.append(item)
					continue
				seen = true
				count += 1
				if not dropping:
					next.append(_rewrite_queued(text, new_id))
			if seen:
				block["queued"] = next
		if _issue_doc(str(block.get("cursor", ""))) == old:
			count += 1
			if dropping:
				block.erase("cursor")
				block.erase("beliefs")
				block.erase("claim")
			else:
				block["cursor"] = _rewrite_issue(str(block.get("cursor", "")), new_id)
	var scheduler: Variant = flight.get("scheduler", {})
	if scheduler is Dictionary:
		var queue: Dictionary = scheduler
		var tokens: Variant = queue.get("publish", null)
		if tokens is Array:
			var kept: Array = []
			var touched := false
			for token in tokens:
				var token_text := str(token)
				if _issue_doc(token_text) != old:
					kept.append(token)
					continue
				touched = true
				count += 1
				if not dropping:
					kept.append(_rewrite_issue(token_text, new_id))
			if touched:
				queue["publish"] = kept
	return count


static func _move_int_key(block: Dictionary, field: String, old: String, new_id: String, dropping: bool) -> int:
	var bag: Variant = block.get(field, {})
	if not (bag is Dictionary) or not (bag as Dictionary).has(old):
		return 0
	var values: Dictionary = bag
	if dropping:
		values.erase(old)
	else:
		values[new_id] = values[old]
		values.erase(old)
	return 1


static func _issue_doc(token: String) -> String:
	var parts := token.split("\t")
	if parts.size() < 4 or parts[0] != "issue":
		return ""
	return parts[1]


static func _rewrite_issue(token: String, new_id: String) -> String:
	var parts := token.split("\t")
	parts[1] = new_id
	return "\t".join(parts)


static func _queued_doc(token: String) -> String:
	var at := token.find("\t")
	if at <= 0:
		return ""
	return token.substr(0, at)


static func _rewrite_queued(token: String, new_id: String) -> String:
	var at := token.find("\t")
	return new_id + token.substr(at)


static func _quest_def(content: WyrdContent, quest_id: String, row: Dictionary) -> WyrdQuestDef:
	if quest_id.contains("#") or str(row.get("template", "")) != "":
		return content.templates.get(_stage_scope(quest_id, row)) as WyrdQuestDef
	return content.quests.get(quest_id) as WyrdQuestDef


static func _stage_names(quest: WyrdQuestDef) -> Dictionary:
	var names := {}
	if quest == null:
		return names
	for stage in quest.stages:
		if not stage.id.is_empty():
			names[stage.id] = true
	return names


static func _top_stage(quest: WyrdQuestDef, stage_id: String) -> WyrdStageDef:
	if quest == null:
		return null
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null


static func _fallback_stage(quest: WyrdQuestDef, row: Dictionary, names: Dictionary) -> String:
	if not quest.on_missing_stage.is_empty() and names.has(quest.on_missing_stage):
		return quest.on_missing_stage
	var trail: Variant = row.get("trail", [])
	if trail is Array:
		var items: Array = trail
		for index in range(items.size() - 1, -1, -1):
			var id := str(items[index])
			if names.has(id):
				return id
	if quest.stages.is_empty():
		return ""
	return quest.stages[0].id


static func _arrive(row: Dictionary, quest: WyrdQuestDef, stage_id: String) -> void:
	var stage := _top_stage(quest, stage_id)
	row["stage"] = stage_id
	row["entered"] = true
	row["variant"] = ""
	row["step_at"] = WyrdQuestRunner.entry_step_count(stage)
	row["offered"] = ""
	row["waiting"] = ""
	row["host_screen"] = ""
	row["scene_done"] = false
	row["held_empty"] = false
	row["host_fields"] = []
	var regions := _initial_regions(stage)
	if regions.is_empty():
		row.erase("regions")
	else:
		row["regions"] = regions
	var prior: Array = []
	var raw: Variant = row.get("trail", [])
	if raw is Array:
		prior = raw
	row["trail"] = WyrdQuestRunner.remember_trail(prior, stage_id)


static func _initial_regions(stage: WyrdStageDef) -> Dictionary:
	var out := {}
	if stage == null:
		return out
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null or region.id.is_empty() or region.stages.is_empty():
			continue
		var leaf := region.stages[0]
		var nested := _initial_regions(leaf)
		var row := {
			"entered": true,
			"stage": leaf.id,
			"step_at": WyrdQuestRunner.entry_step_count(leaf),
		}
		if not nested.is_empty():
			row["regions"] = nested
		out[region.id] = row
	return out


static func _repair_regions(quest_id: String, body: WyrdStageDef, saved: Dictionary, path: String, rows: Array) -> void:
	if body == null:
		return
	var declared := {}
	for item in body.regions:
		var region := item as WyrdRegionDef
		if region != null and not region.id.is_empty():
			declared[region.id] = region
	var ids: Array = saved.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for key in ids:
		var region_id := String(key)
		if not declared.has(region_id) or not (saved[key] is Dictionary):
			continue
		var region: WyrdRegionDef = declared[region_id]
		var row: Dictionary = saved[key]
		var leaf_id := str(row.get("stage", ""))
		var leaf := _region_leaf(region, leaf_id)
		var leaf_path := path + region_id
		if leaf == null:
			if region.stages.is_empty():
				continue
			leaf = region.stages[0]
			row["stage"] = leaf.id
			row["entered"] = true
			row["step_at"] = WyrdQuestRunner.entry_step_count(leaf)
			var nested := _initial_regions(leaf)
			if nested.is_empty():
				row.erase("regions")
			else:
				row["regions"] = nested
			_note_move(rows, "%s/%s" % [quest_id, leaf_path], leaf_id, leaf.id)
			continue
		var packed: Variant = row.get("regions", null)
		if packed is Dictionary:
			_repair_regions(quest_id, leaf, packed, leaf_path + "/", rows)


static func _region_leaf(region: WyrdRegionDef, stage_id: String) -> WyrdStageDef:
	if region == null:
		return null
	for stage in region.stages:
		if stage.id == stage_id:
			return stage
	return null


static func _note_move(rows: Array, id: String, old: String, new_id: String) -> void:
	rows.append({
		"code": String(WyrdDiagnostic.W_SAVE_STAGE),
		"count": 1,
		"from": old,
		"id": id,
		"kind": "missing_stage",
		"to": new_id,
	})


static func _pair(left: String, right: String) -> String:
	return "%s\t%s" % [left, right]


static func _rows(rewrites: Dictionary, drops: Dictionary) -> Array:
	var rows: Array = []
	for subject in rewrites.keys():
		rows.append(_row(rewrites[subject], String(subject), ""))
	for subject in drops.keys():
		rows.append(_row(drops[subject], String(subject), String(WyrdDiagnostic.W_SAVE_ALIAS)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a := String(a.get("id", ""))
		var id_b := String(b.get("id", ""))
		if id_a != id_b:
			return id_a < id_b
		return String(a.get("code", "")) < String(b.get("code", ""))
	)
	return rows


static func _row(body: Dictionary, subject: String, code: String) -> Dictionary:
	return {
		"code": code,
		"count": int(body.get("count", 0)),
		"from": String(body.get("from", "")),
		"id": subject,
		"kind": "alias",
		"to": String(body.get("to", "")),
	}


static func _diagnostics(drops: Dictionary) -> Array:
	var notes: Array = []
	var subjects: Array = drops.keys()
	subjects.sort()
	for subject in subjects:
		var body: Dictionary = drops[subject]
		notes.append({
			"code": String(WyrdDiagnostic.W_SAVE_ALIAS),
			"message": "saved %s \"%s\" was dropped because \"%s\" is also saved" % [String(body.get("kind", "")), String(body.get("from", "")), String(body.get("to", ""))],
			"severity": "warning",
		})
	return notes
