class_name WyrdCli
extends RefCounted

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Text and exit status for the command-line entry.
##
## @experimental
## [code]check[/code] lexes, parses, compiles, and links a pack.
## [code]tag-lines[/code] writes missing line ids. [code]export-json[/code] writes
## the debug pack document. [code]facts[/code] prints the cross-reference.
## [code]roles[/code] prints a sorted table of role holders.
## [code]why-not[/code] explains one storylet for a scope and speaker.
## [code]storylets[/code] lists storylets. [code]cooldowns[/code] lists clocks.
## [code]choices[/code] lists stored-fact writes from the provenance map.
## [code]coverage[/code] lists storylets, variants, and line ids that were never hit.
## [code]console[/code] is the playtest prompt. It is omitted from a release export.
## [code]voice-check[/code] reports variable text per speaker.
## [code]script-export[/code] writes one speaker's lines for a recording pass.
## [code]unvoiced-report[/code] lists line ids with no audio for each locale.
## [code]test[/code] stays unimplemented until the runtime can run a scene.
## Engine unit tests stay on GUT.

const COMMANDS: PackedStringArray = ["check", "test", "tag-lines", "export-json", "pot", "defs", "facts", "roles", "why-not", "voice-check", "script-export", "unvoiced-report", "storylets", "cooldowns", "choices", "coverage", "console", "generate"]
const CONSOLE_SCRIPT := "res://addons/wyrd/runtime/console/wyrd_console.gd"
const CONSOLE_ABSENT := "wyrd: console is not in this build\n"


static func version_line() -> String:
	return "wyrd %s" % _Runtime.read_version()


static func command_lines() -> PackedStringArray:
	return PackedStringArray([
		"check: compile and link a content pack; --watch re-checks on change; --tiers a,b runs the secrecy lint; --pressure-tiers a,b lints template tiers",
		"test: not implemented",
		"tag-lines: write missing #line: ids",
		"export-json: write the linked pack as JSON",
		"pot: write a gettext POT for one pack's player text",
		"defs: write a ctags tags file of a pack's definitions",
		"facts: print the fact cross-reference",
		"roles: print a sorted table of role holders",
		"why-not: explain one storylet for a scope and speaker",
		"voice-check: report variable text per speaker",
		"script-export: write one speaker's lines for a recording pass",
		"unvoiced-report: list line ids with no audio for each locale",
		"storylets: list storylets for a scope and speaker",
		"cooldowns: list storylet rows and speaker clocks",
		"choices: list fact writes by scene, choice, prefix, or time",
		"coverage: list storylets, variants, and lines that were never hit",
		"console: playtest prompt for facts, roles, time, events, and scenes",
		"generate: --dry-run shows one proposal or why there is none",
	])


static func render() -> String:
	var lines := PackedStringArray()
	lines.append(version_line())
	lines.append_array(command_lines())
	return "\n".join(lines) + "\n"


static func execute(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"exit_code": 0, "output": render()}
	var command := args[0]
	if command == "test":
		return {"exit_code": 0, "output": "test: not implemented\n"}
	if command == "check":
		return _check(args)
	if command == "tag-lines":
		return _tag(args)
	if command == "export-json":
		return _export(args)
	if command == "facts":
		return _facts(args)
	if command == "roles":
		return _roles(args)
	if command == "why-not":
		return _why_not(args)
	if command == "storylets":
		return _storylets(args)
	if command == "cooldowns":
		return _cooldowns(args)
	if command == "choices":
		return _choices(args)
	if command == "coverage":
		return _coverage(args)
	if command == "console":
		return _console(args)
	if command == "voice-check":
		return _voice_check(args)
	if command == "script-export":
		return _script_export(args)
	if command == "unvoiced-report":
		return _unvoiced_report(args)
	if command == "pot":
		return _pot(args)
	if command == "defs":
		return _defs(args)
	if command == "generate":
		return _generate(args)
	return {"exit_code": 1, "output": "wyrd: unknown command \"%s\"\n" % command}


class _NoElection extends WyrdElectionAdapter:
	func start_election(_role: StringName, _departed: StringName) -> void:
		pass


class _NoHost extends RefCounted:
	func decide(_role: StringName, _departed: StringName) -> void:
		pass


static func _check(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	if bool(parsed["watch"]):
		return {
			"exit_code": 0,
			"output": "",
			"watch": WyrdCheckWatch.new(parsed, _without_watch(args)),
		}
	var compiled := _compile_check(parsed)
	return {"exit_code": int(compiled["exit_code"]), "output": str(compiled["output"])}


static func _run_check(args: PackedStringArray) -> Dictionary:
	var parsed := _options(_without_watch(args))
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"]), "errors": 1, "warnings": 0}
	return _compile_check(parsed)


static func _without_watch(args: PackedStringArray) -> PackedStringArray:
	var forwarded := PackedStringArray()
	for arg in args:
		if arg != "--watch":
			forwarded.append(arg)
	return forwarded


static func _compile_check(parsed: Dictionary) -> Dictionary:
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(loaded["output"]), "errors": 1, "warnings": 0}
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	var errors := 0
	var warnings := 0
	for item in diagnostics.items:
		var severity := String(item.severity)
		if severity == "error":
			errors += 1
		elif severity == "warning":
			warnings += 1
	var exit_code := 0
	if diagnostics.has_errors() or (bool(parsed["strict"]) and diagnostics.has_warnings()):
		exit_code = 1
	return {
		"exit_code": exit_code,
		"output": diagnostics.format(),
		"errors": errors,
		"warnings": warnings,
	}


