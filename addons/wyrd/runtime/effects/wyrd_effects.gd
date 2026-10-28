class_name WyrdEffects
extends RefCounted

## Runs the slice effects, including belief and knowledge writes.
##
## @experimental
## [code]set[/code] and [code]inc[/code] write stored facts and keep provenance
## [code]scene[/code], [code]choice[/code], and [code]time[/code] (game minutes).
## A [code]do[/code] failure returns its [code]on_fail[/code] target: a label in
## a scene, or a stage in a quest. Set literals in deed arguments are read from
## the stored argument text, because the expression emitter does not push a set
## value. [code]start_quest[/code] and [code]advance[/code] call
## [method WyrdQuestRunner.start] and [method WyrdQuestRunner.advance].
## [code]assign_role[/code] and [code]vacate_role[/code] call the content role
## entry points. [code]adjust_baseline[/code] calls [method WyrdSocial.adjust_baseline].
## [code]unlock_topic[/code] and [code]lock_topic[/code] call [WyrdTopics].
## A repeat unlock does not emit [signal topic_unlocked] again.
## Out-of-slice effects cannot appear here; the compiler rejects them.

signal topic_unlocked(topic: StringName)
signal outcome_changed(quest_id: String, branch: StringName, value: StringName)

var runtime: WyrdRuntime
var quest_id: String = ""
var scene_id: String = ""
var choice_id: String = ""
var provenance: Dictionary = {}


func bind(host: WyrdRuntime) -> void:
	runtime = host


func export_state() -> Dictionary:
	var out := {}
	var keys: Array = provenance.keys()
	keys.sort()
	for key in keys:
		var row: Dictionary = provenance[key]
		out[String(key)] = {
			"choice": String(row.get("choice", "")),
			"scene": String(row.get("scene", "")),
			"time": int(row.get("time", 0)),
		}
	return out


func import_state(data: Dictionary) -> void:
	provenance.clear()
	var keys: Array = data.keys()
	keys.sort()
	for key in keys:
		var row: Variant = data[key]
		if not (row is Dictionary):
			continue
		var item: Dictionary = row
		provenance[String(key)] = {
			"choice": WyrdSave.text_of(item.get("choice", ""), ""),
			"scene": WyrdSave.text_of(item.get("scene", ""), ""),
			"time": WyrdSave._whole(item.get("time", 0), 0),
		}


func clear() -> void:
	quest_id = ""
	scene_id = ""
	choice_id = ""
	provenance.clear()


func provenance_of(key: String) -> Dictionary:
	if not provenance.has(key):
		return {}
	return (provenance[key] as Dictionary).duplicate()


## Drops provenance for facts that are not marked [code]recap[/code].
## A missing schema keeps every row. Returns kept, dropped, and the dropped keys.
func compact_provenance() -> Dictionary:
	var dropped: Array = []
	var kept := 0
	var keys: Array = provenance.keys()
	keys.sort()
	for key in keys:
		var name := String(key)
		if _keeps_provenance(name):
			kept += 1
			continue
		provenance.erase(name)
		dropped.append(name)
	return {"dropped": dropped.size(), "kept": kept, "keys": dropped}


func _keeps_provenance(key: String) -> bool:
	if runtime == null:
		return true
	return runtime.fact_is_recap(key)


func run_all(rows: Array) -> String:
	for row in rows:
		var effect := row as WyrdEffectDef
		if effect == null:
			continue
		var divert := run_one(effect)
		if divert != "":
			return divert
	return ""


