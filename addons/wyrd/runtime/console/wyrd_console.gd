class_name WyrdConsole
extends RefCounted

## Playtest commands for one runtime.
##
## @experimental
## The verbs are the §3.3 set: set a fact; kill, vacate, or replace a role
## holder; advance time; fire an event; run a scene in a text UI.
## [code]advance[/code] and [code]choose[/code] walk that text UI.
## [code]quit[/code] and a blank line are prompt control. They are not commands.
## A release export must exclude [constant RELEASE_EXCLUDE]. The runtime does
## not reference this script, so the exclude removes it from the PCK.

const SOURCE := "console"
const RELEASE_EXCLUDE := "addons/wyrd/runtime/console/*"

var runtime: WyrdRuntime
var _scene_id: String = ""


func bind(host: WyrdRuntime) -> void:
	runtime = host
	_scene_id = ""


func exec(line: String) -> Dictionary:
	var text := line.strip_edges()
	if text.is_empty() or text.begins_with("#"):
		return _done(true, "", false)
	var tokens := _tokens(text)
	if tokens.is_empty():
		return _done(true, "", false)
	var verb := tokens[0]
	if verb == "quit":
		if tokens.size() != 1:
			push_error("Wyrd.console: quit takes no arguments")
			return _done(false, "", false)
		return _done(true, "", true)
	if not _known(verb):
		push_error("Wyrd.console: unknown command \"%s\"" % verb)
		return _done(false, "", false)
	if runtime == null or runtime.content() == null:
		push_error("Wyrd.console: load content first")
		return _done(false, "", false)
	match verb:
		"set":
			return _set_fact(tokens)
		"kill":
			return _depart(tokens, "kill", &"died")
		"vacate":
			return _depart(tokens, "vacate", &"left")
		"replace":
			return _replace(tokens)
		"time":
			return _time(tokens)
		"event":
			return _event(tokens)
		"scene":
			return _scene(tokens)
		"advance":
			return _advance(tokens)
		"choose":
			return _choose(tokens)
		_:
			push_error("Wyrd.console: unknown command \"%s\"" % verb)
			return _done(false, "", false)


func run_lines(lines: PackedStringArray) -> Dictionary:
	var chunks := PackedStringArray()
	var failed := false
	var stopped := false
	for line in lines:
		var step := exec(line)
		var text := str(step["output"])
		if not text.is_empty():
			chunks.append(text.trim_suffix("\n"))
		if not bool(step["ok"]):
			failed = true
		if bool(step["quit"]):
			stopped = true
			break
	var output := ""
	if not chunks.is_empty():
		output = "\n".join(chunks) + "\n"
	return {"ok": not failed, "output": output, "quit": stopped}


func _set_fact(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() < 3:
		_trace("set", tokens[1] if tokens.size() > 1 else "", "", false)
		push_error("Wyrd.console: set needs a fact and a value")
		return _done(false, "", false)
	var fact := tokens[1]
	var parts := PackedStringArray()
	for i in range(2, tokens.size()):
		parts.append(tokens[i])
	var value_text := " ".join(parts)
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		value_text,
		runtime.content().schema,
		diagnostics,
		"",
		1,
		1,
		WyrdCondition.CONTEXT_STORYLET,
		WyrdCondition.MINUTES_PER_DAY,
		null,
		false
	)
	if diagnostics.has_errors():
		_trace("set", fact, "", false)
		var item := diagnostics.items[0] as WyrdDiagnostic
		push_error("Wyrd.console: %s" % item.message)
		return _done(false, "", false)
	var expected: Variant = runtime.eval_value(compiled)
	var prior_scene := runtime.effects.scene_id
	var prior_choice := runtime.effects.choice_id
	runtime.effects.scene_id = SOURCE
	runtime.effects.choice_id = "set"
	var effect := WyrdEffectDef.new()
	effect.kind = &"set"
	effect.fact_key = fact
	effect.value = compiled
	runtime.effects.run_one(effect)
	runtime.effects.scene_id = prior_scene
	runtime.effects.choice_id = prior_choice
	var stored: Variant = runtime.facts.get_in(StringName(fact))
	var prov := runtime.effects.provenance_of(fact)
	var same_value := false
	if stored == expected:
		same_value = true
	var wrote := same_value and str(prov.get("scene", "")) == SOURCE and str(prov.get("choice", "")) == "set"
	_trace("set", fact, "", wrote)
	if not wrote:
		return _done(false, "", false)
	return _done(true, "set %s = %s\n" % [fact, str(stored)], false)


