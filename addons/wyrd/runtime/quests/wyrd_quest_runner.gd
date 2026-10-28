class_name WyrdQuestRunner
extends RefCounted

## Quest status, stages, waits, variants, outcomes, and the journal.
##
## [code]start when[/code] and [code]waits_until[/code] advance only after the
## tick queue has re-checked them. A stage that names a scene offers it; the
## host opens it, and transitions wait until that scene ends normally. An
## aborted scene stays pending. The winning slot variant replaces the stage
## body. [code]unwilling[/code] and [code]barred[/code] are evaluated live and
## again on a tick when no scene or host step is open. Ending a scene finishes
## the current body before that re-check. [code]route_closed[/code] does not
## finish the quest. The quest
## completes when every declared outcome is [code]done[/code] or [code]failed[/code]
## and the current body has no transition. Any [code]failed[/code] outcome
## fails the quest instead. [method start] ignores [code]start when[/code].
## [method advance] leaves through the same path as a transition, including a
## stage that is still waiting. [code]on_empty: wait[/code] holds a stage when a
## slot is empty and no variant matched. Journal text and its date are frozen
## at the write. The default date is [code]day N, HH:MM[/code].
## [method summary] returns the frozen journal entries joined in order, or
## validated cached summary text, and does not write the journal. An
## [code]await_host[/code] step calls [method request_host_step] and pauses
## the remaining entry steps until [method complete_host_step]. A stage may
## name parallel [code]region[/code] blocks. Their active leaves are saved on
## the quest row and omitted when the stage has none.

## Fires when a quest status changes.
signal quest_state_changed(quest_id: String, status: StringName)
## Fires when a quest enters a stage.
signal stage_changed(quest_id: String, stage_id: String)
## Fires when a journal entry is written.
signal journal_entry_added(quest_id: String, entry_id: String, text: String)
## Fires when a quest's required pack is missing.
signal content_unavailable(quest_id: String, pack_id: String)
## @experimental
signal host_step_requested(quest_id: String, screen_id: StringName, fields: PackedStringArray)

## Quest status before the quest has been offered.
const DORMANT: StringName = &"dormant"
## Quest status after the quest is offered and before it is active.
const AVAILABLE: StringName = &"available"
## Quest status while the quest is running.
const ACTIVE: StringName = &"active"
## Quest status when every declared outcome is done and the body has no transition.
const COMPLETED: StringName = &"completed"
## Quest status when an outcome has failed.
const FAILED: StringName = &"failed"
## Quest status after the quest is abandoned or expires.
const ABANDONED: StringName = &"abandoned"
## Quest status when a required pack is missing.
const UNAVAILABLE: StringName = &"unavailable"
const _HOP_LIMIT := 24
## Returned while a region step list defers a top-level advance. Not a stage id.
const _LIFT := "\u0001"

## @experimental
var runtime: WyrdRuntime
var _states: Dictionary = {}
var _declared: Dictionary = {}
var _fired: Dictionary = {}
var _formatter: Callable = Callable()
var _text: WyrdText
## Quest ids visited every tick: active, or a start that is not a pure fact compare.
var _watch: Dictionary = {}
## Pure start-condition index to quest ids. Those stay dormant until the flag is true.
var _by_cond: Dictionary = {}
var _pure_start: Dictionary = {}
var _wake: Dictionary = {}
## Hop count of the stage entry whose step list is running. 0 when none is.
var _hop: int = 0
## Quest id whose entry steps or region steps are running. Empty otherwise.
var _steps_for: String = ""
## [code]stage[/code] or [code]region[/code] while that list is running.
var _step_level: String = ""
## The next [method _goto] came from [method advance] and should trace it.
var _from_advance: bool = false
## Top-level stage to enter after the current region step list returns.
var _lift_to: String = ""
## Template id to the last issued instance number.
var _counters: Dictionary = {}
## Instance id to param name to [code]{entity, kind, owner?, place?}[/code].
var _params: Dictionary = {}
## Instance id to the minute [method create_instance] ran. Not a quest-row field.
var _created: Dictionary = {}
## Quest rows written back unchanged: a missing template, or a quest the content no longer declares.
var _raw_rows: Dictionary = {}
## Instance id to a generator entry whose template is no longer in the content.
var _raw_instances: Dictionary = {}
## Template id to the set of instance ids kept raw on this load.
var _missing: Dictionary = {}
var _load_report: WyrdLoadReport


class QuestState extends RefCounted:
	var status: StringName = &"dormant"
	var stage_id: String = ""
	var variant: String = ""
	var outcomes: Dictionary = {}
	var offered: String = ""
	var slots: PackedStringArray = PackedStringArray()
	var scene_done: bool = false
	var host_screen: String = ""
	var host_fields: PackedStringArray = PackedStringArray()
	var host_returns: Dictionary = {}
	var journal: Array = []
	var entered: bool = false
	var held_empty: bool = false
	var waiting: String = ""
	var step_at: int = 0
	## Region id to [code]{stage, entered, step_at, regions}[/code]. Not a flat quest.
	var regions: Dictionary = {}
	## Set on a generated instance. Empty for a hand-written quest.
	var template: String = ""
	var n: int = 0
	var trail: PackedStringArray = PackedStringArray()


## @experimental
func bind(host: WyrdRuntime) -> void:
	runtime = host
	_text = WyrdText.new()
	_text.runtime = host


## @experimental
func reset() -> void:
	_states.clear(); _expiring.clear()
	_declared.clear()
	_fired.clear()
	_watch.clear()
	_wake.clear()
	_by_cond.clear()
	_pure_start.clear()
	_counters.clear()
	_params.clear()
	_created.clear()
	_raw_rows.clear()
	_raw_instances.clear()
	_missing.clear()
	_load_report = null
	if runtime != null and runtime.roles != null:
		runtime.roles.drop_instances()
	if runtime == null or runtime.content() == null:
		return
	var content := runtime.content()
	var ids: Array = content.quests.keys()
	ids.sort()
	for quest_id in ids:
		var quest: WyrdQuestDef = content.quests[quest_id]
		var state := QuestState.new()
		var key := String(quest_id)
		_states[key] = state
		_declared[key] = _collect(quest)
		_index_start(key, quest)
		if not _requires_ok(quest, content.pack_id):
			_set_status(key, state, UNAVAILABLE)
			content_unavailable.emit(key, _missing_pack(quest, content.pack_id))
		else:
			_sync_watch(key, state)