func run_one(effect: WyrdEffectDef) -> String:
	if effect == null or runtime == null:
		return ""
	match effect.kind:
		&"set":
			_write(effect, false)
		&"inc":
			_write(effect, true)
		&"record_deed":
			_deed(effect)
		&"unlock_topic":
			if effect.topic.is_empty():
				push_error("WyrdEffects: unlock topic needs an id")
			elif runtime.topics == null:
				push_error("WyrdEffects: no topic store")
			else:
				var reason := runtime.topics.unlock(StringName(effect.topic))
				if reason == "unlocked":
					topic_unlocked.emit(StringName(effect.topic))
		&"lock_topic":
			if effect.topic.is_empty():
				push_error("WyrdEffects: lock topic needs an id")
			elif runtime.topics == null:
				push_error("WyrdEffects: no topic store")
			else:
				runtime.topics.lock(StringName(effect.topic))
		&"do":
			return _command(effect)
		&"outcome":
			outcome_changed.emit(quest_id, StringName(effect.branch), StringName(effect.outcome))
		&"believe", &"declare", &"learn":
			_belief(effect, true)
		&"unbelieve", &"retract", &"forget":
			_belief(effect, false)
		&"start_quest":
			if runtime.quests == null:
				push_error("WyrdEffects: no quest runner")
			else:
				runtime.quests.start(effect.quest)
		&"advance":
			if runtime.quests == null:
				push_error("WyrdEffects: no quest runner")
			else:
				return runtime.quests.advance(effect.quest, effect.stage)
		&"assign_role":
			if runtime.roles == null:
				push_error("WyrdEffects: no role runner")
			else:
				runtime.roles.assign_from_content(StringName(effect.role), _party(effect.entity, effect.entity_text))
		&"vacate_role":
			if runtime.roles == null:
				push_error("WyrdEffects: no role runner")
			else:
				runtime.roles.vacate_from_content(StringName(effect.role))
		&"create_document":
			if effect.document_id.is_empty() or effect.copy_id.is_empty():
				push_error("WyrdEffects: create document needs a document and a copy")
			elif runtime.documents == null:
				push_error("WyrdEffects: no document store")
			else:
				runtime.documents.create_copy(StringName(effect.document_id), effect.copy_id, {}, false)
		&"adjust_baseline":
			if runtime.social == null:
				push_error("WyrdEffects: no social graph")
			else:
				var amount: Variant = runtime.eval_value(effect.value)
				if not (amount is int) and not (amount is float):
					push_error("WyrdEffects: adjust baseline needs a number")
				else:
					runtime.social.adjust_baseline(
						_party(effect.a, effect.a_text),
						_party(effect.b, effect.b_text),
						StringName(effect.axis),
						float(amount)
					)
		_:
			push_error("WyrdEffects: effect \"%s\" is not in this slice" % String(effect.kind))
	return ""


func _belief(effect: WyrdEffectDef, write_value: bool) -> void:
	var key := effect.fact_key
	if key.is_empty() or key.contains("{"):
		push_error("WyrdEffects: \"%s\" is not a concrete stored fact" % key)
		return
	if effect.agent.is_empty():
		push_error("WyrdEffects: belief needs an agent or group")
		return
	var layer := "held"
	if effect.kind == &"believe" or effect.kind == &"unbelieve":
		layer = "believed"
	elif effect.kind == &"learn" or effect.kind == &"forget":
		layer = "known"
	var perspective := StringName("%s/%s" % [layer, effect.agent])
	if write_value:
		runtime.facts.set_in(StringName(key), runtime.eval_value(effect.value), perspective)
	else:
		runtime.facts.clear_in(StringName(key), perspective)


func _write(effect: WyrdEffectDef, is_inc: bool) -> void:
	var key := effect.fact_key
	if key.is_empty() or key.contains("{"):
		push_error("WyrdEffects: \"%s\" is not a concrete stored fact" % key)
		return
	var amount: Variant = runtime.eval_value(effect.value)
	var value := amount
	if is_inc:
		var current: Variant = runtime.facts.get_in(StringName(key))
		var base: Variant = 0 if current == null else current
		if amount == null or base == null:
			push_error("WyrdEffects: inc \"%s\" has no numeric value" % key)
			return
		value = base + amount
	if not runtime.facts.set_in(StringName(key), value):
		return
	provenance[key] = {"choice": choice_id, "scene": scene_id, "time": runtime.now_minutes()}


func _deed(effect: WyrdEffectDef) -> void:
	var args := _arg_map(effect)
	var actor := _name(_value(args, "actor"))
	if actor == &"":
		push_error("WyrdEffects: deed needs an actor")
		return
	var witnesses: Variant = null
	if args.has("witnesses"):
		var raw: Variant = _value(args, "witnesses")
		if raw is String or raw is StringName:
			witnesses = StringName(str(raw))
		else:
			witnesses = _strings(raw, _text(args, "witnesses"))
	var claim: Variant = null
	if not effect.fact_key.is_empty():
		claim = runtime.eval_value(effect.value)
		runtime.perception_claim(effect.fact_key, claim)
	var deed_id := runtime.deeds.record(
		StringName(effect.verb),
		actor,
		_name(_value(args, "target")),
		_name(_value(args, "place")),
		_strings(_value(args, "tags"), _text(args, "tags")),
		float(_value(args, "magnitude")) if args.has("magnitude") and _value(args, "magnitude") != null else 1.0,
		witnesses,
		_name(_value(args, "visibility")) if args.has("visibility") else &"public",
		bool(_value(args, "memorable")) if args.has("memorable") else false
	)
	runtime.clear_perception_claim()
	if effect.fact_key.is_empty() or deed_id < 0 or runtime.deeds.size() == 0:
		return
	var row := runtime.deeds.row_at(runtime.deeds.size() - 1)
	if int(row["id"]) != deed_id:
		return
	if _is_statement(args):
		_credibility(row, actor, StringName(effect.verb), effect.fact_key, claim)
	else:
		_reveal(row, effect.fact_key, claim)