func _depart(tokens: PackedStringArray, verb: String, reason: StringName) -> Dictionary:
	if tokens.size() != 2:
		var partial := tokens[1] if tokens.size() > 1 else ""
		_trace(verb, partial, partial, false)
		push_error("Wyrd.console: %s needs one role" % verb)
		return _done(false, "", false)
	var role_id := StringName(tokens[1])
	if not _role_known(role_id):
		_trace(verb, tokens[1], tokens[1], false)
		push_error("Wyrd.console: unknown role \"%s\"" % tokens[1])
		return _done(false, "", false)
	var before := runtime.roles.holder(role_id)
	if before == &"":
		_trace(verb, tokens[1], tokens[1], false)
		push_error("Wyrd.console: \"%s\" has no holder" % tokens[1])
		return _done(false, "", false)
	runtime.roles.vacate(role_id, reason)
	var after := runtime.roles.holder(role_id)
	var changed := after != before
	_trace(verb, tokens[1], tokens[1], changed)
	if not changed:
		push_error("Wyrd.console: \"%s\" did not change holder" % tokens[1])
		return _done(false, "", false)
	var label := "killed" if verb == "kill" else "vacated"
	if after == &"":
		return _done(true, "%s %s\n" % [label, tokens[1]], false)
	return _done(true, "%s %s holder=%s\n" % [label, tokens[1], String(after)], false)


