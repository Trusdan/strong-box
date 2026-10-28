class_name WyrdPack
extends RefCounted

## Compiles a pack: parse every file, merge facts, compile statements, link.
##
## @experimental
## Statement lookup uses the merged schema, so a quest can read facts declared
## in another file of the same pack. [code]wyrd_commands.json[/code] is optional.

static func compile(
	files: PackedStringArray,
	pack_id: String,
	language_version: int,
	commands: WyrdCommandSchema,
	diagnostics: WyrdDiagnostics,
	note_path: String = "",
	skip_commands_note: bool = false,
	secrecy_tiers: PackedStringArray = PackedStringArray(),
	pressure_tiers: PackedStringArray = PackedStringArray()
) -> WyrdLinkedPack:
	var parsed: Array = []
	for path in _unique(files):
		var source := WyrdSource.load_file(path)
		if source == null:
			diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "could not read file", path, 1, 1)
			continue
		var tree := WyrdParser.new().parse(source, diagnostics)
		var schema := tree.schema if tree.schema != null else WyrdFactSchema.new()
		parsed.append({"path": path, "schema": schema, "source": source, "tree": tree})
	var merged := WyrdFactSchema.new()
	var fact_paths := {}
	for row in parsed:
		var path := str(row["path"])
		var schema: WyrdFactSchema = row["schema"]
		for fact in schema.entries:
			var prior := merged.conflict(fact)
			if prior != null:
				var prior_path := str(fact_paths.get(prior, ""))
				if prior_path != path:
					diagnostics.add(
						WyrdDiagnostic.E_FACT_REDECLARED,
						_redeclare(prior, fact, prior_path),
						path,
						fact.line,
						fact.col
					)
				continue
			merged.entries.append(fact)
			fact_paths[fact] = path
	var events := _merge_events(parsed, diagnostics)
	_lint_resolvers(merged, events, fact_paths, diagnostics)
	_lint_leaves(merged, events, diagnostics)
	var units: Array = []
	for row in parsed:
		var tree: WyrdNode = row["tree"]
		var source: WyrdSource = row["source"]
		tree.schema = merged
		var file := WyrdStatements.new().compile(source, tree, diagnostics, events)
		units.append({
			"file": file,
			"hash": WyrdExport.hash_text(source.text),
			"path": source.path,
			"text": source.text,
		})
	var linker := WyrdLinker.new()
	var pack := linker.link(units, merged, pack_id, language_version, commands, note_path, skip_commands_note, diagnostics)
	pack.events = events
	linker.finish_xref(pack, fact_paths)
	if not secrecy_tiers.is_empty():
		WyrdSecrecyLint.warn(pack, diagnostics, secrecy_tiers)
	if not pressure_tiers.is_empty():
		WyrdLinker.warn_pressure(pack, diagnostics, pressure_tiers)
	diagnostics.sort_items()
	return pack


static func read_commands(path: String, diagnostics: WyrdDiagnostics) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"schema": null, "skip_note": false}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not (parser.data is Dictionary):
		diagnostics.add(
			WyrdDiagnostic.E_COMMANDS_FILE,
			"could not read command schemas",
			path,
			1,
			1
		)
		return {"schema": null, "skip_note": true}
	var data: Dictionary = parser.data
	var names: Variant = data.get("commands", [])
	if not (names is Array):
		diagnostics.add(WyrdDiagnostic.E_COMMANDS_FILE, "could not read command schemas", path, 1, 1)
		return {"schema": null, "skip_note": true}
	var schema := WyrdCommandSchema.new()
	for name in names:
		schema.add_command(StringName(str(name)))
	if data.has("skills"):
		var skills: Variant = data.get("skills")
		if not (skills is Array):
			diagnostics.add(WyrdDiagnostic.E_COMMANDS_FILE, "could not read command schemas", path, 1, 1)
			return {"schema": null, "skip_note": true}
		schema.checks_skills = true
		for name in skills:
			schema.add_skill(StringName(str(name)))
	return {"schema": schema, "skip_note": true}


static func pack_id_for(path: String) -> String:
	var name := path.get_file()
	if name.ends_with(".wyrd"):
		return name.trim_suffix(".wyrd")
	return name