func _is_statement(args: Dictionary) -> bool:
	return args.has("statement") and _value(args, "statement") == true


## Each witness is a listener. Acceptance writes [code]believed/<listener>[/code] only.
## A rejection writes nothing. The speaker is not added. [code]known/[/code], [code]world[/code],
## and [code]held/[/code] stay unchanged, and the claim is not copied onward.
func _credibility(row: Dictionary, speaker: StringName, verb: StringName, key: String, claim: Variant) -> void:
	var witnesses: PackedStringArray = row["witnesses"]
	var threshold := runtime.credibility_threshold()
	for listener in witnesses:
		var who := StringName(String(listener))
		var score := runtime.credibility_score(who, speaker)
		var accepted := score >= threshold
		runtime.trace_credibility(who, speaker, verb, key, claim, score, accepted)
		if accepted:
			runtime.facts.set_in(StringName(key), claim, StringName("believed/%s" % String(who)))


## [code]saw[/code] writes [code]known/[/code]. [code]heard[/code] and [code]inferred[/code]
## write [code]believed/[/code]. The actor and other agents are not copied in.
## A statement deed does not use this path.
func _reveal(row: Dictionary, key: String, claim: Variant) -> void:
	var witnesses: PackedStringArray = row["witnesses"]
	var modes: PackedStringArray = row["perception"]
	for i in witnesses.size():
		var layer := "known" if String(modes[i]) == "saw" else "believed"
		runtime.facts.set_in(StringName(key), claim, StringName("%s/%s" % [layer, String(witnesses[i])]))


func _command(effect: WyrdEffectDef) -> String:
	var adapter := runtime.adapter(WyrdActionAdapter) as WyrdActionAdapter
	var cmd := WyrdCommand.new()
	cmd.name = StringName(effect.command)
	var args := _arg_map(effect)
	for name in args.keys():
		cmd.args[name] = _value(args, String(name))
	var result := WyrdCommandResult.failed(&"no_adapter")
	if adapter == null:
		push_error("WyrdEffects: no action adapter for \"%s\"" % effect.command)
	else:
		result = adapter.execute(cmd)
	var ok := result != null and result.is_ok()
	var reason := ""
	if result != null:
		reason = String(result.reason)
	if runtime != null:
		runtime.trace_add("command", {"name": String(effect.command), "ok": ok, "reason": reason})
	if ok:
		return ""
	if effect.on_fail.is_empty():
		push_error("WyrdEffects: \"%s\" failed with no on_fail" % effect.command)
		return ""
	return effect.on_fail


func _arg_map(effect: WyrdEffectDef) -> Dictionary:
	var out := {}
	var positional := 0
	for row in effect.args:
		var spec: Dictionary = row
		var name := String(spec.get("name", ""))
		if name.is_empty():
			name = "#%d" % positional
			positional += 1
		out[name] = {"text": String(spec.get("text", "")), "value": runtime.eval_value(spec.get("compiled"))}
	return out


func _value(args: Dictionary, name: String) -> Variant:
	if not args.has(name):
		return null
	return (args[name] as Dictionary)["value"]


func _text(args: Dictionary, name: String) -> String:
	if not args.has(name):
		return ""
	return String((args[name] as Dictionary)["text"])


## A bare slot name of the running quest is that slot's holder.
## [code]holder()[/code], [code]player[/code], and an entity id are the evaluated name.
func _party(compiled: WyrdCompiledCondition, text: String) -> StringName:
	var bare := text.strip_edges()
	if _bare_name(bare) and _is_slot(bare):
		return runtime.roles.slot_holder(quest_id, StringName(bare))
	var value: Variant = runtime.eval_value(compiled)
	if value == null:
		return &""
	if value is String or value is StringName:
		return StringName(str(value))
	return &""


func _bare_name(text: String) -> bool:
	if text.is_empty() or text.contains("(") or text.contains(" ") or text.contains("."):
		return false
	return true


func _is_slot(name: String) -> bool:
	if quest_id.is_empty() or runtime == null or runtime.content() == null:
		return false
	var quest := runtime.content().quest_def(quest_id)
	if quest == null:
		return false
	for slot in quest.slots:
		if slot.name == name:
			return true
	return false


func _name(value: Variant) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


func _strings(value: Variant, text: String) -> PackedStringArray:
	var rows := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for item in value:
			if item != null:
				rows.append(str(item))
		return rows
	var body := text.strip_edges()
	if body.begins_with("[") and body.ends_with("]") and body.length() >= 2:
		body = body.substr(1, body.length() - 2)
		for part in body.split(","):
			var item := part.strip_edges()
			if not item.is_empty():
				rows.append(item)
	return rows