func _replace(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() != 3:
		var partial := tokens[1] if tokens.size() > 1 else ""
		_trace("replace", partial, partial, false)
		push_error("Wyrd.console: replace needs a role and an entity")
		return _done(false, "", false)
	var role_id := StringName(tokens[1])
	var entity := StringName(tokens[2])
	if not _role_known(role_id):
		_trace("replace", tokens[1], tokens[1], false)
		push_error("Wyrd.console: unknown role \"%s\"" % tokens[1])
		return _done(false, "", false)
	if runtime.roles.abolished(role_id):
		_trace("replace", tokens[1], tokens[1], false)
		push_error("Wyrd.console: \"%s\" is abolished" % tokens[1])
		return _done(false, "", false)
	runtime.roles.assign(role_id, entity)
	var ok := runtime.roles.holder(role_id) == entity
	_trace("replace", tokens[1], tokens[1], ok)
	if not ok:
		return _done(false, "", false)
	return _done(true, "replaced %s holder=%s\n" % [tokens[1], tokens[2]], false)


func _time(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() != 2 or not tokens[1].is_valid_int() or int(tokens[1]) < 0:
		var partial := tokens[1] if tokens.size() > 1 else ""
		_trace("time", partial, "", false)
		push_error("Wyrd.console: time needs one whole number of minutes")
		return _done(false, "", false)
	var minutes := int(tokens[1])
	runtime.tick(minutes)
	_trace("time", tokens[1], "", true)
	return _done(true, "time %d\n" % minutes, false)


func _event(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() < 2:
		_trace("event", "", "", false)
		push_error("Wyrd.console: event needs a name")
		return _done(false, "", false)
	var payload := {}
	for i in range(2, tokens.size()):
		var token := tokens[i]
		var cut := token.find("=")
		if cut <= 0 or cut == token.length() - 1:
			_trace("event", tokens[1], "", false)
			push_error("Wyrd.console: event field \"%s\" needs a value" % token)
			return _done(false, "", false)
		var field := token.substr(0, cut)
		if payload.has(field):
			_trace("event", tokens[1], "", false)
			push_error("Wyrd.console: duplicate event field \"%s\"" % field)
			return _done(false, "", false)
		payload[field] = _field_value(token.substr(cut + 1))
	var before := _last_emit_id()
	runtime.events.emit(StringName(tokens[1]), payload)
	var ok := _last_emit_id() != before
	_trace("event", tokens[1], "", ok)
	if not ok:
		return _done(false, "", false)
	return _done(true, "event %s\n" % tokens[1], false)


func _scene(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() != 2:
		var partial := tokens[1] if tokens.size() > 1 else ""
		_trace("scene", partial, "", false)
		push_error("Wyrd.console: scene needs one id")
		return _done(false, "", false)
	if runtime.dialogue.is_open():
		_trace("scene", tokens[1], "", false)
		push_error("Wyrd.console: a scene is already open")
		return _done(false, "", false)
	if not runtime.content().scenes.has(tokens[1]):
		_trace("scene", tokens[1], "", false)
		push_error("Wyrd.console: unknown scene \"%s\"" % tokens[1])
		return _done(false, "", false)
	_scene_id = tokens[1]
	runtime.dialogue.open_scene(tokens[1])
	_trace("scene", tokens[1], "", true)
	return _done(true, _render_scene(), false)


func _advance(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() != 1:
		_trace("advance", _scene_id, "", false)
		push_error("Wyrd.console: advance takes no arguments")
		return _done(false, "", false)
	if runtime.dialogue.line() == null:
		_trace("advance", _scene_id, "", false)
		push_error("Wyrd.console: no line is waiting")
		return _done(false, "", false)
	runtime.dialogue.advance()
	_trace("advance", _scene_id, "", true)
	return _done(true, _render_scene(), false)


func _choose(tokens: PackedStringArray) -> Dictionary:
	if tokens.size() != 2 or not tokens[1].is_valid_int():
		_trace("choose", _scene_id, "", false)
		push_error("Wyrd.console: choose needs one number")
		return _done(false, "", false)
	var shown := int(tokens[1])
	var views := runtime.dialogue.choices()
	if views.is_empty():
		_trace("choose", _scene_id, "", false)
		push_error("Wyrd.console: no choices are waiting")
		return _done(false, "", false)
	var index := shown - 1
	if index < 0 or index >= views.size():
		_trace("choose", _scene_id, "", false)
		push_error("Wyrd.console: choice %d is out of range" % shown)
		return _done(false, "", false)
	var picked := views[index] as WyrdChoiceView
	if not picked.enabled:
		_trace("choose", _scene_id, "", false)
		push_error("Wyrd.console: choice %d is disabled" % shown)
		return _done(false, "", false)
	runtime.dialogue.choose(index)
	_trace("choose", _scene_id, "", true)
	return _done(true, _render_scene(), false)


func _render_scene() -> String:
	if runtime.dialogue == null:
		return ""
	if not runtime.dialogue.is_open():
		var ended := _scene_id
		_scene_id = ""
		if ended.is_empty():
			return "scene ended\n"
		return "scene ended %s\n" % ended
	var shown := runtime.dialogue.line()
	if shown != null:
		var who := shown.display_name
		if who.is_empty():
			who = String(shown.speaker)
		return "%s: %s\n" % [who, shown.text]
	var views := runtime.dialogue.choices()
	if views.is_empty():
		return ""
	var rows := PackedStringArray()
	for view in views:
		var choice := view as WyrdChoiceView
		rows.append("%d %s" % [choice.index + 1, choice.text])
	return "\n".join(rows) + "\n"


func _role_known(role_id: StringName) -> bool:
	return runtime.content().roles.has(String(role_id))


func _last_emit_id() -> int:
	if runtime.events.recent.is_empty():
		return 0
	var row: Dictionary = runtime.events.recent[runtime.events.recent.size() - 1]
	return int(row.get("id", 0))


func _field_value(token: String) -> Variant:
	if token == "true":
		return true
	if token == "false":
		return false
	if token.is_valid_int() and not token.contains("."):
		return int(token)
	if token.is_valid_float() and token.contains("."):
		return float(token)
	return StringName(token)


func _trace(command: String, key: String, role_id: String, ok: bool) -> void:
	if runtime == null or runtime.trace == null or not runtime.trace.enabled:
		return
	var fields := {
		"command": command,
		"key": key,
		"ok": ok,
		"path": SOURCE,
		"role": role_id,
		"source": SOURCE,
	}
	if not runtime._trace_allows(fields):
		return
	runtime.trace_add("console", fields)
	var shown_key := key if not key.is_empty() else "-"
	var shown_role := role_id if not role_id.is_empty() else "-"
	var flag := "true" if ok else "false"
	print(
		"wyrd console command=%s key=%s role=%s source=console ok=%s"
		% [command, shown_key, shown_role, flag]
	)


func _known(verb: String) -> bool:
	match verb:
		"set", "kill", "vacate", "replace", "time", "event", "scene", "advance", "choose":
			return true
		_:
			return false


func _done(ok: bool, output: String, quit: bool) -> Dictionary:
	return {"ok": ok, "output": output, "quit": quit}


static func _tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	for i in text.length():
		var ch := text[i]
		if ch == " " or ch == "\t":
			if not current.is_empty():
				out.append(current)
				current = ""
		else:
			current += ch
	if not current.is_empty():
		out.append(current)
	return out