static func _tag(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var files: PackedStringArray = parsed["files"]
	var pack_id := str(parsed["pack_id"])
	if files.is_empty():
		return {"exit_code": 1, "output": "wyrd: tag-lines needs one file or directory\n"}
	return WyrdTagLines.tag_files(files, pack_id, bool(parsed["dry_run"]))


static func _export(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var body := WyrdExport.to_json(WyrdExport.to_data(loaded["pack"]))
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _facts(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var pack: WyrdLinkedPack = loaded["pack"]
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if bool(parsed["as_json"]):
		return {"exit_code": 1 if diagnostics.has_errors() else 0, "output": WyrdExport.xref_json(pack)}
	var table := ""
	if pack.xref != null:
		table = pack.xref.render_table()
	var lines: PackedStringArray = PackedStringArray()
	if not table.is_empty():
		lines.append(table)
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 1 if diagnostics.has_errors() else 0, "output": output}


static func _roles(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var runtime: WyrdRuntime = _Runtime.new()
	var host := _NoHost.new()
	runtime.set_meta(&"cli_host", host)
	runtime.roles.set_host_decides(Callable(host, &"decide"))
	var election := _NoElection.new()
	runtime.set_meta(&"cli_election", election)
	runtime.register_adapter(WyrdElectionAdapter, election)
	var report := runtime.load_content(_manifest(parsed))
	if not report.ok:
		return {"exit_code": 1, "output": report.diagnostics.format()}
	runtime.start_new_game(1)
	var save_path := str(parsed["save"])
	if not save_path.is_empty():
		var resolved := _resolve(save_path)
		if not FileAccess.file_exists(resolved):
			return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % save_path}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
		if not (data is Dictionary):
			return {"exit_code": 1, "output": "wyrd: save is not a JSON object\n"}
		var loaded_save := runtime.load_state(data)
		if not loaded_save.ok:
			return {"exit_code": 1, "output": loaded_save.diagnostics.format()}
	var table := runtime.roles.render_table(str(parsed["prefix"]))
	var lines := PackedStringArray()
	if not table.is_empty():
		lines.append(table.trim_suffix("\n"))
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _choices(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var runtime: WyrdRuntime = _Runtime.new()
	var report := runtime.load_content(_manifest(parsed))
	if not report.ok:
		return {"exit_code": 1, "output": report.diagnostics.format()}
	runtime.start_new_game(1)
	var save_path := str(parsed["save"])
	if not save_path.is_empty():
		var resolved := _resolve(save_path)
		if not FileAccess.file_exists(resolved):
			return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % save_path}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
		if not (data is Dictionary):
			return {"exit_code": 1, "output": "wyrd: save is not a JSON object\n"}
		var loaded_save := runtime.load_state(data)
		if not loaded_save.ok:
			return {"exit_code": 1, "output": loaded_save.diagnostics.format()}
	var query := {}
	if bool(parsed["scene_set"]):
		query["scene"] = str(parsed["scene"])
	if bool(parsed["choice_set"]):
		query["choice"] = str(parsed["choice"])
	if not str(parsed["prefix"]).is_empty():
		query["prefix"] = str(parsed["prefix"])
	if bool(parsed["from_set"]):
		query["from"] = int(parsed["from_minute"])
	if bool(parsed["to_set"]):
		query["to"] = int(parsed["to_minute"])
	var table := runtime.facts.render_choice_summary(query)
	var lines := PackedStringArray()
	if not table.is_empty():
		lines.append(table.trim_suffix("\n"))
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func console_in_build(debug_build: bool) -> bool:
	if not debug_build:
		return false
	return load(CONSOLE_SCRIPT) != null


static func _console(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	if not console_in_build(OS.is_debug_build()):
		return {"exit_code": 1, "output": CONSOLE_ABSENT}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var played := _runtime_from(parsed)
	if int(played["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(played["output"])}
	var tool := _console_tool()
	if tool == null:
		return {"exit_code": 1, "output": CONSOLE_ABSENT}
	var runtime: WyrdRuntime = played["runtime"]
	tool.call(&"bind", runtime)
	var commands: PackedStringArray = parsed["cmds"]
	var interactive := commands.is_empty()
	var stdin: FileAccess = null
	if interactive:
		stdin = FileAccess.open("/dev/stdin", FileAccess.READ)
		if stdin == null:
			return {"exit_code": 1, "output": "wyrd: console could not read stdin\n"}
	var chunks := PackedStringArray()
	var failed := false
	var index := 0
	while true:
		var line := ""
		if interactive:
			if stdin.eof_reached():
				break
			print("wyrd>")
			line = stdin.get_line()
			if line.is_empty() and stdin.eof_reached():
				break
		else:
			if index >= commands.size():
				break
			line = commands[index]
			index += 1
		var raw: Variant = tool.call(&"exec", line)
		if not (raw is Dictionary):
			failed = true
			break
		var step: Dictionary = raw
		var text := str(step["output"])
		if interactive:
			if not text.is_empty():
				print(text.trim_suffix("\n"))
		elif not text.is_empty():
			chunks.append(text.trim_suffix("\n"))
		if not bool(step["ok"]):
			failed = true
		if bool(step["quit"]):
			break
	var save_error := _write_console_save(runtime, str(parsed["out"]), failed)
	if not save_error.is_empty():
		failed = true
		if interactive:
			print(save_error.trim_suffix("\n"))
		else:
			chunks.append(save_error.trim_suffix("\n"))
	var lines := PackedStringArray()
	if not chunks.is_empty():
		lines.append("\n".join(chunks))
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 1 if failed else 0, "output": output}


## Writes the runtime save when [param out] is set and no command failed.
## An open scene is refused here so [method WyrdRuntime.save_state] is not called.
static func _write_console_save(runtime: WyrdRuntime, out: String, failed: bool) -> String:
	if out.is_empty() or failed:
		return ""
	if runtime == null or not runtime.can_save():
		return "wyrd: console could not write the save: a scene is open\n"
	var saved := runtime.save_state()
	if saved.is_empty():
		return "wyrd: console could not write the save\n"
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "wyrd: could not write %s\n" % out
	file.store_string(JSON.stringify(saved))
	file.close()
	return ""


static func _console_tool() -> RefCounted:
	var script: Variant = load(CONSOLE_SCRIPT)
	if not (script is Script):
		return null
	var created: Variant = (script as Script).new()
	if created is RefCounted:
		return created as RefCounted
	return null


static func _coverage(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var runtime: WyrdRuntime = _Runtime.new()
	var report := runtime.load_content(_manifest(parsed))
	if not report.ok:
		return {"exit_code": 1, "output": report.diagnostics.format()}
	var file_path := WyrdCoverage.DEFAULT_PATH
	if bool(parsed["file_set"]):
		file_path = str(parsed["file"])
	var resolved := _resolve(file_path)
	var read := WyrdCoverage.read_file(resolved)
	if not bool(read["ok"]):
		return {"exit_code": 1, "output": "wyrd: coverage file is not a JSON object\n"}
	var counts: Dictionary = read["counts"]
	var table := runtime.coverage.render(counts)
	var lines := PackedStringArray()
	if not table.is_empty():
		lines.append(table.trim_suffix("\n"))
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _why_not(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var played := _runtime_from(parsed)
	if int(played["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(played["output"])}
	var runtime: WyrdRuntime = played["runtime"]
	var storylet_id := str(parsed["storylet"])
	if runtime.content().templates.has(storylet_id) and not runtime.content().storylets.has(storylet_id):
		return _why_not_template(runtime, parsed, storylet_id)
	var scope := str(parsed["scope"])
	var scope_id := str(parsed["scope_id"])
	var speaker := str(parsed["speaker"])
	var found: Variant = runtime.content().storylets.get(storylet_id, null)
	if found is WyrdStoryletDef:
		var story: WyrdStoryletDef = found
		if not bool(parsed["scope_set"]):
			scope = String(story.scope_kind)
		if not bool(parsed["scope_id_set"]) and scope != "bark":
			scope_id = story.scope_id
		if not bool(parsed["speaker_set"]):
			speaker = story.speaker
	var lines := PackedStringArray()
	if bool(parsed["trace_director"]):
		for item in runtime.director.candidate_rows(scope, scope_id, speaker):
			lines.append(WyrdDirector.format_candidate(item))
	var row := runtime.director.why_not(storylet_id, scope, scope_id, speaker)
	if str(row.get("reason", "")) == "missing":
		return {"exit_code": 1, "output": "wyrd: unknown storylet \"%s\"\n" % storylet_id}
	lines.append(WyrdDirector.format_why_not(row))
	return {"exit_code": 0, "output": "\n".join(lines) + "\n"}


static func _why_not_template(runtime: WyrdRuntime, parsed: Dictionary, template_id: String) -> Dictionary:
	var world := _register_world(runtime, parsed)
	if int(world["exit_code"]) != 0:
		return world
	var source := str(parsed.get("source", ""))
	if not bool(parsed.get("source_set", false)):
		source = "cli"
	var key := str(parsed.get("offer_key", ""))
	if not bool(parsed.get("key_set", false)):
		key = "why-not"
	var context := {
		"key": key,
		"source": source,
		"template": template_id,
		"tier": str(parsed.get("offer_tier", "")),
	}
	runtime.generator.propose(context)
	var row := runtime.generator.why_not(template_id)
	var lines := PackedStringArray()
	lines.append("why_not template=%s reason=%s" % [template_id, str(row.get("reason", ""))])
	var rules: Array = row.get("rules", [])
	for item in rules:
		if not (item is Dictionary):
			continue
		var rule: Dictionary = item
		lines.append("  rule=%s id=%s attempt=%s" % [str(rule.get("rule", "")), str(rule.get("id", "")), str(rule.get("attempt", ""))])
	return {"exit_code": 0, "output": "\n".join(lines) + "\n"}


static func _generate(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var played := _runtime_from(parsed)
	if int(played["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(played["output"])}
	var runtime: WyrdRuntime = played["runtime"]
	var world := _register_world(runtime, parsed)
	if int(world["exit_code"]) != 0:
		return world
	runtime.trace.enabled = true
	runtime.trace.clear()
	var context := {
		"key": str(parsed.get("offer_key", "")),
		"source": str(parsed.get("source", "")),
		"tier": str(parsed.get("offer_tier", "")),
	}
	var template_id := str(parsed.get("template", ""))
	if not template_id.is_empty():
		context["template"] = template_id
	var proposal := runtime.generator.propose(context)
	var lines := PackedStringArray()
	for item in runtime.trace.events:
		if not (item is Dictionary):
			continue
		var text := _format_gen(item)
		if not text.is_empty():
			lines.append(text)
	if proposal == null:
		var reason := "no_template"
		for item in runtime.trace.events:
			if item is Dictionary and str((item as Dictionary).get("kind", "")) == "gen_propose":
				reason = str((item as Dictionary).get("reason", reason))
		lines.append("none reason=%s" % reason)
		if reason == "rejected":
			for item in runtime.trace.events:
				if not (item is Dictionary) or str((item as Dictionary).get("kind", "")) != "gen_reject":
					continue
				var row: Dictionary = item
				lines.append("  rule=%s id=%s attempt=%s" % [str(row.get("rule", "")), str(row.get("id", "")), str(row.get("attempt", ""))])
	else:
		lines.append("proposal template=%s instance=%s casts=%s params=%s" % [
			proposal.template,
			proposal.instance,
			_pair_list(runtime, proposal, true),
			_pair_list(runtime, proposal, false),
		])
	return {"exit_code": 0, "output": "\n".join(lines) + "\n"}


static func _pair_list(runtime: WyrdRuntime, proposal: WyrdProposal, casts: bool) -> String:
	var template: WyrdTemplateDef = runtime.content().templates.get(proposal.template) as WyrdTemplateDef
	var parts := PackedStringArray()
	if template == null:
		return ""
	if casts:
		for slot in template.slots:
			if slot.mode != &"cast" or not proposal.casts.has(slot.name):
				continue
			parts.append("%s=%s" % [slot.name, str(proposal.casts[slot.name])])
	else:
		for param in template.params:
			if not proposal.params.has(param.name):
				continue
			var snap: Variant = proposal.params[param.name]
			var entity := ""
			if snap is Dictionary:
				entity = str((snap as Dictionary).get("entity", ""))
			parts.append("%s=%s" % [param.name, entity])
	return ",".join(parts)


static func _format_gen(row: Dictionary) -> String:
	var kind := str(row.get("kind", ""))
	match kind:
		"gen_tier":
			return "wyrd gen_tier source=%s key=%s tier=%s eligible=%s" % [str(row.get("source", "")), str(row.get("key", "")), str(row.get("tier", "")), str(row.get("eligible", ""))]
		"gen_pick":
			if str(row.get("reason", "")) == "no_template":
				return "wyrd gen_pick source=%s key=%s template= reason=no_template score=0/0 band=0 seed_key=%s" % [str(row.get("source", "")), str(row.get("key", "")), str(row.get("seed_key", ""))]
			return "wyrd gen_pick source=%s key=%s template=%s score=%s band=%s seed_key=%s" % [str(row.get("source", "")), str(row.get("key", "")), str(row.get("template", "")), str(row.get("score", "")), str(row.get("band", "")), str(row.get("seed_key", ""))]
		"gen_candidates":
			return "wyrd gen_candidates key=%s count=%s digest=%s" % [str(row.get("key", "")), str(row.get("count", "")), str(row.get("digest", ""))]
		"gen_cast":
			return "wyrd gen_cast instance=%s slot=%s kind=%s entity=%s" % [str(row.get("instance", "")), str(row.get("slot", "")), str(row.get("slot_kind", "")), str(row.get("entity", ""))]
		"gen_bind":
			return "wyrd gen_bind instance=%s param=%s kind=%s entity=%s" % [str(row.get("instance", "")), str(row.get("param", "")), str(row.get("slot_kind", "")), str(row.get("entity", ""))]
		"gen_propose":
			return "wyrd gen_propose source=%s key=%s ok=%s reason=%s proposal=%s" % [str(row.get("source", "")), str(row.get("key", "")), str(row.get("ok", "")), str(row.get("reason", "")), str(row.get("proposal", ""))]
		"gen_reject":
			return "wyrd gen_reject template=%s instance=%s rule=%s id=%s attempt=%s" % [str(row.get("template", "")), str(row.get("instance", "")), str(row.get("rule", "")), str(row.get("id", "")), str(row.get("attempt", ""))]
		"gen_cap":
			return "wyrd gen_cap template=%s active=%s reserved=%s max=%s" % [str(row.get("template", "")), str(row.get("active", "")), str(row.get("reserved", "")), str(row.get("max", ""))]
		"gen_expire":
			return "wyrd gen_expire instance=%s reason=%s" % [str(row.get("instance", "")), str(row.get("reason", ""))]
		_:
			return ""


static func _register_world(runtime: WyrdRuntime, parsed: Dictionary) -> Dictionary:
	var path := str(parsed.get("world", ""))
	if path.is_empty():
		return {"exit_code": 0, "output": ""}
	var resolved := _resolve(path)
	if not FileAccess.file_exists(resolved):
		return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % path}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	var loaded := WyrdCliWorld.from_data(data)
	if not bool(loaded.get("ok", false)):
		return {"exit_code": 1, "output": str(loaded.get("error", ""))}
	var world: WyrdCliWorld = loaded["world"]
	runtime.register_adapter(WyrdWorldAdapter, world)
	runtime.register_adapter(WyrdSpatialAdapter, world.spatial)
	runtime.register_adapter(WyrdInventoryAdapter, world.inventory)
	return {"exit_code": 0, "output": ""}


static func _storylets(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var played := _runtime_from(parsed)
	if int(played["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(played["output"])}
	var runtime: WyrdRuntime = played["runtime"]
	var scope := str(parsed["scope"])
	var scope_id := str(parsed["scope_id"])
	var speaker := str(parsed["speaker"])
	var filter := str(parsed["filter"])
	var prefix := str(parsed["prefix"])
	var lines := PackedStringArray()
	var ids: Array = runtime.content().storylets.keys()
	ids.sort()
	for id in ids:
		var story_id := String(id)
		if not prefix.is_empty() and not story_id.begins_with(prefix):
			continue
		if not filter.is_empty() and not story_id.contains(filter):
			continue
		var found: Variant = runtime.content().storylets[id]
		if not (found is WyrdStoryletDef):
			continue
		var story: WyrdStoryletDef = found
		if bool(parsed["scope_set"]) and String(story.scope_kind) != scope:
			continue
		if bool(parsed["scope_id_set"]) and String(story.scope_kind) != "bark" and story.scope_id != scope_id:
			continue
		var query_speaker := speaker if bool(parsed["speaker_set"]) else story.speaker
		if bool(parsed["speaker_set"]) and not runtime.director.speaker_matches(story.speaker, speaker):
			continue
		var query_scope := String(story.scope_kind)
		var query_id := "" if query_scope == "bark" else story.scope_id
		if bool(parsed["scope_set"]):
			query_scope = scope
		if query_scope == "bark":
			query_id = ""
		elif bool(parsed["scope_id_set"]):
			query_id = scope_id
		var diagnosed := runtime.director.diagnose(story_id, query_scope, query_id, query_speaker)
		if str(diagnosed["block"]) == "scope" or str(diagnosed["block"]) == "speaker" or str(diagnosed["block"]) == "missing":
			continue
		lines.append(_storylet_line(story, diagnosed))
	if bool(parsed["trace_director"]):
		for item in runtime.director.candidate_rows(scope, scope_id, speaker):
			lines.append(WyrdDirector.format_candidate(item))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _storylet_line(story: WyrdStoryletDef, diagnosed: Dictionary) -> String:
	var spoken := story.speaker
	if spoken.is_empty():
		spoken = "-"
	var secrecy := story.secrecy
	if secrecy.is_empty():
		secrecy = "-"
	var block := str(diagnosed.get("block", ""))
	if block.is_empty():
		block = "-"
	var clause := str(diagnosed.get("clause", "-")).replace("\"", "'")
	if clause.is_empty():
		clause = "-"
	return "wyrd storylet id=%s scope=%s speaker=%s priority=%s specificity=%s weight=%s cooldown=%s secrecy=%s seen=%s block=%s clause=\"%s\"" % [
		story.id,
		story.scope_text(),
		spoken,
		str(story.priority),
		str(story.specificity),
		str(story.weight),
		str(story.cooldown_minutes),
		secrecy,
		str(diagnosed.get("seen", 0)),
		block,
		clause,
	]


static func _cooldowns(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var played := _runtime_from(parsed)
	if int(played["exit_code"]) != 0:
		return {"exit_code": 1, "output": str(played["output"])}
	var runtime: WyrdRuntime = played["runtime"]
	var prefix := str(parsed["prefix"])
	var lines := PackedStringArray()
	var state := runtime.storylets.export_state()
	for id in state.keys():
		var story_id := String(id)
		if not prefix.is_empty() and not story_id.begins_with(prefix):
			continue
		var row: Dictionary = state[id]
		var seen := int(row.get("seen", 0))
		var last := -1
		if row.has("last_minute"):
			last = int(row.get("last_minute", -1))
		var cooldown := 0
		var found: Variant = runtime.content().storylets.get(story_id, null)
		if found is WyrdStoryletDef:
			cooldown = (found as WyrdStoryletDef).cooldown_minutes
		var remaining := 0
		if cooldown > 0 and last >= 0:
			var elapsed := runtime.now_minutes() - last
			if elapsed < cooldown:
				remaining = cooldown - elapsed
		lines.append("wyrd cooldown storylet=%s seen=%s last=%s cooldown=%s remaining=%s" % [
			story_id, str(seen), str(last), str(cooldown), str(remaining),
		])
	var speakers := runtime.storylets.export_speakers()
	for id in speakers.keys():
		var key := String(id)
		if not prefix.is_empty() and not key.begins_with(prefix):
			continue
		var clock: Dictionary = speakers[id]
		var stored := int(clock.get("cooldown", 0))
		var last_minute := int(clock.get("last_minute", 0))
		var left := runtime.storylets.speaker_remaining(key, runtime.now_minutes())
		lines.append("wyrd cooldown speaker=%s last=%s cooldown=%s remaining=%s" % [
			key, str(last_minute), str(stored), str(left),
		])
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _runtime_from(parsed: Dictionary) -> Dictionary:
	var runtime: WyrdRuntime = _Runtime.new()
	var host := _NoHost.new()
	runtime.set_meta(&"cli_host", host)
	runtime.roles.set_host_decides(Callable(host, &"decide"))
	var election := _NoElection.new()
	runtime.set_meta(&"cli_election", election)
	runtime.register_adapter(WyrdElectionAdapter, election)
	var report := runtime.load_content(_manifest(parsed))
	if not report.ok:
		return {"exit_code": 1, "output": report.diagnostics.format(), "runtime": null}
	var seed := 1
	if bool(parsed.get("seed_set", false)):
		seed = int(parsed.get("seed", 1))
	runtime.start_new_game(seed)
	var save_path := str(parsed["save"])
	if not save_path.is_empty():
		var resolved := _resolve(save_path)
		if not FileAccess.file_exists(resolved):
			return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % save_path, "runtime": null}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
		if not (data is Dictionary):
			return {"exit_code": 1, "output": "wyrd: save is not a JSON object\n", "runtime": null}
		var loaded_save := runtime.load_state(data)
		if not loaded_save.ok:
			return {"exit_code": 1, "output": loaded_save.diagnostics.format(), "runtime": null}
	if bool(parsed["tiers_set"]):
		runtime.config().secrecy_tiers = _tier_names(parsed["tiers"])
	if bool(parsed["secrecy_fact_set"]):
		runtime.config().secrecy_fact = str(parsed["secrecy_fact"])
	if bool(parsed["trace_director"]):
		runtime.config().trace_director = true
	return {"exit_code": 0, "output": "", "runtime": runtime}


static func _split_tiers(text: String) -> Dictionary:
	return _split_named(text, "--tiers")


static func _split_named(text: String, flag: String) -> Dictionary:
	var names := PackedStringArray()
	for part in text.split(","):
		var name := part.strip_edges()
		if name.is_empty():
			return {"error": "wyrd: %s has an empty name\n" % flag, "tiers": PackedStringArray()}
		names.append(name)
	if names.is_empty():
		return {"error": "wyrd: %s has an empty name\n" % flag, "tiers": PackedStringArray()}
	return {"error": "", "tiers": names}


static func _tier_names(value: Variant) -> PackedStringArray:
	var names := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for item in value:
			names.append(str(item))
	return names


static func _voice_check(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var rows := _voice_rows(loaded["pack"])
	var groups := {}
	for row in rows:
		var speaker := str(row["speaker"])
		if not groups.has(speaker):
			groups[speaker] = {"details": [], "lines": 0, "variable": 0, "voiced": 0}
		var group: Dictionary = groups[speaker]
		group["lines"] = int(group["lines"]) + 1
		if bool(row["voiced"]):
			group["voiced"] = int(group["voiced"]) + 1
		if bool(row["variable"]):
			group["variable"] = int(group["variable"]) + 1
			(group["details"] as Array).append(row)
	var names: Array = groups.keys()
	names.sort()
	var lines := PackedStringArray()
	var any_variable := false
	for name in names:
		var group: Dictionary = groups[name]
		lines.append("speaker=%s lines=%d voiced=%d variable=%d" % [name, int(group["lines"]), int(group["voiced"]), int(group["variable"])])
		var details: Array = group["details"]
		details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
		for detail in details:
			any_variable = true
			lines.append("  %s %s" % [str(detail["id"]), str(detail["context"])])
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 1 if any_variable else 0, "output": output}


static func _script_export(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var speaker := str(parsed["speaker"])
	var rows := _voice_rows(loaded["pack"])
	var kept: Array = []
	for row in rows:
		if str(row["speaker"]) == speaker:
			kept.append(row)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var lines := PackedStringArray()
	for row in kept:
		lines.append("id=%s text=%s tags=%s scene=%s context=%s" % [str(row["id"]), str(row["text"]), str(row["tags"]), str(row["scene"]), str(row["context"])])
	var body := ""
	if not lines.is_empty():
		body = "\n".join(lines) + "\n"
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _pot(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var body := WyrdPotExtractor.render(loaded["pack"])
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _defs(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var body := WyrdDefsWriter.render(loaded["pack"])
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _unvoiced_report(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var heard := _audio_map(str(parsed["audio"]))
	if not str(heard["error"]).is_empty():
		return {"exit_code": 1, "output": str(heard["error"])}
	var audio: Dictionary = heard["map"]
	var ids := PackedStringArray()
	var seen := {}
	for row in _voice_rows(loaded["pack"]):
		var id := str(row["id"])
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		ids.append(id)
	ids.sort()
	var locales: PackedStringArray = parsed["locales"]
	if locales.is_empty():
		locales = PackedStringArray(["en"])
	var ordered: Array = []
	for locale in locales:
		ordered.append(locale)
	ordered.sort()
	var lines := PackedStringArray()
	for locale in ordered:
		var have: Dictionary = audio.get(String(locale), {})
		lines.append("locale=%s" % String(locale))
		for id in ids:
			if not have.has(id):
				lines.append(id)
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _audio_map(path: String) -> Dictionary:
	if path.is_empty():
		return {"error": "", "map": {}}
	var resolved := _resolve(path)
	if not FileAccess.file_exists(resolved):
		return {"error": "wyrd: no such file: %s\n" % path, "map": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	if not (data is Dictionary):
		return {"error": "wyrd: audio file is not a JSON object\n", "map": {}}
	var mapped := {}
	for locale in (data as Dictionary).keys():
		var listed: Variant = (data as Dictionary)[locale]
		if not (listed is Array):
			return {"error": "wyrd: audio locale \"%s\" needs a list of line ids\n" % String(locale), "map": {}}
		var have := {}
		for id in listed:
			have[str(id)] = true
		mapped[String(locale)] = have
	return {"error": "", "map": mapped}


static func _voice_rows(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quest_bodies():
			for stage in quest.stages:
				_voice_stage(rows, quest.id, stage)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_voice_line(rows, item.line_def, item.line_def.speaker, "scene:%s" % scene.id, scene.id)
				if item.choice != null and not item.choice.line_id.is_empty():
					_voice_choice(rows, item.choice, scene.id)
		for story in file.storylets:
			for line_def in story.lines:
				var who := line_def.speaker if not line_def.speaker.is_empty() else story.speaker
				_voice_line(rows, line_def, who, "storylet:%s" % story.id, "")
	return rows


static func _voice_stage(rows: Array, quest_id: String, stage: WyrdStageDef) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_voice_line(rows, journal, journal.speaker, "journal:%s" % quest_id, "")
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.body != null:
			_voice_stage(rows, quest_id, variant.body)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_voice_stage(rows, quest_id, child)


static func _voice_line(rows: Array, line: WyrdLineDef, speaker: String, context: String, scene_id: String) -> void:
	if line == null or line.line_id.is_empty():
		return
	rows.append(_voice_row(line.line_id, speaker, context, scene_id, line.tags, line.prose))
	for item in line.variants:
		var variant := item as WyrdLineDef
		if variant == null:
			continue
		var variant_context := "variant:%s %s" % [variant.holder, context]
		_voice_line(rows, variant, speaker, variant_context, scene_id)


static func _voice_choice(rows: Array, choice: WyrdChoiceDef, scene_id: String) -> void:
	rows.append(_voice_row(choice.line_id, "", "choice:%s" % scene_id, scene_id, choice.tags, choice.label))


static func _voice_row(
	line_id: String,
	speaker: String,
	context: String,
	scene_id: String,
	tags: PackedStringArray,
	prose: WyrdExprNode
) -> Dictionary:
	var names := PackedStringArray()
	for tag in tags:
		names.append(tag)
	names.sort()
	return {
		"context": context,
		"id": line_id,
		"scene": scene_id,
		"speaker": speaker if not speaker.is_empty() else "-",
		"tags": ",".join(names),
		"text": WyrdLineDef.source_of(prose),
		"variable": WyrdLineDef.has_variable_text(prose),
		"voiced": tags.has("voiced"),
	}


static func _manifest(parsed: Dictionary) -> WyrdContentManifest:
	var path := str(parsed["manifest"])
	if not path.is_empty():
		return load(path) as WyrdContentManifest
	var created := WyrdContentManifest.new()
	created.pack_id = StringName(str(parsed["pack_id"]))
	created.language_version = int(parsed["language_version"])
	created.files = parsed["files"]
	return created


static func _load(parsed: Dictionary) -> Dictionary:
	var files: PackedStringArray = parsed["files"]
	if files.is_empty():
		return {"exit_code": 1, "output": "wyrd: %s needs one file or directory\n" % str(parsed["command"])}
	var diagnostics := WyrdDiagnostics.new()
	var commands: WyrdCommandSchema = null
	var skip_commands_note := false
	var commands_path := str(parsed["commands_path"])
	if not commands_path.is_empty():
		var read := WyrdPack.read_commands(commands_path, diagnostics)
		commands = read["schema"]
		skip_commands_note = bool(read["skip_note"])
	var secrecy := PackedStringArray()
	if str(parsed["command"]) == "check" and bool(parsed.get("tiers_set", false)):
		secrecy = _tier_names(parsed["tiers"])
	var pressure := PackedStringArray()
	if str(parsed["command"]) == "check" and bool(parsed.get("pressure_set", false)):
		pressure = _tier_names(parsed["pressure_tiers"])
	var pack := WyrdPack.compile(
		files,
		str(parsed["pack_id"]),
		int(parsed["language_version"]),
		commands,
		diagnostics,
		str(parsed["note_path"]),
		skip_commands_note,
		secrecy,
		pressure
	)
	return {"diagnostics": diagnostics, "exit_code": 0, "output": "", "pack": pack}


static func _options(args: PackedStringArray) -> Dictionary:
	var command := args[0]
	var strict := false
	var watch := false
	var dry_run := false
	var as_json := false
	var manifest := ""
	var out := ""
	var prefix := ""
	var save_path := ""
	var scope := ""
	var scope_id := ""
	var speaker := ""
	var scope_set := false
	var scope_id_set := false
	var speaker_set := false
	var audio := ""
	var locales := PackedStringArray()
	var tiers := PackedStringArray()
	var tiers_set := false
	var pressure_tiers := PackedStringArray()
	var pressure_set := false
	var secrecy_fact := ""
	var secrecy_fact_set := false
	var trace_director := false
	var filter := ""
	var scene := ""
	var scene_set := false
	var choice := ""
	var choice_set := false
	var from_minute := 0
	var from_set := false
	var to_minute := 0
	var to_set := false
	var file_path := ""
	var file_set := false
	var source_name := ""
	var source_set := false
	var offer_key := ""
	var key_set := false
	var offer_tier := ""
	var template_id := ""
	var seed_value := 1
	var seed_set := false
	var world_path := ""
	var cmds := PackedStringArray()
	var positionals: PackedStringArray = PackedStringArray()
	var listed := command == "why-not" or command == "storylets" or command == "cooldowns"
	var i := 1
	while i < args.size():
		var arg := args[i]
		if arg == "--strict":
			strict = true
		elif command == "check" and arg == "--watch":
			watch = true
		elif arg == "--dry-run":
			dry_run = true
		elif arg == "--json":
			as_json = true
		elif arg == "--manifest":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --manifest needs a path\n")
			manifest = args[i]
		elif arg == "-o":
			i += 1
			if i >= args.size():
				return _fail("wyrd: -o needs a path\n")
			out = args[i]
		elif arg == "--prefix":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --prefix needs text\n")
			prefix = args[i]
		elif arg == "--save":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --save needs a path\n")
			save_path = args[i]
		elif (command == "why-not" or command == "storylets") and arg == "--scope":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --scope needs a kind\n")
			scope = args[i]
			scope_set = true
		elif (command == "why-not" or command == "storylets") and arg == "--scope-id":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --scope-id needs an id\n")
			scope_id = args[i]
			scope_id_set = true
		elif (command == "why-not" or command == "storylets" or command == "script-export") and arg == "--speaker":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --speaker needs an id\n")
			speaker = args[i]
			speaker_set = true
		elif (listed or command == "check") and arg == "--tiers":
			i += 1
			if i >= args.size() or args[i].begins_with("--"):
				return _fail("wyrd: --tiers needs a list\n")
			var tier_list := _split_tiers(args[i])
			if not str(tier_list["error"]).is_empty():
				return _fail(str(tier_list["error"]))
			tiers = tier_list["tiers"]
			tiers_set = true
		elif command == "check" and arg == "--pressure-tiers":
			i += 1
			if i >= args.size() or args[i].begins_with("--"):
				return _fail("wyrd: --pressure-tiers needs a list\n")
			var pressure_list := _split_named(args[i], "--pressure-tiers")
			if not str(pressure_list["error"]).is_empty():
				return _fail(str(pressure_list["error"]))
			pressure_tiers = pressure_list["tiers"]
			pressure_set = true
		elif listed and arg == "--secrecy-fact":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --secrecy-fact needs a fact\n")
			secrecy_fact = args[i].strip_edges()
			secrecy_fact_set = true
		elif command == "choices" and arg == "--scene":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --scene needs an id\n")
			scene = args[i].strip_edges()
			scene_set = true
		elif command == "choices" and arg == "--choice":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --choice needs an id\n")
			choice = args[i].strip_edges()
			choice_set = true
		elif command == "choices" and arg == "--from":
			i += 1
			if i >= args.size() or not args[i].is_valid_int():
				return _fail("wyrd: --from needs a whole number of minutes\n")
			from_minute = int(args[i])
			from_set = true
		elif (command == "console" or command == "pot" or command == "defs") and arg == "--out":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --out needs a path\n")
			out = args[i]
		elif command == "console" and arg == "--cmd":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --cmd needs a command\n")
			cmds.append(args[i])
		elif command == "coverage" and arg == "--file":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --file needs a path\n")
			file_path = args[i].strip_edges()
			file_set = true
		elif command == "choices" and arg == "--to":
			i += 1
			if i >= args.size() or not args[i].is_valid_int():
				return _fail("wyrd: --to needs a whole number of minutes\n")
			to_minute = int(args[i])
			to_set = true
		elif command == "storylets" and arg == "--filter":
			i += 1
			if i >= args.size() or args[i].strip_edges().is_empty():
				return _fail("wyrd: --filter needs text\n")
			filter = args[i]
		elif (command == "why-not" or command == "storylets") and arg == "--trace-director":
			trace_director = true
		elif (command == "generate" or command == "why-not") and arg == "--source":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --source needs an id\n")
			source_name = args[i].strip_edges()
			source_set = true
		elif (command == "generate" or command == "why-not") and arg == "--key":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --key needs an id\n")
			offer_key = args[i].strip_edges()
			key_set = true
		elif (command == "generate" or command == "why-not") and arg == "--tier":
			i += 1
			if i >= args.size() or args[i].begins_with("--"):
				return _fail("wyrd: --tier needs a name\n")
			offer_tier = args[i]
		elif command == "generate" and arg == "--template":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --template needs an id\n")
			template_id = args[i].strip_edges()
		elif (command == "generate" or command == "why-not") and arg == "--seed":
			i += 1
			if i >= args.size() or not args[i].is_valid_int():
				return _fail("wyrd: --seed needs a whole number\n")
			seed_value = int(args[i])
			seed_set = true
		elif (command == "generate" or command == "why-not") and arg == "--world":
			i += 1
			if i >= args.size() or args[i].begins_with("--") or args[i].strip_edges().is_empty():
				return _fail("wyrd: --world needs a path\n")
			world_path = args[i].strip_edges()
		elif command == "unvoiced-report" and arg == "--locale":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --locale needs a locale\n")
			locales.append(args[i])
		elif command == "unvoiced-report" and arg == "--audio":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --audio needs a path\n")
			audio = args[i]
		elif arg.begins_with("-"):
			return _fail("wyrd: unknown option \"%s\"\n" % arg)
		else:
			positionals.append(arg)
		i += 1
	if command == "check" and watch and strict:
		return _fail("wyrd: --watch does not take --strict\n")
	if command == "script-export" and not speaker_set:
		return _fail("wyrd: script-export needs --speaker\n")
	if command == "pot" and (manifest.is_empty() or not positionals.is_empty()):
		return _fail("wyrd: pot needs --manifest\n")
	if command == "defs" and (manifest.is_empty() or not positionals.is_empty()):
		return _fail("wyrd: defs needs --manifest\n")
	if command == "generate":
		if not dry_run:
			return _fail("wyrd: generate needs --dry-run\n")
		if manifest.is_empty():
			return _fail("wyrd: generate needs --manifest\n")
		if not source_set:
			return _fail("wyrd: generate needs --source\n")
		if not key_set:
			return _fail("wyrd: generate needs --key\n")
		if not positionals.is_empty():
			return _fail("wyrd: generate takes no path\n")
	elif listed:
		if manifest.is_empty():
			return _fail("wyrd: %s needs --manifest\n" % command)
		if command == "why-not" and positionals.size() != 1:
			return _fail("wyrd: why-not needs one storylet id\n")
		if command != "why-not" and not positionals.is_empty():
			return _fail("wyrd: %s takes no path\n" % command)
		if command == "storylets" and trace_director and not scope_set:
			return _fail("wyrd: --trace-director needs --scope\n")
	else:
		if not manifest.is_empty() and not positionals.is_empty():
			return _fail("wyrd: pass a path or --manifest\n")
		if manifest.is_empty() and positionals.size() != 1:
			return _fail("wyrd: %s needs one file or directory\n" % command)
	var files := PackedStringArray()
	var pack_id := ""
	var language_version := 1
	var note_path := ""
	var commands_path := ""
	var manifest_path := ""
	if not manifest.is_empty():
		manifest_path = _resolve(manifest)
		if not FileAccess.file_exists(manifest_path):
			return _fail("wyrd: no such file: %s\n" % manifest)
		var resource := ResourceLoader.load(manifest_path)
		if not (resource is WyrdContentManifest):
			return _fail("wyrd: not a content manifest: %s\n" % manifest)
		var spec := resource as WyrdContentManifest
		pack_id = String(spec.pack_id)
		language_version = spec.language_version
		for listed_path in spec.files:
			files.append(_resolve(listed_path))
		commands_path = manifest_path.get_base_dir() + "/wyrd_commands.json"
		note_path = manifest_path
	else:
		var path := _resolve(positionals[0])
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return _fail("wyrd: no such file: %s\n" % positionals[0])
		files = _collect(path)
		pack_id = WyrdPack.pack_id_for(path)
		note_path = path
	return {
		"as_json": as_json,
		"audio": audio,
		"command": command,
		"cmds": cmds,
		"commands_path": commands_path,
		"dry_run": dry_run,
		"error": "",
		"files": files,
		"language_version": language_version,
		"locales": locales,
		"manifest": manifest_path if not manifest.is_empty() else "",
		"note_path": note_path,
		"out": out,
		"pack_id": pack_id,
		"prefix": prefix,
		"save": save_path,
		"scope": scope,
		"scope_id": scope_id,
		"scope_id_set": scope_id_set,
		"scope_set": scope_set,
		"file": file_path,
		"file_set": file_set,
		"choice": choice,
		"choice_set": choice_set,
		"filter": filter,
		"from_minute": from_minute,
		"from_set": from_set,
		"scene": scene,
		"scene_set": scene_set,
		"secrecy_fact": secrecy_fact,
		"to_minute": to_minute,
		"to_set": to_set,
		"secrecy_fact_set": secrecy_fact_set,
		"speaker": speaker,
		"speaker_set": speaker_set,
		"storylet": positionals[0] if command == "why-not" and positionals.size() == 1 else "",
		"source": source_name,
		"source_set": source_set,
		"offer_key": offer_key,
		"key_set": key_set,
		"offer_tier": offer_tier,
		"template": template_id,
		"seed": seed_value,
		"seed_set": seed_set,
		"world": world_path,
		"strict": strict,
		"watch": watch,
		"pressure_set": pressure_set,
		"pressure_tiers": pressure_tiers,
		"tiers": tiers,
		"tiers_set": tiers_set,
		"trace_director": trace_director,
	}


static func _fail(message: String) -> Dictionary:
	return {
		"as_json": false,
		"command": "",
		"commands_path": "",
		"dry_run": false,
		"error": message,
		"files": PackedStringArray(),
		"language_version": 1,
		"manifest": "",
		"note_path": "",
		"out": "",
		"pack_id": "",
		"prefix": "",
		"save": "",
		"strict": false,
		"watch": false,
	}


static func _resolve(argument: String) -> String:
	var path := argument.replace("\\", "/")
	while path.ends_with("/") and path.length() > 1:
		path = path.trim_suffix("/")
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path.trim_prefix("./")


static func _collect(path: String) -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	if FileAccess.file_exists(path):
		files.append(path)
		return files
	if DirAccess.dir_exists_absolute(path):
		_walk(path, files)
		files.sort()
	return files


static func _walk(dir_path: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var child := dir_path.trim_suffix("/") + "/" + file_name
			if dir.current_is_dir():
				_walk(child, files)
			elif file_name.ends_with(".wyrd"):
				files.append(child)
		file_name = dir.get_next()
	dir.list_dir_end()