## @experimental
func register_date_formatter(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdQuestRunner.register_date_formatter: missing callable")
		return
	_formatter = fn


## @experimental
func format_date(minutes: int) -> String:
	if _formatter.is_valid():
		return str(_formatter.call(minutes))
	return WyrdText.game_date(minutes)


## @experimental
func note_ready(index: int) -> void:
	if not _by_cond.has(index):
		return
	for quest_id in _by_cond[index]:
		_wake[String(quest_id)] = true


## @experimental
func on_tick() -> void:
	var ids: Array = []
	if runtime != null and not runtime.locals_empty():
		ids = _states.keys()
		_wake.clear()
	else:
		var seen := {}
		for quest_id in _watch.keys():
			seen[quest_id] = true
			ids.append(quest_id)
		for quest_id in _wake.keys():
			if not seen.has(quest_id):
				ids.append(quest_id)
		_wake.clear()
	ids.sort()
	for quest_id in ids:
		var key := String(quest_id)
		var state := _states[quest_id] as QuestState
		var quest := _quest(key)
		if quest == null or state == null:
			continue
		if runtime != null:
			runtime.push_scope(key)
		if state.status == DORMANT or state.status == AVAILABLE:
			_consider_start(key, quest, state)
		elif state.status == ACTIVE:
			_continue(key, quest, state, 0, true)
		if runtime != null:
			runtime.pop_scope()


## @experimental
func clear_event_fires() -> void:
	_fired.clear()


## Runs the current stage's first matching [code]on[/code] handler for this emit.
## A stage handles one emit id once. A transition does not enter the next stage's
## handlers for the same emit.
## @experimental
func on_world_event(emit_id: int, event_name: StringName, payload: Dictionary) -> void:
	if runtime == null:
		return
	var locals := {}
	var payload_keys: Array = payload.keys()
	payload_keys.sort()
	for key in payload_keys:
		locals["event.%s" % String(key)] = payload[key]
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state == null or state.status != ACTIVE:
			continue
		var quest := _quest(String(quest_id))
		if quest == null:
			continue
		if runtime != null:
			runtime.push_scope(String(quest_id))
		_on_world_event_body(String(quest_id), quest, state, emit_id, String(event_name), locals)
		if runtime != null:
			runtime.pop_scope()
	runtime.clear_locals()


func _on_world_event_body(
	quest_id: String,
	quest: WyrdQuestDef,
	state: QuestState,
	emit_id: int,
	event_name: String,
	locals: Dictionary
) -> void:
	var body := _body_now(quest, state)
	if body == null:
		return
	var before := state.stage_id
	if not body.handlers.is_empty():
		var token := "%d|%s|%s" % [emit_id, quest_id, state.stage_id]
		if not _fired.has(token):
			runtime.bind_locals(locals)
			for handler in body.handlers:
				if handler.event_name != event_name:
					continue
				if handler.where_cond == null or not runtime.eval_bool(handler.where_cond):
					continue
				_fired[token] = true
				_run_armed_all(quest_id, handler.effects)
				_take_handler_transition(quest_id, quest, state, handler)
				break
			runtime.clear_locals()
	if state.status == ACTIVE and state.stage_id == before:
		runtime.bind_locals(locals)
		_dispatch_regions(quest_id, quest, state, body, state.regions, emit_id, event_name, "")
		runtime.clear_locals()


## @experimental
func on_scene_ended(scene_id: String, status: StringName, _reason: StringName) -> void:
	if status != &"ended":
		return
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state == null or state.status != ACTIVE:
			continue
		if state.offered == scene_id and not state.scene_done:
			state.scene_done = true
			if state.waiting.begins_with("scene:"):
				state.waiting = ""
			var quest := _quest(String(quest_id))
			if quest != null:
				_continue(String(quest_id), quest, state, 0)
			return


## @experimental
func note_outcome(quest_id: String, branch: StringName, value: StringName) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or branch == &"":
		return
	state.outcomes[String(branch)] = String(value)


## @experimental
func status(quest_id: String) -> StringName:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return &""
	return state.status


## @experimental
func stage(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.stage_id


## Active region leaves for [param quest_id], in the save shape. Empty for a flat stage.
## @experimental
func regions_of(quest_id: String) -> Dictionary:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return {}
	return _export_regions(state.regions)


## @experimental
func outcome(quest_id: String, branch: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null or not state.outcomes.has(branch):
		return ""
	return String(state.outcomes[branch])


## @experimental
func waiting_reason(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.waiting


## @experimental
func offered_scene(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.scene_done:
		return ""
	return state.offered


## @experimental
func variant_of(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.variant


## @experimental
func journal(quest_id: String) -> Array:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return []
	return state.journal.duplicate()

## Frozen journal entries joined in order, or validated cached summary text. Records [code]quest_summary[/code].
func summary(quest_id: String) -> String:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null:
		runtime.trace_add("quest_summary", {"quest": quest_id})
	var entries := journal(quest_id)
	if runtime == null or runtime.ai == null:
		return _joined_entries(entries)
	return runtime.ai.summary_for(quest_id, entries)


## [code]ai[/code] when [method summary] would return cached text now.
## Records nothing, sends nothing, and logs nothing.
func summary_source(quest_id: String) -> StringName:
	var entries := journal(quest_id)
	if entries.is_empty() or runtime == null or runtime.ai == null:
		return &"authored"
	if not runtime.ai.is_active() or not runtime.ai.locale_ok():
		return &"authored"
	var packet := runtime.ai.summary_packet(quest_id, entries)
	var key := runtime.ai.cache_key(&"journal_summary", packet)
	if runtime.ai.cached_text(key).is_empty():
		return &"authored"
	return &"ai"


func _joined_entries(entries: Array) -> String:
	var lines := PackedStringArray()
	for item in entries:
		if item is Dictionary:
			lines.append(str((item as Dictionary).get("text", "")))
	return "\n".join(lines)


## @experimental
func host_returns(quest_id: String) -> Dictionary:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return {}
	return state.host_returns.duplicate(true)


## @experimental
func offer_for(scene_id: String) -> Dictionary:
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state != null and state.status == ACTIVE and state.offered == scene_id and not state.scene_done:
			return {"quest": String(quest_id), "slots": state.slots.duplicate()}
	return {"quest": "", "slots": PackedStringArray()}


## @experimental
func template_counter(template_id: String) -> int:
	return int(_counters.get(template_id, 0))


## @experimental
func param_entity(instance_id: String, name: String) -> StringName:
	var rows: Variant = _params.get(instance_id, {})
	if not (rows is Dictionary) or not (rows as Dictionary).has(name):
		return &""
	var snap: Variant = (rows as Dictionary)[name]
	if not (snap is Dictionary):
		return &""
	return StringName(str((snap as Dictionary).get("entity", "")))


## @experimental
func active_count(template_id: String) -> int:
	var count := 0
	for quest_id in _states.keys():
		var state := _states[quest_id] as QuestState
		if state == null:
			continue
		if state.template == template_id and state.status == ACTIVE:
			count += 1
	return count


## @experimental
func export_generator() -> Dictionary:
	if _counters.is_empty():
		return {}
	var counters := {}
	var names: Array = _counters.keys()
	names.sort()
	for name in names:
		counters[String(name)] = int(_counters[name])
	var live := {}
	if runtime != null and runtime.roles != null:
		live = runtime.roles.instance_casts()
	var ids := {}
	for instance_id in live.keys():
		ids[String(instance_id)] = true
	for instance_id in _raw_instances.keys():
		ids[String(instance_id)] = true
	for instance_id in _params.keys():
		ids[String(instance_id)] = true
	for instance_id in _created.keys():
		if _expires_minutes(_template_id(String(instance_id), {})) > 0:
			ids[String(instance_id)] = true
	var ordered: Array = ids.keys()
	ordered.sort()
	var instances := {}
	for instance_id in ordered:
		var key := String(instance_id)
		if live.has(key):
			instances[key] = {"casts": live[key]}
		elif _raw_instances.has(key):
			instances[key] = (_raw_instances[key] as Dictionary).duplicate(true)
		var params := _param_row(key)
		if not params.is_empty():
			if not instances.has(key):
				instances[key] = {}
			(instances[key] as Dictionary)["params"] = params
		if _expires_minutes(_template_id(key, {})) > 0 and _created.has(key):
			if not instances.has(key):
				instances[key] = {}
			(instances[key] as Dictionary)["created"] = int(_created[key])
	return {"counters": counters, "instances": instances}


func _param_row(instance_id: String) -> Dictionary:
	var rows: Variant = _params.get(instance_id, {})
	if not (rows is Dictionary) or (rows as Dictionary).is_empty():
		return {}
	var copy := {}
	var names: Array = (rows as Dictionary).keys()
	names.sort()
	for name in names:
		var snap: Variant = (rows as Dictionary)[name]
		if snap is Dictionary:
			copy[String(name)] = (snap as Dictionary).duplicate(true)
	return copy


## @experimental
func import_generator(data: Dictionary, report: WyrdLoadReport) -> void:
	_counters.clear()
	_params.clear()
	_created.clear()
	_raw_instances.clear()
	_missing.clear()
	_load_report = report
	if runtime != null and runtime.roles != null:
		runtime.roles.drop_instances()
	var counters: Dictionary = data.get("counters", {}) if data.get("counters") is Dictionary else {}
	var names: Array = counters.keys()
	names.sort()
	for name in names:
		_counters[String(name)] = WyrdSave._whole(counters[name], 0)
	var listed: Dictionary = data.get("instances", {}) if data.get("instances") is Dictionary else {}
	var ids: Array = listed.keys()
	ids.sort()
	var content := runtime.content() if runtime != null else null
	for instance_id in ids:
		var key := String(instance_id)
		var entry: Dictionary = listed[instance_id] if listed[instance_id] is Dictionary else {}
		var template_id := _template_id(key, {})
		var known: bool = content != null and template_id != "" and content.templates.has(template_id)
		if known and runtime != null and runtime.roles != null:
			var quest: WyrdQuestDef = content.templates[template_id]
			runtime.roles.bind_instance(key, quest)
			var casts: Dictionary = entry.get("casts", {}) if entry.get("casts") is Dictionary else {}
			runtime.roles.install_casts(key, casts)
			_install_params(key, entry)
			_install_created(key, entry)
		else:
			_raw_instances[key] = entry.duplicate(true)
			_note_missing(template_id, key)


## @experimental
func export_state() -> Dictionary:
	var out := {}
	var ids: Array = _states.keys()
	for quest_id in _raw_rows.keys():
		if not _states.has(quest_id):
			ids.append(quest_id)
	ids.sort()
	for quest_id in ids:
		var key := String(quest_id)
		if _raw_rows.has(key) and not _states.has(key):
			out[key] = (_raw_rows[key] as Dictionary).duplicate(true)
			continue
		var state := _states.get(key) as QuestState
		if state == null:
			continue
		var fields: Array = []
		for field in state.host_fields:
			fields.append(String(field))
		var slots: Array = []
		for slot_name in state.slots:
			slots.append(String(slot_name))
		var row := {
			"entered": state.entered,
			"held_empty": state.held_empty,
			"host_fields": fields,
			"host_returns": state.host_returns.duplicate(true),
			"host_screen": state.host_screen,
			"journal": state.journal.duplicate(true),
			"offered": state.offered,
			"outcomes": state.outcomes.duplicate(true),
			"scene_done": state.scene_done,
			"slots": slots,
			"stage": state.stage_id,
			"status": String(state.status),
			"step_at": state.step_at,
			"variant": state.variant,
			"waiting": state.waiting,
		}
		var regions := _export_regions(state.regions)
		if not regions.is_empty():
			row["regions"] = regions
		if state.template != "":
			row["n"] = state.n
			row["template"] = state.template
		if not state.trail.is_empty():
			var trail: Array = []
			for entry in state.trail:
				trail.append(String(entry))
			row["trail"] = trail
		out[key] = row
	return out


## @experimental
func import_state(data: Dictionary) -> void:
	_fired.clear()
	_drop_instance_states()
	_raw_rows.clear()
	for quest_id in data.keys():
		var key := String(quest_id)
		var row: Variant = data[quest_id]
		if not (row is Dictionary):
			continue
		var item: Dictionary = row
		if _instance_row(key, item):
			_import_instance(key, item)
			continue
		var state := _states.get(key) as QuestState
		if state == null:
			_raw_rows[key] = item.duplicate(true)
			continue
		_load_row(key, state, item)
	_retrack()
	_warn_missing()


## Creates [code]<template>#<n>[/code] and starts it. Returns [code]""[/code] when the
## template is unknown, a cast key is not a [code]mode: cast[/code] slot, or a
## param key is not a param. A refusal changes nothing. There is no facade method
## and no replay input.
##
## @experimental
func create_instance(template_id: String, casts: Dictionary = {}, params: Dictionary = {}) -> String:
	var template := _template(template_id)
	if template == null:
		_trace_gen(template_id, "", 0, false, "unknown_template")
		return ""
	var cast_slots := {}
	for slot in template.slots:
		if slot.mode == &"cast":
			cast_slots[slot.name] = slot
	for key in casts.keys():
		if not cast_slots.has(String(key)):
			_trace_gen(template_id, "", 0, false, "bad_cast")
			return ""
	var param_names := {}
	if template is WyrdTemplateDef:
		for param in (template as WyrdTemplateDef).params:
			param_names[param.name] = true
	var stored := {}
	for key in params.keys():
		var name := String(key)
		if not param_names.has(name):
			_trace_gen(template_id, "", 0, false, "bad_param")
			return ""
		var snap := _normalize_param(params[key])
		if snap.is_empty():
			_trace_gen(template_id, "", 0, false, "bad_param")
			return ""
		stored[name] = snap
	var n := int(_counters.get(template_id, 0)) + 1
	var id := "%s#%d" % [template_id, n]
	_counters[template_id] = n
	var state := QuestState.new()
	state.template = template_id
	state.n = n
	_states[id] = state
	_note_expiring(id)
	_declared[id] = _collect(template)
	if not stored.is_empty():
		_params[id] = stored
	var minute := 0
	if runtime != null:
		minute = runtime.now_minutes()
	_created[id] = minute
	if runtime != null and runtime.roles != null:
		runtime.roles.bind_instance(id, template)
		for slot in template.slots:
			if slot.mode != &"cast":
				continue
			runtime.roles.freeze_given(id, slot, StringName(str(casts.get(slot.name, ""))))
	if runtime != null:
		runtime.push_scope(id)
	_trace_gen(template_id, id, n, true, "created")
	if runtime != null:
		runtime.note_instance_change()
	var pack_id := ""
	if runtime != null and runtime.content() != null:
		pack_id = runtime.content().pack_id
	if pack_id != "" and not _requires_ok(template, pack_id):
		_set_status(id, state, UNAVAILABLE)
		content_unavailable.emit(id, _missing_pack(template, pack_id))
		if runtime != null:
			runtime.pop_scope()
		return id
	start(id)
	if runtime != null:
		runtime.pop_scope()
	return id


func _normalize_param(value: Variant) -> Dictionary:
	if value is String or value is StringName:
		return {"entity": String(value), "kind": ""}
	if not (value is Dictionary):
		return {}
	var copy := (value as Dictionary).duplicate(true)
	if not copy.has("entity"):
		return {}
	copy["entity"] = WyrdSave.text_of(copy["entity"], "")
	if copy.has("kind"):
		copy["kind"] = WyrdSave.text_of(copy["kind"], "")
	if copy.has("owner"):
		copy["owner"] = WyrdSave.text_of(copy["owner"], "")
	if copy.has("place"):
		copy["place"] = WyrdSave.text_of(copy["place"], "")
	return copy


func _install_created(instance_id: String, entry: Dictionary) -> void:
	if entry.has("created"):
		_created[instance_id] = WyrdSave._whole(entry["created"], 0)
		return
	var minute := 0
	if runtime != null:
		minute = runtime.now_minutes()
	_created[instance_id] = minute


func _note_expiring(quest_id: String) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.template == "" or _expires_minutes(state.template) <= 0:
		_expiring.erase(quest_id)
		return
	_expiring[quest_id] = true


func _expires_minutes(template_id: String) -> int:
	var found := _template(template_id)
	if found is WyrdTemplateDef:
		return (found as WyrdTemplateDef).expires_minutes
	return 0


func _trace_expire(instance_id: String) -> void:
	if runtime == null:
		return
	runtime.trace_gen_line(
		"gen_expire",
		{"instance": instance_id, "reason": "timeout"},
		"wyrd gen_expire instance=%s reason=timeout" % instance_id
	)


func _install_params(instance_id: String, entry: Dictionary) -> void:
	var params: Variant = entry.get("params", {})
	if not (params is Dictionary) or (params as Dictionary).is_empty():
		return
	var stored := {}
	for name in (params as Dictionary).keys():
		var snap := _normalize_param((params as Dictionary)[name])
		if snap.is_empty():
			continue
		stored[String(name)] = snap
	if not stored.is_empty():
		_params[instance_id] = stored


## Starts [param quest_id] whatever its [code]start when[/code] says.
## [code]dormant[/code] and [code]available[/code] become [code]active[/code] at
## the first stage, through [method _consider_start] and [method _activate].
## [code]active[/code], [code]completed[/code], [code]failed[/code], and
## [code]abandoned[/code] warn and stay. [code]unavailable[/code] stays
## [code]unavailable[/code]. A running step list is already [code]active[/code],
## so a start of that quest warns and does not defer.
##
## @experimental
func start(quest_id: String) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if runtime != null:
		runtime.push_scope(quest_id)
	_start_quest(quest_id)
	if runtime != null:
		runtime.pop_scope()


func _start_quest(quest_id: String) -> void:
	var state := _states.get(quest_id) as QuestState
	var quest := _quest(quest_id)
	if state == null or quest == null:
		push_error("WyrdQuestRunner.start: unknown quest \"%s\"" % quest_id)
		return
	var reason := _start_reason(state.status)
	if reason != "started":
		if runtime != null and runtime._host_logs():
			runtime._host_mark("quests.start", [quest_id])
		_trace_start(quest_id, false, reason)
		if state.status != UNAVAILABLE:
			push_warning("WyrdQuestRunner.start: \"%s\" is %s" % [quest_id, reason])
		return
	var hops := _next_hop()
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("quests.start", [quest_id])
	_trace_start(quest_id, true, "started")
	if state.status == DORMANT:
		_set_status(quest_id, state, AVAILABLE)
	_activate(quest_id, quest, state, hops)


## Moves an [code]active[/code] quest to a top-level stage through [method _goto].
## [code]waits_until[/code] and a held-empty wait do not block it. The offered
## scene and the waiting reason are cleared. A pending host step or an open
## scene for this quest warns and stays. The current stage is a no-op. Any
## other status warns and stays. When both a host step and a scene are open,
## the reason is [code]host_step[/code]. A quest whose own step list is running
## applies the move after that list, like a divert. The returned stage id is
## that divert. Other callers get an empty string.
##
## @experimental
func advance(quest_id: String, stage_id: String) -> String:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var state := _states.get(quest_id) as QuestState
	var quest := _quest(quest_id)
	if state == null or quest == null:
		push_error("WyrdQuestRunner.advance: unknown quest \"%s\"" % quest_id)
		return ""
	if state.status != ACTIVE:
		if runtime != null and runtime._host_logs():
			runtime._host_mark("quests.advance", [quest_id, stage_id])
		_trace_advance(quest_id, state.stage_id, stage_id, false, "not_active")
		push_warning("WyrdQuestRunner.advance: \"%s\" is %s" % [quest_id, String(state.status)])
		return ""
	if _stage_by_id(quest, stage_id) == null:
		push_error("WyrdQuestRunner.advance: unknown stage \"%s\"" % stage_id)
		return ""
	if runtime != null and runtime._host_logs():
		runtime._host_mark("quests.advance", [quest_id, stage_id])
	if stage_id == state.stage_id:
		_trace_advance(quest_id, state.stage_id, stage_id, false, "same_stage")
		return ""
	if state.host_screen != "":
		_trace_advance(quest_id, state.stage_id, stage_id, false, "host_step")
		push_warning("WyrdQuestRunner.advance: \"%s\" is waiting on the host" % quest_id)
		return ""
	if _scene_open(quest_id):
		_trace_advance(quest_id, state.stage_id, stage_id, false, "scene_open")
		push_warning("WyrdQuestRunner.advance: \"%s\" has an open scene" % quest_id)
		return ""
	if _steps_for == quest_id and _step_level == "stage":
		_from_advance = true
		return stage_id
	if _steps_for == quest_id and _step_level == "region":
		_lift_to = stage_id
		return _LIFT
	_move(quest_id, quest, state, stage_id, _next_hop())
	return ""


## Instance ids whose template can expire. Not saved. Empty skips the tick walk.
var _expiring: Dictionary = {}


## Abandons generated instances whose [code]expires:[/code] has elapsed.
## An open scene of that instance waits for the next tick. Hand-written quests
## are skipped. This does not call [method abandon], so another open scene stays up.
## @experimental
func expire_due(now: int) -> void:
	if _expiring.is_empty():
		return
	var ids: Array = _expiring.keys()
	ids.sort()
	for quest_id in ids:
		var key := String(quest_id)
		var state := _states.get(key) as QuestState
		if state == null or state.template == "":
			continue
		var limit := _expires_minutes(state.template)
		if limit <= 0:
			continue
		if state.status != AVAILABLE and state.status != ACTIVE:
			continue
		var created := now
		if _created.has(key):
			created = int(_created[key])
		if now - created < limit:
			continue
		if runtime != null and runtime.dialogue != null and runtime.dialogue.is_open() and runtime.dialogue.open_quest_id() == key:
			continue
		state.waiting = ""
		state.entered = false
		state.held_empty = false
		_set_status(key, state, ABANDONED)
		_trace_expire(key)


## @experimental
func abandon(quest_id: String) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var state := _states.get(quest_id) as QuestState
	if state == null:
		push_error("WyrdQuestRunner.abandon: unknown quest \"%s\"" % quest_id)
		return
	if state.status != ACTIVE and state.status != AVAILABLE:
		push_error("WyrdQuestRunner.abandon: \"%s\" is %s" % [quest_id, String(state.status)])
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("quests.abandon", [quest_id])
	if runtime != null and runtime.dialogue != null and runtime.dialogue.is_open():
		runtime.dialogue.abort(&"abandoned")
	state.waiting = ""
	state.entered = false
	state.held_empty = false
	_set_status(quest_id, state, ABANDONED)


## @experimental
func request_host_step(quest_id: String, screen_id: StringName, fields: PackedStringArray = PackedStringArray()) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.status != ACTIVE:
		push_error("WyrdQuestRunner.request_host_step: \"%s\" is not active" % quest_id)
		return
	if screen_id == &"":
		push_error("WyrdQuestRunner.request_host_step: missing screen")
		return
	state.host_screen = String(screen_id)
	state.host_fields = fields.duplicate()
	state.waiting = "host:%s" % state.host_screen
	if runtime != null:
		var names: Array = []
		for field in state.host_fields:
			names.append(String(field))
		runtime.trace_add("host_step", {"fields": names, "quest": quest_id, "screen": state.host_screen})
	host_step_requested.emit(quest_id, screen_id, state.host_fields)


## @experimental
func complete_host_step(quest_id: String, values: Dictionary) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var state := _states.get(quest_id) as QuestState
	if state == null or state.host_screen.is_empty():
		push_error("WyrdQuestRunner.complete_host_step: \"%s\" is not waiting on the host" % quest_id)
		return
	if runtime != null:
		runtime.push_scope(quest_id)
	_complete_host_body(quest_id, state, values)
	if runtime != null:
		runtime.pop_scope()


func _complete_host_body(quest_id: String, state: QuestState, values: Dictionary) -> void:
	if runtime != null:
		runtime.trace_add("complete_host", {"quest": quest_id, "values": values.duplicate(true)})
	state.host_returns = values.duplicate(true)
	state.host_screen = ""
	if state.waiting.begins_with("host:"):
		state.waiting = ""
	var quest := _quest(quest_id)
	if quest != null:
		_continue(quest_id, quest, state, 0)


func _consider_start(quest_id: String, quest: WyrdQuestDef, state: QuestState) -> void:
	if not _cond_ready(quest.start_when):
		return
	if state.status == DORMANT:
		_set_status(quest_id, state, AVAILABLE)
	_activate(quest_id, quest, state)


func _activate(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int = 0) -> void:
	if quest.stages.is_empty():
		_set_status(quest_id, state, ACTIVE)
		return
	runtime.roles.begin_quest(quest_id)
	_set_status(quest_id, state, ACTIVE)
	state.stage_id = quest.stages[0].id
	state.entered = false
	_enter(quest_id, quest, state, hops)


func _continue(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int, recheck: bool = false) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	if state.status != ACTIVE:
		return
	if state.held_empty:
		var held := _stage_by_id(quest, state.stage_id)
		if held != null and _pick(quest_id, quest, held)["hold"]:
			state.waiting = "on_empty"
			return
		state.held_empty = false
		state.entered = false
	if not state.entered:
		_enter(quest_id, quest, state, hops)
		return
	if state.host_screen != "":
		state.waiting = "host:%s" % state.host_screen
		return
	if state.offered != "" and not state.scene_done:
		state.waiting = "scene:%s" % state.offered
		return
	if recheck and _adopt_pick(quest_id, quest, state, hops):
		return
	var body := _body_now(quest, state)
	if body == null:
		return
	if state.step_at < _entry_steps(body).size():
		_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body, hops))
		return
	_advance_region_map(quest_id, quest, state, body, state.regions, hops, "")
	if _consume_lift(quest_id, quest, state, hops):
		return
	if _wait_blocks(state, body):
		return
	state.waiting = ""
	if _take_transition(quest_id, quest, state, body, hops):
		return
	_maybe_finish(quest_id, state, body)


func _enter(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	var stage := _stage_by_id(quest, state.stage_id)
	if stage == null:
		push_error("WyrdQuestRunner: unknown stage \"%s\"" % state.stage_id)
		return
	_remember_stage(state)
	runtime.roles.enter_stage(quest_id, state.stage_id)
	var pick := _pick(quest_id, quest, stage)
	state.variant = String(pick["key"])
	_note_variant(quest_id, state.stage_id, state.variant)
	state.entered = true
	state.step_at = 0
	state.offered = ""
	state.slots = PackedStringArray()
	state.scene_done = false
	state.held_empty = false
	state.regions = {}
	stage_changed.emit(quest_id, state.stage_id)
	if pick["hold"]:
		state.held_empty = true
		state.waiting = "on_empty"
		return
	var body := pick["body"] as WyrdStageDef
	state.regions = _fresh_regions(quest_id, body, "")
	_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body, hops))


func _remember_stage(state: QuestState) -> void:
	if state.stage_id.is_empty():
		return
	var prior: Array = []
	for entry in state.trail:
		prior.append(String(entry))
	var next: Array = remember_trail(prior, state.stage_id)
	var packed := PackedStringArray()
	for entry in next:
		packed.append(String(entry))
	state.trail = packed


func _after_steps(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, hops: int, divert: String) -> void:
	if divert != "":
		var marked := _from_advance
		_from_advance = false
		_goto(quest_id, quest, state, divert, hops + 1, marked)
		return
	if state.host_screen != "":
		state.waiting = "host:%s" % state.host_screen
		return
	if state.offered != "":
		state.waiting = "scene:%s" % state.offered
		return
	_advance_region_map(quest_id, quest, state, body, state.regions, hops, "")
	if _consume_lift(quest_id, quest, state, hops):
		return
	if _wait_blocks(state, body):
		return
	state.waiting = ""
	if _take_transition(quest_id, quest, state, body, hops):
		return
	_maybe_finish(quest_id, state, body)


func _entry_steps(body: WyrdStageDef) -> Array:
	return entry_steps(body)


## Journal lines, effects, scenes, and host steps of one stage body, source order.
## @experimental
static func entry_steps(body: WyrdStageDef) -> Array:
	var steps: Array = []
	if body == null:
		return steps
	for journal_line in body.journals:
		steps.append({"at": journal_line.line, "journal": journal_line, "kind": &"journal"})
	for effect in body.effects:
		steps.append({"at": effect.line, "effect": effect, "kind": &"effect"})
	for scene in body.scenes:
		steps.append({"at": int(scene.get("line", 0)), "kind": &"scene", "scene": scene})
	for host in body.hosts:
		steps.append({
			"at": int(host.get("line", 0)),
			"fields": host.get("fields", PackedStringArray()),
			"kind": &"host",
			"screen": String(host.get("screen", "")),
		})
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	return steps


## How many entry steps [method entry_steps] lists. Shared with the load pass.
## @experimental
static func entry_step_count(body: WyrdStageDef) -> int:
	return entry_steps(body).size()


## The variant body whose [code]<slot>.<state>[/code] equals [param variant_key], else the stage.
## @experimental
static func stage_body(stage: WyrdStageDef, variant_key: String) -> WyrdStageDef:
	if stage == null or variant_key.is_empty():
		return stage
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and "%s.%s" % [variant.slot, String(variant.state)] == variant_key:
			return variant.body
	return stage


## Drops [param stage_id] if present, appends it, and keeps the newest 32.
## @experimental
static func remember_trail(entries: Array, stage_id: String) -> Array:
	var kept: Array = []
	for prior in entries:
		var id := str(prior)
		if id != stage_id:
			kept.append(id)
	kept.append(stage_id)
	while kept.size() > 32:
		kept.remove_at(0)
	return kept


func _run_steps(quest_id: String, state: QuestState, body: WyrdStageDef, hops: int) -> String:
	var saved_hop := _hop
	var saved_for := _steps_for
	var saved_level := _step_level
	_hop = hops
	_steps_for = quest_id
	_step_level = "stage"
	var divert := _run_step_list(quest_id, state, body)
	_hop = saved_hop
	_steps_for = saved_for
	_step_level = saved_level
	return divert


func _run_step_list(quest_id: String, state: QuestState, body: WyrdStageDef) -> String:
	var steps := _entry_steps(body)
	var offered := state.offered != ""
	while state.step_at < steps.size():
		var step: Dictionary = steps[state.step_at]
		state.step_at += 1
		var kind: StringName = step["kind"]
		if kind == &"journal":
			_write_journal(quest_id, state, step["journal"])
		elif kind == &"effect":
			var divert := _run_armed_one(quest_id, step["effect"])
			if divert != "":
				return divert
		elif kind == &"scene" and not offered:
			_offer(state, step["scene"])
			offered = true
		elif kind == &"host":
			var fields := PackedStringArray()
			var raw: Variant = step.get("fields", PackedStringArray())
			if raw is PackedStringArray:
				fields = raw
			request_host_step(quest_id, StringName(str(step.get("screen", ""))), fields)
			return ""
	return ""


func _offer(state: QuestState, scene: Dictionary) -> void:
	state.offered = String(scene.get("id", ""))
	state.scene_done = false
	var slots := PackedStringArray()
	for row in scene.get("with", []):
		slots.append(String(row.get("name", "")))
	state.slots = slots


func _write_journal(quest_id: String, state: QuestState, line: WyrdLineDef) -> void:
	if not runtime.secrecy_allows(line.secrecy):
		runtime.trace_secrecy("", line.line_id, line.secrecy, runtime.secrecy_unlocked_name(), "", "")
		return
	var minutes := runtime.now_minutes()
	var shown := runtime.apply_variant_secrecy(line, runtime.resolve_line(line))
	if runtime.coverage != null:
		runtime.coverage.hit("line", str(shown["id"]))
	var entry := {
		"date": format_date(minutes),
		"id": str(shown["id"]),
		"minutes": minutes,
		"text": str(shown["text"]),
	}
	state.journal.append(entry)
	journal_entry_added.emit(quest_id, line.line_id, String(entry["text"]))


func _take_handler_transition(quest_id: String, quest: WyrdQuestDef, state: QuestState, handler: WyrdOnEventDef) -> bool:
	for row in handler.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_goto(quest_id, quest, state, String(row.get("target", "")), 1)
		return true
	return false


func _take_transition(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, hops: int) -> bool:
	for row in body.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_goto(quest_id, quest, state, String(row.get("target", "")), hops + 1)
		return true
	return false


func _goto(quest_id: String, quest: WyrdQuestDef, state: QuestState, target: String, hops: int, from_advance: bool = false) -> void:
	if from_advance and hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	if _stage_by_id(quest, target) == null:
		push_error("WyrdQuestRunner: unknown stage \"%s\"" % target)
		return
	var previous := state.stage_id
	if from_advance:
		_trace_advance(quest_id, previous, target, true, "moved")
	if runtime != null:
		runtime.trace_add("transition", {"from": previous, "quest": quest_id, "to": target})
	state.stage_id = target
	state.entered = false
	state.held_empty = false
	state.variant = ""
	state.offered = ""
	state.scene_done = false
	state.waiting = ""
	_enter(quest_id, quest, state, hops)


func _maybe_finish(quest_id: String, state: QuestState, body: WyrdStageDef) -> void:
	if body == null or state.status != ACTIVE:
		return
	if state.offered != "" and not state.scene_done:
		return
	if state.host_screen != "" or state.held_empty:
		return
	if body.waits_until != null and not _cond_ready(body.waits_until):
		return
	if body.transitions.size() > 0:
		return
	var names: PackedStringArray = _declared.get(quest_id, PackedStringArray())
	var failed := false
	for branch in names:
		if not state.outcomes.has(String(branch)):
			return
		var value := String(state.outcomes[String(branch)])
		if value == "route_closed":
			return
		if value == "failed":
			failed = true
	state.waiting = ""
	_set_status(quest_id, state, FAILED if failed else COMPLETED)


func _wait_blocks(state: QuestState, body: WyrdStageDef) -> bool:
	if body == null or body.waits_until == null:
		return false
	if state.template != "" and runtime != null and runtime.defer_instance_waits():
		state.waiting = "waits_until: %s" % body.waits_text
		return true
	if _cond_ready(body.waits_until):
		return false
	state.waiting = "waits_until: %s" % body.waits_text
	return true


func _adopt_pick(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int) -> bool:
	var stage := _stage_by_id(quest, state.stage_id)
	if stage == null:
		return false
	var pick := _pick(quest_id, quest, stage)
	var key := String(pick["key"])
	var hold := bool(pick["hold"])
	if key == state.variant and hold == state.held_empty:
		return false
	state.variant = key
	_note_variant(quest_id, state.stage_id, key)
	state.step_at = 0
	state.offered = ""
	state.slots = PackedStringArray()
	state.scene_done = false
	state.held_empty = hold
	state.waiting = ""
	state.regions = {}
	if hold:
		state.waiting = "on_empty"
		return true
	var body := pick["body"] as WyrdStageDef
	state.regions = _fresh_regions(quest_id, body, "")
	_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body, hops))
	return true


func _note_variant(quest_id: String, stage_id: String, key: String) -> void:
	if key.is_empty() or runtime == null or runtime.coverage == null:
		return
	runtime.coverage.hit("variant", "%s.%s.%s" % [quest_id, stage_id, key])


func _pick(quest_id: String, quest: WyrdQuestDef, stage: WyrdStageDef) -> Dictionary:
	var chosen: WyrdVariantDef = null
	var chosen_at := -1
	for slot in quest.slots:
		var found: Dictionary = runtime.roles.resolve_slot(quest_id, StringName(slot.name), true)
		var variant: Variant = found.get("variant", null)
		if variant == null or not (variant is WyrdVariantDef):
			continue
		var at := _variant_index(stage, variant)
		if at < 0:
			continue
		if chosen == null or at < chosen_at:
			chosen = variant
			chosen_at = at
	if chosen != null:
		return {
			"body": chosen.body,
			"hold": false,
			"key": "%s.%s" % [chosen.slot, String(chosen.state)],
		}
	if quest.on_empty == "wait" and _any_empty(quest_id, quest):
		return {"body": null, "hold": true, "key": ""}
	return {"body": stage, "hold": false, "key": ""}


func _variant_index(stage: WyrdStageDef, variant: WyrdVariantDef) -> int:
	for i in stage.variants.size():
		if stage.variants[i] == variant:
			return i
	return -1


func _any_empty(quest_id: String, quest: WyrdQuestDef) -> bool:
	for slot in quest.slots:
		var state: StringName = runtime.roles.resolve_slot(quest_id, StringName(slot.name), false)["state"]
		if state == &"empty" or state == &"contested":
			return true
	return false


func _body_now(quest: WyrdQuestDef, state: QuestState) -> WyrdStageDef:
	return stage_body(_stage_by_id(quest, state.stage_id), state.variant)


func _cond_ready(cond: WyrdCompiledCondition) -> bool:
	if cond == null:
		return true
	var content := runtime.content()
	if content == null:
		return false
	var index := content.index_of(cond)
	if runtime.condition_dirty(index):
		return false
	if cond.uses_spatial:
		return runtime.condition_flag(index) != 0
	return runtime.eval_bool(cond)


func _fresh_regions(quest_id: String, stage: WyrdStageDef, path: String) -> Dictionary:
	var out := {}
	if stage == null:
		return out
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null or region.id.is_empty():
			continue
		var row := _blank_region(region)
		out[region.id] = row
		var stage_id := String(row.get("stage", ""))
		if stage_id != "":
			runtime.trace_region(quest_id, path + region.id, "", stage_id)
	return out


func _blank_region(region: WyrdRegionDef) -> Dictionary:
	var stage_id := ""
	if region != null and not region.stages.is_empty():
		stage_id = region.stages[0].id
	return {"entered": false, "regions": {}, "stage": stage_id, "step_at": 0}


func _region_stage(region: WyrdRegionDef, stage_id: String) -> WyrdStageDef:
	if region == null:
		return null
	for stage in region.stages:
		if stage.id == stage_id:
			return stage
	return null


func _region_blocked(state: QuestState) -> bool:
	if state.host_screen != "":
		return true
	return state.offered != "" and not state.scene_done


func _region_waiting(stage: WyrdStageDef) -> bool:
	if stage == null or stage.waits_until == null:
		return false
	return not _cond_ready(stage.waits_until)


func _advance_region_map(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, rows: Dictionary, hops: int, path: String) -> void:
	if body == null or hops > _HOP_LIMIT:
		if hops > _HOP_LIMIT:
			push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	for item in body.regions:
		var region := item as WyrdRegionDef
		if region == null or region.id.is_empty():
			continue
		var leaf := path + region.id
		if not rows.has(region.id) or not (rows[region.id] is Dictionary):
			var blank := _blank_region(region)
			rows[region.id] = blank
			var stage_id := String(blank.get("stage", ""))
			if stage_id != "":
				runtime.trace_region(quest_id, leaf, "", stage_id)
		_advance_region(quest_id, quest, state, region, rows[region.id], hops, leaf)
		if _lift_to != "":
			return


func _advance_region(quest_id: String, quest: WyrdQuestDef, state: QuestState, region: WyrdRegionDef, row: Dictionary, hops: int, path: String) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	var stage := _region_stage(region, String(row.get("stage", "")))
	if stage == null:
		return
	if not bool(row.get("entered", false)):
		_enter_region(quest_id, quest, state, region, row, stage, hops, path)
		return
	if _region_blocked(state):
		return
	if int(row.get("step_at", 0)) < _entry_steps(stage).size():
		var ran := _run_region_steps(quest_id, state, stage, row, hops)
		if bool(ran.get("lift", false)) or _lift_to != "":
			return
		if str(ran.get("divert", "")) != "":
			_region_goto(quest_id, quest, state, region, row, str(ran["divert"]), hops + 1, path)
			return
		if bool(ran.get("blocked", false)) or _region_blocked(state):
			return
	var nested: Dictionary = row.get("regions", {})
	_advance_region_map(quest_id, quest, state, stage, nested, hops, path + "/")
	row["regions"] = nested
	if _lift_to != "" or _region_blocked(state) or _region_waiting(stage):
		return
	_take_region_transition(quest_id, quest, state, region, row, stage, hops, path)


func _enter_region(quest_id: String, quest: WyrdQuestDef, state: QuestState, region: WyrdRegionDef, row: Dictionary, stage: WyrdStageDef, hops: int, path: String) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	row["entered"] = true
	row["step_at"] = 0
	row["regions"] = _fresh_regions(quest_id, stage, path + "/")
	var ran := _run_region_steps(quest_id, state, stage, row, hops)
	if bool(ran.get("lift", false)) or _lift_to != "":
		return
	if str(ran.get("divert", "")) != "":
		_region_goto(quest_id, quest, state, region, row, str(ran["divert"]), hops + 1, path)
		return
	if bool(ran.get("blocked", false)) or _region_blocked(state):
		return
	var nested: Dictionary = row.get("regions", {})
	_advance_region_map(quest_id, quest, state, stage, nested, hops, path + "/")
	row["regions"] = nested
	if _lift_to != "" or _region_blocked(state) or _region_waiting(stage):
		return
	_take_region_transition(quest_id, quest, state, region, row, stage, hops, path)


func _run_region_steps(quest_id: String, state: QuestState, stage: WyrdStageDef, row: Dictionary, hops: int) -> Dictionary:
	var saved_hop := _hop
	var saved_for := _steps_for
	var saved_level := _step_level
	_hop = hops
	_steps_for = quest_id
	_step_level = "region"
	var ran := _run_region_list(quest_id, state, stage, row)
	_hop = saved_hop
	_steps_for = saved_for
	_step_level = saved_level
	return ran


func _run_region_list(quest_id: String, state: QuestState, stage: WyrdStageDef, row: Dictionary) -> Dictionary:
	var steps := _entry_steps(stage)
	while int(row.get("step_at", 0)) < steps.size():
		var step: Dictionary = steps[int(row["step_at"])]
		var kind: StringName = step["kind"]
		if kind == &"scene" and state.offered != "" and not state.scene_done:
			return {"blocked": true, "divert": ""}
		if kind == &"host" and state.host_screen != "":
			return {"blocked": true, "divert": ""}
		row["step_at"] = int(row["step_at"]) + 1
		if kind == &"journal":
			_write_journal(quest_id, state, step["journal"])
		elif kind == &"effect":
			var divert := _run_armed_one(quest_id, step["effect"])
			if divert == _LIFT:
				return {"blocked": false, "divert": "", "lift": true}
			if divert != "":
				return {"blocked": false, "divert": divert}
		elif kind == &"scene":
			_offer(state, step["scene"])
		elif kind == &"host":
			var fields := PackedStringArray()
			var raw: Variant = step.get("fields", PackedStringArray())
			if raw is PackedStringArray:
				fields = raw
			request_host_step(quest_id, StringName(str(step.get("screen", ""))), fields)
			return {"blocked": true, "divert": ""}
	return {"blocked": false, "divert": ""}


func _region_goto(quest_id: String, quest: WyrdQuestDef, state: QuestState, region: WyrdRegionDef, row: Dictionary, target: String, hops: int, path: String) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	var stage := _region_stage(region, target)
	if stage == null:
		push_error("WyrdQuestRunner: unknown stage \"%s\"" % target)
		return
	var previous := String(row.get("stage", ""))
	row["stage"] = target
	row["entered"] = false
	row["step_at"] = 0
	row["regions"] = {}
	runtime.trace_region(quest_id, path, previous, target)
	_enter_region(quest_id, quest, state, region, row, stage, hops, path)


func _take_region_transition(quest_id: String, quest: WyrdQuestDef, state: QuestState, region: WyrdRegionDef, row: Dictionary, stage: WyrdStageDef, hops: int, path: String) -> bool:
	for edge in stage.transitions:
		var when: Variant = edge.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_region_goto(quest_id, quest, state, region, row, String(edge.get("target", "")), hops + 1, path)
		return true
	return false


func _dispatch_regions(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, rows: Dictionary, emit_id: int, event_name: String, path: String) -> void:
	if body == null:
		return
	for item in body.regions:
		var region := item as WyrdRegionDef
		if region == null or not rows.has(region.id) or not (rows[region.id] is Dictionary):
			continue
		var row: Dictionary = rows[region.id]
		var stage := _region_stage(region, String(row.get("stage", "")))
		if stage == null:
			continue
		var token := "%d|%s|%s%s|%s" % [emit_id, quest_id, path, region.id, String(row.get("stage", ""))]
		var moved := false
		if not stage.handlers.is_empty() and not _fired.has(token):
			for handler in stage.handlers:
				if handler.event_name != event_name:
					continue
				if handler.where_cond == null or not runtime.eval_bool(handler.where_cond):
					continue
				_fired[token] = true
				_run_armed_all(quest_id, handler.effects)
				if _take_region_handler(quest_id, quest, state, region, row, handler, path + region.id):
					moved = true
				break
		if moved:
			continue
		var nested: Dictionary = row.get("regions", {})
		_dispatch_regions(quest_id, quest, state, stage, nested, emit_id, event_name, path + region.id + "/")
		row["regions"] = nested


func _take_region_handler(quest_id: String, quest: WyrdQuestDef, state: QuestState, region: WyrdRegionDef, row: Dictionary, handler: WyrdOnEventDef, path: String) -> bool:
	for edge in handler.transitions:
		var when: Variant = edge.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_region_goto(quest_id, quest, state, region, row, String(edge.get("target", "")), 1, path)
		return true
	return false


func _export_regions(rows: Dictionary) -> Dictionary:
	var out := {}
	var ids: Array = rows.keys()
	ids.sort()
	for id in ids:
		var row: Variant = rows[id]
		if not (row is Dictionary):
			continue
		var item: Dictionary = row
		var copy := {
			"entered": bool(item.get("entered", false)),
			"stage": String(item.get("stage", "")),
			"step_at": int(item.get("step_at", 0)),
		}
		var nested: Variant = item.get("regions", {})
		if nested is Dictionary:
			var packed := _export_regions(nested)
			if not packed.is_empty():
				copy["regions"] = packed
		out[String(id)] = copy
	return out


func _import_regions(defs: Array, data: Dictionary) -> Dictionary:
	var by_id := {}
	for item in defs:
		var region := item as WyrdRegionDef
		if region != null and not region.id.is_empty():
			by_id[region.id] = region
	var out := {}
	for key in data.keys():
		var id := String(key)
		if not by_id.has(id) or not (data[key] is Dictionary):
			continue
		var region: WyrdRegionDef = by_id[id]
		var item: Dictionary = data[key]
		var stage_id := WyrdSave.text_of(item.get("stage", ""), "")
		var known := _region_stage(region, stage_id)
		var entered := WyrdSave.flag_of(item.get("entered", false), false)
		var step_at := WyrdSave._whole(item.get("step_at", 0), 0)
		if known == null:
			stage_id = ""
			if not region.stages.is_empty():
				stage_id = region.stages[0].id
			known = _region_stage(region, stage_id)
			entered = false
			step_at = 0
		var nested := {}
		var packed: Variant = item.get("regions", null)
		if known != null and packed is Dictionary:
			nested = _import_regions(known.regions, packed)
		out[id] = {"entered": entered, "regions": nested, "stage": stage_id, "step_at": step_at}
	return out


func _collect(quest: WyrdQuestDef) -> PackedStringArray:
	var found := {}
	for stage in quest.stages:
		_collect_stage(stage, found)
	var names := PackedStringArray()
	for branch in found.keys():
		names.append(String(branch))
	names.sort()
	return names


func _collect_stage(stage: WyrdStageDef, found: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		if effect.kind == &"outcome" and not effect.branch.is_empty():
			found[effect.branch] = true
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null:
			_collect_stage(variant.body, found)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_collect_stage(child, found)


func _requires_ok(quest: WyrdQuestDef, pack_id: String) -> bool:
	for item in quest.requires:
		if _pack_name(String(item)) != pack_id:
			return false
	return true


func _missing_pack(quest: WyrdQuestDef, pack_id: String) -> String:
	for item in quest.requires:
		var name := _pack_name(String(item))
		if name != pack_id:
			return name
	return ""


func _pack_name(token: String) -> String:
	if token.begins_with("pack."):
		return token.substr(5)
	return token


func _arm_effects(quest_id: String) -> void:
	runtime.effects.quest_id = quest_id
	runtime.effects.scene_id = ""
	runtime.effects.choice_id = ""


func _run_armed_all(quest_id: String, effects: Array) -> void:
	if runtime != null:
		runtime.push_scope(quest_id)
	_arm_effects(quest_id)
	if runtime != null and runtime.effects != null:
		runtime.effects.run_all(effects)
	if runtime != null:
		runtime.pop_scope()


func _run_armed_one(quest_id: String, effect: WyrdEffectDef) -> String:
	if runtime != null:
		runtime.push_scope(quest_id)
	_arm_effects(quest_id)
	var divert := ""
	if runtime != null and runtime.effects != null:
		divert = runtime.effects.run_one(effect)
	if runtime != null:
		runtime.pop_scope()
	return divert


func _set_status(quest_id: String, state: QuestState, next: StringName) -> void:
	if state.status == next:
		return
	var previous := String(state.status)
	state.status = next
	_sync_watch(quest_id, state)
	if runtime != null:
		runtime.trace_quest_status(quest_id, previous, String(next))
		if state.template != "":
			runtime.note_instance_change()
	quest_state_changed.emit(quest_id, next)


func _start_reason(status: StringName) -> String:
	match status:
		DORMANT, AVAILABLE:
			return "started"
		ACTIVE:
			return "active"
		COMPLETED:
			return "completed"
		FAILED:
			return "failed"
		ABANDONED:
			return "abandoned"
		UNAVAILABLE:
			return "unavailable"
		_:
			return String(status)


func _next_hop() -> int:
	if _steps_for == "":
		return 0
	return _hop + 1


func _move(quest_id: String, quest: WyrdQuestDef, state: QuestState, stage_id: String, hops: int) -> void:
	_goto(quest_id, quest, state, stage_id, hops, true)


func _consume_lift(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int) -> bool:
	if _lift_to == "":
		return false
	var target := _lift_to
	_lift_to = ""
	_goto(quest_id, quest, state, target, hops + 1, true)
	return true


func _scene_open(quest_id: String) -> bool:
	if runtime == null or runtime.dialogue == null or not runtime.dialogue.is_open():
		return false
	return runtime.dialogue.open_quest_id() == quest_id


func _trace_start(quest_id: String, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	runtime.trace_quest_start(quest_id, ok, reason)


func _trace_advance(quest_id: String, from_stage: String, to_stage: String, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	runtime.trace_quest_advance(quest_id, from_stage, to_stage, ok, reason)


func _index_start(quest_id: String, quest: WyrdQuestDef) -> void:
	if quest == null or quest.start_when == null or runtime == null or runtime.content() == null:
		return
	var index := runtime.content().index_of(quest.start_when)
	if index < 0 or not runtime.content().is_pure(index):
		return
	_pure_start[quest_id] = index
	var bucket: Array = _by_cond.get(index, [])
	bucket.append(quest_id)
	_by_cond[index] = bucket


func _sync_watch(quest_id: String, state: QuestState) -> void:
	var follow := state.status == ACTIVE
	if not follow and (state.status == DORMANT or state.status == AVAILABLE) and not _pure_start.has(quest_id):
		follow = true
	if follow:
		_watch[quest_id] = true
	else:
		_watch.erase(quest_id)


func _retrack() -> void:
	_watch.clear()
	for quest_id in _states.keys():
		var state := _states[quest_id] as QuestState
		if state != null:
			_sync_watch(String(quest_id), state)
	_catch_up()


func _catch_up() -> void:
	if runtime == null:
		return
	for index in _by_cond.keys():
		var at := int(index)
		if runtime.condition_dirty(at) or runtime.condition_flag(at) != 1:
			continue
		for quest_id in _by_cond[index]:
			_wake[String(quest_id)] = true


func _load_row(quest_id: String, state: QuestState, item: Dictionary) -> void:
	state.status = StringName(str(item.get("status", "dormant")))
	state.stage_id = WyrdSave.text_of(item.get("stage", ""), "")
	state.variant = WyrdSave.text_of(item.get("variant", ""), "")
	var outcomes: Variant = item.get("outcomes", {})
	state.outcomes = (outcomes as Dictionary).duplicate(true) if outcomes is Dictionary else {}
	state.offered = WyrdSave.text_of(item.get("offered", ""), "")
	state.scene_done = WyrdSave.flag_of(item.get("scene_done", false), false)
	state.host_screen = WyrdSave.text_of(item.get("host_screen", ""), "")
	var returns: Variant = item.get("host_returns", {})
	state.host_returns = (returns as Dictionary).duplicate(true) if returns is Dictionary else {}
	var journal: Array = []
	var journal_raw: Variant = item.get("journal", [])
	if journal_raw is Array:
		for entry in journal_raw:
			if entry is Dictionary:
				var copy: Dictionary = (entry as Dictionary).duplicate(true)
				copy["minutes"] = WyrdSave._whole(copy.get("minutes", 0), 0)
				journal.append(copy)
	state.journal = journal
	state.entered = WyrdSave.flag_of(item.get("entered", false), false)
	state.held_empty = WyrdSave.flag_of(item.get("held_empty", false), false)
	state.waiting = WyrdSave.text_of(item.get("waiting", ""), "")
	state.step_at = WyrdSave._whole(item.get("step_at", 0), 0)
	var slots := PackedStringArray()
	var slot_raw: Variant = item.get("slots", [])
	if slot_raw is Array:
		for slot_name in slot_raw:
			slots.append(WyrdSave.text_of(slot_name, ""))
	state.slots = slots
	var fields := PackedStringArray()
	var field_raw: Variant = item.get("host_fields", [])
	if field_raw is Array:
		for field in field_raw:
			fields.append(WyrdSave.text_of(field, ""))
	state.host_fields = fields
	var trail := PackedStringArray()
	var trail_raw: Variant = item.get("trail", [])
	if trail_raw is Array:
		for entry in trail_raw:
			if entry is String or entry is StringName:
				trail.append(String(entry))
	state.trail = trail
	state.regions = {}
	var quest := _quest(quest_id)
	var packed: Variant = item.get("regions", null)
	if quest != null and packed is Dictionary:
		var body := _body_now(quest, state)
		if body != null:
			state.regions = _import_regions(body.regions, packed)


func _import_instance(quest_id: String, item: Dictionary) -> void:
	var template_id := _template_id(quest_id, item)
	var content := runtime.content() if runtime != null else null
	var known: bool = content != null and template_id != "" and content.templates.has(template_id)
	if not known:
		_raw_rows[quest_id] = _coerce_row(item)
		_note_missing(template_id, quest_id)
		return
	var quest: WyrdQuestDef = content.templates[template_id]
	var state := QuestState.new()
	state.template = template_id
	state.n = WyrdSave._whole(item.get("n", 0), 0)
	_states[quest_id] = state
	_declared[quest_id] = _collect(quest)
	_load_row(quest_id, state, item)
	state.template = template_id
	state.n = WyrdSave._whole(item.get("n", 0), 0)
	_note_expiring(quest_id)


## Hand-written quest ids kept raw because the content no longer declares them.
## @experimental
func kept_quest_ids() -> PackedStringArray:
	var names := PackedStringArray()
	for quest_id in _raw_rows.keys():
		var key := String(quest_id)
		var row: Variant = _raw_rows[key]
		if not (row is Dictionary):
			continue
		if _instance_row(key, row):
			continue
		names.append(key)
	names.sort()
	return names


func _instance_row(quest_id: String, item: Dictionary) -> bool:
	if quest_id.contains("#"):
		return true
	return str(item.get("template", "")) != ""


func _drop_instance_states() -> void:
	var ids: Array = _states.keys()
	for quest_id in ids:
		var key := String(quest_id)
		var state := _states.get(key) as QuestState
		if not key.contains("#") and (state == null or state.template == ""):
			continue
		_states.erase(key)
		_expiring.erase(key)
		_declared.erase(key)
		_watch.erase(key)
		_wake.erase(key)
		if not _pure_start.has(key):
			continue
		var index := int(_pure_start[key])
		_pure_start.erase(key)
		if not _by_cond.has(index):
			continue
		var kept: Array = []
		for item in _by_cond[index]:
			if String(item) != key:
				kept.append(item)
		if kept.is_empty():
			_by_cond.erase(index)
		else:
			_by_cond[index] = kept


func _template(template_id: String) -> WyrdQuestDef:
	if runtime == null or runtime.content() == null:
		return null
	return runtime.content().templates.get(template_id) as WyrdQuestDef


func _template_id(instance_id: String, row: Dictionary) -> String:
	var named := str(row.get("template", ""))
	if named != "":
		return named
	var hash := instance_id.find("#")
	if hash <= 0:
		return ""
	return instance_id.substr(0, hash)


func _note_missing(template_id: String, instance_id: String) -> void:
	if template_id == "" or instance_id == "":
		return
	var bag: Dictionary = _missing.get(template_id, {})
	bag[instance_id] = true
	_missing[template_id] = bag


func _warn_missing() -> void:
	if _load_report == null:
		_missing.clear()
		return
	var names: Array = _missing.keys()
	names.sort()
	for template_id in names:
		var count := (_missing[template_id] as Dictionary).size()
		_load_report.diagnostics.add(
			WyrdDiagnostic.W_SAVE_TEMPLATE,
			"load_missing kind=template id=%s instances=%d" % [String(template_id), count],
			"",
			1,
			1,
			WyrdDiagnostic.SEVERITY_WARNING
		)
		_load_report.add_row("template", String(template_id), "", "", count, "W_SAVE_TEMPLATE")
	_missing.clear()
	_load_report = null


func _trace_gen(template_id: String, instance_id: String, n: int, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	runtime.trace_gen_create(template_id, instance_id, n, ok, reason)


func _coerce_row(item: Dictionary) -> Dictionary:
	var copy: Dictionary = item.duplicate(true)
	_coerce_numbers(copy)
	return copy


func _coerce_numbers(row: Dictionary) -> void:
	if row.has("step_at"):
		row["step_at"] = WyrdSave._whole(row["step_at"], 0)
	if row.has("n"):
		row["n"] = WyrdSave._whole(row["n"], 0)
	if row.has("minutes"):
		row["minutes"] = WyrdSave._whole(row["minutes"], 0)
	var journal: Variant = row.get("journal", null)
	if journal is Array:
		for entry in journal:
			if entry is Dictionary:
				_coerce_numbers(entry)
	var regions: Variant = row.get("regions", null)
	if regions is Dictionary:
		for region_id in (regions as Dictionary).keys():
			if (regions as Dictionary)[region_id] is Dictionary:
				_coerce_numbers((regions as Dictionary)[region_id])


func _quest(quest_id: String) -> WyrdQuestDef:
	if runtime == null or runtime.content() == null:
		return null
	var content := runtime.content()
	if content.quests.has(quest_id):
		return content.quests[quest_id] as WyrdQuestDef
	var state := _states.get(quest_id) as QuestState
	if state != null and state.template != "" and content.templates.has(state.template):
		return content.templates[state.template] as WyrdQuestDef
	return null


func _stage_by_id(quest: WyrdQuestDef, stage_id: String) -> WyrdStageDef:
	if quest == null:
		return null
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null