static func _unique(files: PackedStringArray) -> PackedStringArray:
	var copy := files.duplicate()
	copy.sort()
	var out := PackedStringArray()
	var prev := ""
	for item in copy:
		if item.is_empty() or item == prev:
			continue
		out.append(item)
		prev = item
	return out


static func _merge_events(parsed: Array, diagnostics: WyrdDiagnostics) -> Dictionary:
	var events := {}
	var where := {}
	for row in parsed:
		var path := str(row["path"])
		var tree: WyrdNode = row["tree"]
		for child in tree.children:
			if child.keyword != "events":
				continue
			for event in child.events:
				if where.has(event.name):
					var prior: Dictionary = where[event.name]
					diagnostics.add(
						WyrdDiagnostic.E_EVENT_DUPLICATE,
						"duplicate event \"%s\" also declared in %s:%d:%d" % [event.name, str(prior["path"]), int(prior["line"]), int(prior["col"])],
						path,
						event.line,
						event.col
					)
					continue
				where[event.name] = {"col": event.col, "line": event.line, "path": path}
				event.source_path = path
				events[event.name] = event
	return events


static func _lint_resolvers(
	schema: WyrdFactSchema,
	events: Dictionary,
	fact_paths: Dictionary,
	diagnostics: WyrdDiagnostics
) -> void:
	if schema == null:
		return
	for fact in schema.entries:
		if fact.origin != &"resolved":
			continue
		var path := str(fact_paths.get(fact, ""))
		if fact.invalidate == &"":
			diagnostics.add(
				WyrdDiagnostic.E_RESOLVER_NO_INVALIDATE,
				"resolved fact \"%s\" needs invalidate: on_event, poll, or per_query" % fact.key,
				path,
				fact.line,
				fact.col
			)
		elif fact.invalidate == &"on_event" and not events.has(fact.invalidate_arg):
			diagnostics.add(
				WyrdDiagnostic.E_EVENT_UNKNOWN,
				"unknown event \"%s\"" % fact.invalidate_arg,
				path,
				fact.line,
				fact.col
			)


static func _lint_leaves(
	schema: WyrdFactSchema,
	events: Dictionary,
	diagnostics: WyrdDiagnostics
) -> void:
	if schema == null:
		return
	var names: Array = events.keys()
	names.sort()
	for name in names:
		var event := events[name] as WyrdEventDef
		if event == null or event.leaves_key.is_empty():
			continue
		var segments := PackedStringArray()
		for part in event.leaves_key.split("."):
			segments.append(String(part))
		var fact := schema.lookup(segments)
		var path := event.source_path
		var line := event.leaves_line if event.leaves_line > 0 else event.line
		var col := event.leaves_col if event.leaves_col > 0 else event.col
		if fact == null:
			diagnostics.add(
				WyrdDiagnostic.E_UNKNOWN_FACT,
				"unknown fact \"%s\"" % event.leaves_key,
				path,
				line,
				col
			)
			continue
		if fact.is_pattern():
			diagnostics.add(
				WyrdDiagnostic.E_EVENT_ARG,
				"evidence fact \"%s\" must be a concrete key" % event.leaves_key,
				path,
				line,
				col
			)
			continue
		if fact.origin != &"stored":
			diagnostics.add(
				WyrdDiagnostic.E_WRITE_RESOLVED,
				"cannot write resolved fact \"%s\"" % fact.key,
				path,
				line,
				col
			)
			continue
		if not _leaves_fits(event.leaves_kind, fact.type_name):
			diagnostics.add(
				WyrdDiagnostic.E_WRITE_TYPE,
				"cannot write %s to %s fact \"%s\"" % [event.leaves_kind, fact.type_name, fact.key],
				path,
				line,
				col
			)


static func _leaves_fits(have: StringName, want: StringName) -> bool:
	if have == want:
		return true
	return have == &"int" and want == &"float"


static func _redeclare(prior: WyrdFact, fact: WyrdFact, prior_path: String) -> String:
	if prior.key == fact.key:
		return "fact \"%s\" is also declared in %s:%d:%d" % [fact.key, prior_path, prior.line, prior.col]
	return "fact \"%s\" overlaps \"%s\" declared in %s:%d:%d" % [fact.key, prior.key, prior_path, prior.line, prior.col]
