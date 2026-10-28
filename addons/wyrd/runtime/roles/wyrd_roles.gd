class_name WyrdRoles
extends RefCounted

## Role bindings and the quest-slot subset.
##
## A binding holds [code]holder[/code], [code]since[/code], [code]status[/code]
## ([code]default[/code], [code]successor[/code], [code]empty[/code],
## [code]contested[/code]), and [code]history[/code]. [method assign] is host
## setup for the default holder. [method define] stores the same fields as a
## [code]role[/code] block. [method eligible] tests [code]candidate[/code].
## [method vacate] runs [code]relation(...)[/code], [code]faction_assigns(...)[/code],
## [code]host_decides[/code], and [code]election[/code]. [code]election[/code] and
## [code]host_decides[/code] leave the role [code]contested[/code] until
## [method assign]. [code]vacancy: abolish[/code] runs when a strategy finds
## nobody. [code]live[/code] follows the role. [code]locked_at[/code] freezes in
## [method enter_stage]. [code]cast[/code] picks once in [method begin_quest]
## from [method WyrdWorldAdapter.candidates] and freezes that entity. A slot with
## [code]kind: object[/code] or [code]kind: item[/code] passes that kind and the
## [code]has_tag[/code] symbol to [code]candidates[/code], freezes the pick, and
## resolves only [code]locked_gone[/code], [code]empty[/code], and [code]default[/code].
## An item pick also stores [code]owner[/code] when an inventory adapter is registered.
## Slot state [code]hostile[/code]
## means disposition toward [code]player[/code] is below the threshold.
## Precedence is [code]locked_gone[/code], [code]contested[/code], [code]empty[/code],
## then [code]barred[/code], [code]hostile[/code], [code]unwilling[/code],
## [code]successor[/code], and [code]default[/code]. The first of those with a
## declared variant on the current stage wins. [code]contested[/code] with no
## variant uses the [code]empty[/code] variant and stays [code]contested[/code].
## [code]locked_gone[/code] is a frozen [code]locked_at[/code] holder who was
## vacated or is not alive. A departure whose history reason is [code]assign[/code]
## is not a vacate, whether the host or content assigned the new holder.
## A secret holder's key [code]role.<id>.holder[/code] is in [code]known/[/code]
## only for agents passed to [method tell].

## Fires when the holder changes.
signal role_holder_changed(role_id: StringName, old_holder: StringName, new_holder: StringName)
## Fires when the role is left empty or abolished.
signal role_vacant(role_id: StringName)
## Emitted when [code]host_decides[/code] is waiting for [method assign].
## @experimental
signal succession_requested(role_id: StringName, departed: StringName)
## Emitted when [code]election[/code] is waiting for [method assign].
signal election_needed(role_id: StringName, departed: StringName)

## Entity id used when a slot checks disposition toward the player.
const PLAYER: StringName = &"player"
## Binding status when the role has no holder.
const EMPTY: StringName = &"empty"
## Binding status after assign, and the slot state when no earlier state applies.
const DEFAULT: StringName = &"default"
## Binding status after a strategy picks the next holder.
const SUCCESSOR: StringName = &"successor"
## Slot state when disposition toward the player is below the threshold.
const HOSTILE: StringName = &"hostile"
## Slot state when the frozen holder was vacated or is not alive.
const LOCKED_GONE: StringName = &"locked_gone"
## Slot state when a barred variant's condition matches the holder.
const BARRED: StringName = &"barred"
## Slot state when an unwilling variant's condition matches the holder.
const UNWILLING: StringName = &"unwilling"
## Binding status while an election or a host decision is waiting.
const CONTESTED: StringName = &"contested"
const _STATE_ORDER: PackedStringArray = [
	"locked_gone", "contested", "empty", "barred", "hostile", "unwilling", "successor", "default",
]

## @experimental
var social: WyrdSocial
## @experimental
var deeds: WyrdDeedLog
## @experimental
var facts: WyrdFactStore
## @experimental
var runtime: WyrdRuntime
## @experimental
var clock: Callable = Callable()
## @experimental
var config_of: Callable = Callable()
## @experimental
var content_of: Callable = Callable()
## @experimental
var world_of: Callable = Callable()
## [code]inventory_of()[/code] returns the registered [WyrdInventoryAdapter], or null.
## @experimental
var inventory_of: Callable = Callable()
## [code]eval_with(condition, locals)[/code] evaluates one eligibility or cast condition.
## @experimental
var eval_with: Callable = Callable()
## [code]eval_value(condition, locals)[/code] evaluates one cast pin expression.
## @experimental
var eval_value: Callable = Callable()
## Internal. Default true. Not a [WyrdConfig] field and not saved.
## @experimental
var cast_index_enabled: bool = true
var _cast_index := WyrdCastIndex.new()
var _indexed_pool: bool = false
var _indexed_ready: bool = false
var _indexed_digest: int = 0
var _indexed_filter: String = ""
## [code]trace_of(kind, fields)[/code] records one eligibility, slot-state, succession, or cast line. Optional.
## @experimental
var trace_of: Callable = Callable()
## [code]stage_of(quest_id)[/code] returns the quest's current stage id. Optional.
## @experimental
var stage_of: Callable = Callable()
## [code]seed_of()[/code] returns the game seed used for a faction tie-break or a cast pick.
## @experimental
var seed_of: Callable = Callable()
## [code]election_of()[/code] returns the registered [WyrdElectionAdapter], or null.
## @experimental
var election_of: Callable = Callable()
## [code]faction_rank(faction, entity)[/code] returns an int. Higher wins.
## @experimental
var faction_rank: Callable = Callable()
## [code]host_decides(role, departed)[/code] is told about a pending request.
## @experimental
var host_decides: Callable = Callable()

var _slots: Dictionary = {}
var _from_content: Dictionary = {}
## Role ids passed to [method define] since the last [method bind_content].
var _host_defined: Dictionary = {}
var _bindings: Dictionary = {}
var _defs: Dictionary = {}
var _frozen: Dictionary = {}
var _told: Dictionary = {}
var _pending: Dictionary = {}
var _abolished: Dictionary = {}
var _started: bool = false


## @experimental
func bind_content(content: WyrdContent) -> void:
	_slots.clear()
	_frozen.clear()
	for id in _from_content.keys():
		_defs.erase(id)
	_from_content.clear()
	_host_defined.clear()
	if content == null:
		return
	var ids: Array = content.quests.keys()
	ids.sort()
	for quest_id in ids:
		var quest: WyrdQuestDef = content.quests[quest_id]
		for slot in quest.slots:
			var name := String(slot.name)
			if not _slots.has(name):
				_slots[name] = []
			(_slots[name] as Array).append({
				"kind": slot.kind,
				"mode": slot.mode,
				"quest": String(quest_id),
				"role": StringName(slot.role),
				"stage": slot.locked_stage,
			})
	var role_ids: Array = content.roles.keys()
	role_ids.sort()
	for role_id in role_ids:
		install(content.roles[role_id] as WyrdRoleDef, true)


## @experimental
func clear() -> void:
	_bindings.clear()
	_frozen.clear()
	_told.clear()
	_pending.clear()
	_abolished.clear()
	_apply_all_defaults()


## @experimental
func export_state() -> Dictionary:
	var bindings := {}
	var roles: Array = _bindings.keys()
	roles.sort()
	for role in roles:
		var row: Dictionary = _bindings[role]
		var history: Array = []
		for item in row["history"]:
			var prior: Dictionary = item
			history.append({
				"holder": String(prior.get("holder", "")),
				"reason": String(prior.get("reason", "")),
				"since": int(prior.get("since", 0)),
				"status": String(prior.get("status", "")),
				"until": int(prior.get("until", 0)),
			})
		bindings[String(role)] = {
			"history": history,
			"holder": String(row.get("holder", "")),
			"since": int(row.get("since", 0)),
			"status": String(row.get("status", "")),
		}
	var defs := {}
	var defined: Array = _defs.keys()
	defined.sort()
	for role in defined:
		var spec: Dictionary = _defs[role]
		var kinds: Array = []
		for kind in spec["kinds"]:
			kinds.append(String(kind))
		defs[String(role)] = {
			"default_holder": String(spec.get("default_holder", "")),
			"eligibility": String(spec.get("eligibility", "")),
			"kinds": kinds,
			"scope": String(spec.get("scope", "world")),
			"scope_id": String(spec.get("scope_id", "")),
			"secret": bool(spec["secret"]),
			"strategy": String(spec["strategy"]),
			"succession": String(spec.get("succession", _succession_text(String(spec["strategy"]), kinds))),
			"succession_arg": String(spec.get("succession_arg", "")),
			"threshold": int(spec["threshold"]),
			"vacancy": String(spec.get("vacancy", "hold")),
			"visibility": String(spec.get("visibility", "secret" if bool(spec["secret"]) else "public")),
		}
	var frozen := {}
	var locks: Array = _frozen.keys()
	locks.sort()
	for lock in locks:
		var parts := String(lock).split("\t")
		if parts.size() != 2:
			continue
		if parts[0].contains("#"):
			continue
		if not frozen.has(parts[0]):
			frozen[parts[0]] = {}
		var snap: Dictionary = _frozen[lock]
		var frozen_row := {
			"holder": String(snap.get("holder", "")),
			"status": String(snap.get("status", "")),
		}
		if snap.has("owner"):
			frozen_row["owner"] = String(snap.get("owner", ""))
		(frozen[parts[0]] as Dictionary)[parts[1]] = frozen_row
	var told := {}
	var secret_roles: Array = _told.keys()
	secret_roles.sort()
	for role in secret_roles:
		var agents: Array = (_told[role] as Dictionary).keys()
		agents.sort()
		var names: Array = []
		for agent in agents:
			names.append(String(agent))
		told[String(role)] = names
	var pending := {}
	var waiting: Array = _pending.keys()
	waiting.sort()
	for role in waiting:
		var request: Dictionary = _pending[role]
		pending[String(role)] = {
			"departed": String(request.get("departed", "")),
			"since": int(request.get("since", 0)),
		}
	var abolished: Array = []
	var ceased: Array = _abolished.keys()
	ceased.sort()
	for role in ceased:
		abolished.append(String(role))
	return {
		"abolished": abolished,
		"bindings": bindings,
		"defs": defs,
		"frozen": frozen,
		"pending": pending,
		"told": told,
	}


func _import_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


## @experimental
func import_state(data: Dictionary) -> void:
	_bindings.clear()
	_defs.clear()
	_frozen.clear()
	_told.clear()
	_pending.clear()
	_abolished.clear()
	var bindings := _import_dict(data.get("bindings", {}))
	for role in bindings.keys():
		if not (bindings[role] is Dictionary):
			continue
		var row: Dictionary = bindings[role]
		var history: Array = []
		for item in row.get("history", []):
			if not (item is Dictionary):
				continue
			var prior: Dictionary = item
			var prior_status := StringName(str(prior.get("status", "")))
			if prior_status == &"pending":
				prior_status = CONTESTED
			history.append({
				"holder": StringName(str(prior.get("holder", ""))),
				"reason": StringName(str(prior.get("reason", ""))),
				"since": WyrdSave._whole(prior.get("since", 0), 0),
				"status": prior_status,
				"until": WyrdSave._whole(prior.get("until", 0), 0),
			})
		var status := StringName(str(row.get("status", "empty")))
		if status == &"pending":
			status = CONTESTED
		_bindings[StringName(str(role))] = {
			"history": history,
			"holder": StringName(str(row.get("holder", ""))),
			"since": WyrdSave._whole(row.get("since", 0), 0),
			"status": status,
		}
	var defs := _import_dict(data.get("defs", {}))
	for role in defs.keys():
		if not (defs[role] is Dictionary):
			continue
		var spec: Dictionary = defs[role]
		var kinds := PackedStringArray()
		var kind_list: Variant = spec.get("kinds", [])
		if kind_list is Array:
			for kind in kind_list:
				kinds.append(WyrdSave.text_of(kind, ""))
		var visibility := str(spec.get("visibility", ""))
		if visibility != "public" and visibility != "secret":
			visibility = "secret" if WyrdSave.flag_of(spec.get("secret", false), false) else "public"
		var strategy := str(spec.get("strategy", "none"))
		var succession := str(spec.get("succession", ""))
		if succession.is_empty():
			var kind_rows: Array = []
			for kind in kinds:
				kind_rows.append(String(kind))
			succession = _succession_text(strategy, kind_rows)
		var vacancy := str(spec.get("vacancy", "hold"))
		if vacancy != "abolish":
			vacancy = "hold"
		_defs[StringName(str(role))] = {
			"default_holder": StringName(str(spec.get("default_holder", ""))),
			"eligibility": str(spec.get("eligibility", "")),
			"eligibility_cond": null,
			"kinds": kinds,
			"scope": StringName(str(spec.get("scope", "world"))),
			"scope_id": StringName(str(spec.get("scope_id", ""))),
			"secret": visibility == "secret",
			"strategy": StringName(strategy),
			"succession": succession,
			"succession_arg": StringName(str(spec.get("succession_arg", ""))),
			"threshold": WyrdSave._whole(spec.get("threshold", -1), -1),
			"vacancy": StringName(vacancy),
			"visibility": StringName(visibility),
		}
	var frozen := _import_dict(data.get("frozen", {}))
	for quest_id in frozen.keys():
		if not (frozen[quest_id] is Dictionary):
			continue
		var slots: Dictionary = frozen[quest_id]
		for slot_name in slots.keys():
			if not (slots[slot_name] is Dictionary):
				continue
			var snap: Dictionary = slots[slot_name]
			var loaded_row := {
				"holder": StringName(str(snap.get("holder", ""))),
				"status": StringName(str(snap.get("status", ""))),
			}
			if snap.has("owner"):
				loaded_row["owner"] = WyrdSave.text_of(snap.get("owner", ""), "")
			_frozen[_freeze_key(String(quest_id), String(slot_name))] = loaded_row
	var told := _import_dict(data.get("told", {}))
	for role in told.keys():
		var agents: Variant = told[role]
		if not (agents is Array):
			continue
		var bag := {}
		for agent in agents:
			bag[StringName(str(agent))] = true
		_told[StringName(str(role))] = bag
	var pending := _import_dict(data.get("pending", {}))
	for role in pending.keys():
		var request: Dictionary = pending[role] if pending[role] is Dictionary else {}
		_pending[StringName(str(role))] = {
			"departed": StringName(str(request.get("departed", ""))),
			"since": WyrdSave._whole(request.get("since", 0), 0),
		}
	var abolished: Variant = data.get("abolished", [])
	if abolished is Array:
		for role in abolished:
			var id := StringName(str(role))
			if id != &"":
				_abolished[id] = true
	_recompile_eligibility()


## @experimental
func define(
	role: StringName,
	succession: String = "none",
	secret: bool = false,
	hostile_threshold: int = -1,
	scope: String = "",
	eligibility: String = "",
	default_holder: StringName = &"",
	vacancy: String = "",
	visibility: String = ""
) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if role == &"":
		push_error("WyrdRoles.define: missing role")
		return
	var parsed := WyrdRoleDef.parse_succession(succession)
	if not bool(parsed["ok"]):
		push_error("WyrdRoles.define: %s" % String(parsed["error"]))
		return
	var scope_text := scope.strip_edges()
	if scope_text.is_empty():
		scope_text = "world"
	var scope_parsed := WyrdRoleDef.parse_scope(scope_text)
	if not bool(scope_parsed["ok"]):
		push_error("WyrdRoles.define: %s" % String(scope_parsed["error"]))
		return
	var shown := visibility.strip_edges()
	if shown.is_empty():
		shown = "secret" if secret else "public"
	var vis_parsed := WyrdRoleDef.parse_visibility(shown)
	if not bool(vis_parsed["ok"]):
		push_error("WyrdRoles.define: %s" % String(vis_parsed["error"]))
		return
	var vacancy_text := vacancy.strip_edges()
	if vacancy_text.is_empty():
		vacancy_text = "hold"
	var vacancy_parsed := WyrdRoleDef.parse_vacancy(vacancy_text)
	if not bool(vacancy_parsed["ok"]):
		push_error("WyrdRoles.define: %s" % String(vacancy_parsed["error"]))
		return
	var holder_text := String(default_holder).strip_edges()
	if not holder_text.is_empty() and not WyrdRoleDef.is_dotted_ident(holder_text):
		push_error("WyrdRoles.define: default_holder \"%s\" is not an entity id" % holder_text)
		return
	var elig := eligibility.strip_edges()
	var cond: WyrdCompiledCondition = null
	if not elig.is_empty():
		var diags := WyrdDiagnostics.new()
		cond = WyrdRoleDef.compile_eligibility(elig, _schema(), diags, "define", 1, 1)
		if diags.has_errors():
			push_error("WyrdRoles.define: %s" % diags.items[0].message)
			return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("roles.define", [role, succession, secret, hostile_threshold, scope, eligibility, default_holder, vacancy, visibility])
	var spec := _blank_spec()
	spec["default_holder"] = StringName(holder_text)
	spec["eligibility"] = elig
	spec["eligibility_cond"] = cond
	spec["kinds"] = parsed["kinds"]
	spec["scope"] = StringName(str(scope_parsed["scope"]))
	spec["scope_id"] = StringName(str(scope_parsed["id"]))
	spec["secret"] = str(vis_parsed["visibility"]) == "secret"
	spec["strategy"] = StringName(str(parsed["strategy"]))
	spec["succession"] = succession.strip_edges() if not succession.strip_edges().is_empty() else "none"
	spec["succession_arg"] = StringName(str(parsed["arg"]))
	spec["threshold"] = hostile_threshold
	spec["vacancy"] = StringName(str(vacancy_parsed["vacancy"]))
	spec["visibility"] = StringName(str(vis_parsed["visibility"]))
	_defs[role] = spec
	_host_defined[String(role)] = true
	_abolished.erase(role)
	_pending.erase(role)
	_apply_default(role)


## @experimental
func install(role: WyrdRoleDef, from_content: bool = false) -> void:
	if role == null or role.id.is_empty():
		return
	var id := StringName(role.id)
	_defs[id] = role.to_runtime_spec()
	if from_content:
		_from_content[id] = true
	_abolished.erase(id)
	_pending.erase(id)
	_apply_default(id)


## True when [method define] named [param role] since the last content load.
## @experimental
func is_host_defined(role: String) -> bool:
	return _host_defined.has(role)


## Role ids in the imported block: bindings, defs, told, pending, and abolished.
## @experimental
func present_role_ids() -> PackedStringArray:
	var found := {}
	for role in _bindings.keys():
		found[String(role)] = true
	for role in _defs.keys():
		found[String(role)] = true
	for role in _told.keys():
		found[String(role)] = true
	for role in _pending.keys():
		found[String(role)] = true
	for role in _abolished.keys():
		found[String(role)] = true
	var names := PackedStringArray()
	for role in found.keys():
		var id := String(role)
		if not id.is_empty():
			names.append(id)
	names.sort()
	return names


## @experimental
func definition(role: StringName) -> Dictionary:
	var spec := _spec(role)
	var kinds: Array = []
	for kind in spec["kinds"]:
		kinds.append(String(kind))
	return {
		"default_holder": String(spec["default_holder"]),
		"eligibility": String(spec["eligibility"]),
		"kinds": kinds,
		"scope": String(spec["scope"]),
		"scope_id": String(spec["scope_id"]),
		"secret": bool(spec["secret"]),
		"strategy": String(spec["strategy"]),
		"succession": String(spec["succession"]),
		"succession_arg": String(spec["succession_arg"]),
		"threshold": int(spec["threshold"]),
		"vacancy": String(spec["vacancy"]),
		"visibility": String(spec["visibility"]),
	}


## @experimental
func eligible(role: StringName, entity: StringName) -> bool:
	var spec := _spec(role)
	var text := String(spec.get("eligibility", ""))
	var cond: Variant = spec.get("eligibility_cond", null)
	var has_rule := not text.is_empty() or cond is WyrdCompiledCondition
	var ok := true
	if entity == &"":
		ok = false
	elif not has_rule:
		ok = true
	elif cond is WyrdCompiledCondition:
		if eval_with.is_valid():
			ok = bool(eval_with.call(cond, {"candidate": entity}))
		else:
			push_error("WyrdRoles.eligible: no condition evaluator")
			ok = false
	else:
		push_error("WyrdRoles.eligible: \"%s\" has no compiled eligibility" % String(role))
		ok = false
	if has_rule:
		_trace_eligible(role, entity, ok)
	return ok


## @experimental
func set_faction_rank(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdRoles.set_faction_rank: missing callable")
		return
	faction_rank = fn


## @experimental
func set_host_decides(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdRoles.set_host_decides: missing callable")
		return
	host_decides = fn


## Called from [method WyrdRuntime.start_new_game]. A role that uses
## [code]host_decides[/code] needs a callback or a [signal succession_requested]
## connection before play starts. A role that uses [code]election[/code] needs
## a [WyrdElectionAdapter] or an [signal election_needed] connection.
## @experimental
func note_started() -> void:
	_started = true
	if _any_strategy("host_decides") and not _host_ready():
		push_error("WyrdRoles: host_decides has no callback")
	if _any_strategy("election") and not _election_ready():
		push_error("WyrdRoles: election has no adapter")


## @experimental
func abolished(role: StringName) -> bool:
	return _abolished.has(role)


## @experimental
func departed(role: StringName) -> StringName:
	if not _pending.has(role):
		return &""
	return (_pending[role] as Dictionary).get("departed", &"")


## Sets the holder and marks the binding default. Refuses an empty role or entity, an abolished role, or the departed holder.
func assign(role: StringName, entity: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if role == &"" or entity == &"":
		push_error("WyrdRoles.assign: missing role or entity")
		return
	if _abolished.has(role):
		push_error("WyrdRoles.assign: \"%s\" is abolished" % String(role))
		return
	var request: Dictionary = _pending.get(role, {})
	if not request.is_empty() and entity == request.get("departed", &""):
		push_error("WyrdRoles.assign: successor of \"%s\" must differ from the departed holder" % String(role))
		return
	var prior := _binding(role)
	var old: StringName = prior["holder"]
	if old == entity and prior["status"] != EMPTY:
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("roles.assign", [role, entity])
	if old != &"":
		_push_history(prior, &"assign")
	prior["holder"] = entity
	prior["since"] = _now()
	prior["status"] = DEFAULT
	_bindings[role] = prior
	_refresh_told(role)
	if not request.is_empty():
		_pending.erase(role)
		var left: StringName = request.get("departed", &"")
		_record_role_changed(role, left, entity)
		_trace_succession(role, String(_spec(role).get("strategy", "")), left, entity, "assigned")
	if old != entity:
		role_holder_changed.emit(role, old, entity)


## Content [code]assign role[/code]. Host [method assign] is unchanged.
## Unknown roles [code]push_error[/code] and do not trace. Other refusals warn.
## [code]same_holder[/code] traces and does not warn. A first holder has no
## [code]role_changed[/code] deed, because a deed needs an actor.
## @experimental
func assign_from_content(role: StringName, entity: StringName) -> bool:
	if not _defs.has(role):
		push_error("WyrdRoles.assign_from_content: unknown role \"%s\"" % String(role))
		return false
	var prior := _binding(role)
	var old: StringName = prior["holder"]
	if _abolished.has(role):
		return _refuse_assign(role, old, entity, "abolished", "\"%s\" is abolished" % String(role))
	if _pending.has(role):
		return _refuse_assign(role, old, entity, "contested", "\"%s\" is contested" % String(role))
	if not _living(entity):
		return _refuse_assign(role, old, entity, "no_entity", "\"%s\" has no living entity" % String(role))
	if not eligible(role, entity):
		return _refuse_assign(role, old, entity, "ineligible", "\"%s\" is ineligible" % String(role))
	if old == entity and prior["status"] != EMPTY:
		_trace_role_line("role_assign", role, old, entity, false, "same_holder")
		return false
	if old != &"":
		_push_history(prior, &"assign")
	prior["holder"] = entity
	prior["since"] = _now()
	var default_holder := StringName(str(_spec(role).get("default_holder", "")))
	prior["status"] = DEFAULT if entity == default_holder and default_holder != &"" else SUCCESSOR
	_bindings[role] = prior
	_refresh_told(role)
	_record_role_changed(role, old, entity)
	if old != entity:
		role_holder_changed.emit(role, old, entity)
	_trace_role_line("role_assign", role, old, entity, true, "assigned")
	return true


func _refuse_assign(role: StringName, old: StringName, entity: StringName, reason: String, message: String) -> bool:
	_trace_role_line("role_assign", role, old, entity, false, reason)
	push_warning("WyrdRoles.assign_from_content: %s" % message)
	return false


## Content [code]vacate role[/code]. Checks, then [method vacate] with reason [code]content[/code].
## @experimental
func vacate_from_content(role: StringName) -> bool:
	if not _defs.has(role):
		push_error("WyrdRoles.vacate_from_content: unknown role \"%s\"" % String(role))
		return false
	var old: StringName = _binding(role)["holder"]
	if _abolished.has(role):
		return _refuse_vacate(role, old, "abolished", "\"%s\" is abolished" % String(role))
	if _pending.has(role):
		return _refuse_vacate(role, old, "contested", "\"%s\" is contested" % String(role))
	if old == &"":
		return _refuse_vacate(role, old, "empty", "\"%s\" is empty" % String(role))
	vacate(role, &"content")
	_trace_role_line("role_vacate", role, old, _binding(role)["holder"], true, "vacated")
	return true


func _refuse_vacate(role: StringName, old: StringName, reason: String, message: String) -> bool:
	_trace_role_line("role_vacate", role, old, &"", false, reason)
	push_warning("WyrdRoles.vacate_from_content: %s" % message)
	return false


func _trace_role_line(kind: String, role: StringName, old: StringName, next: StringName, ok: bool, reason: String) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call(kind, {
		"from": String(old),
		"ok": "true" if ok else "false",
		"reason": reason,
		"role": String(role),
		"to": String(next),
	})


func _living(entity: StringName) -> bool:
	if entity == &"":
		return false
	var world := _world()
	if world == null:
		return false
	return world.exists(entity) and world.is_alive(entity)


## Clears the holder and runs the role's succession strategy.
func vacate(role: StringName, reason: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if _abolished.has(role) or _pending.has(role):
		return
	var prior := _binding(role)
	var old: StringName = prior["holder"]
	if old == &"":
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("roles.vacate", [role, reason])
	_push_history(prior, reason)
	var strategy := String(_spec(role)["strategy"])
	if strategy == "host_decides" or strategy == "election":
		_begin_contested(role, prior, old, strategy)
		return
	var next := &""
	if strategy == "relation":
		next = _relation_successor(role, old)
	elif strategy == "faction_assigns":
		next = _faction_successor(role, old)
	if next != &"" and next != old:
		_trace_succession(role, strategy, old, next, "picked")
		_take_successor(role, prior, old, next)
		return
	_trace_succession(role, strategy, old, &"", "none")
	if _spec(role)["vacancy"] == &"abolish":
		_abolish(role, prior, old)
		return
	_leave_empty(role, prior)


## @experimental
func tell(role: StringName, agent: StringName) -> void:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if role == &"" or agent == &"":
		push_error("WyrdRoles.tell: missing role or agent")
		return
	if runtime != null and runtime._host_logs():
		runtime._host_mark("roles.tell", [role, agent])
	if not _told.has(role):
		_told[role] = {}
	(_told[role] as Dictionary)[agent] = true
	_write_known(role, agent)


## World role ids whose binding holder is [param entity]. Sorted.
## @experimental
func roles_of(entity: StringName) -> PackedStringArray:
	var found := PackedStringArray()
	if entity == &"":
		return found
	for role in _bindings.keys():
		var row: Dictionary = _bindings[role]
		if row.get("holder", &"") != entity:
			continue
		found.append(String(role))
	found.sort()
	return found


## @experimental
func holder(slot_or_role: StringName) -> StringName:
	var name := String(slot_or_role)
	if _slots.has(name):
		return _resolved(_primary(name), name)["holder"]
	return _binding(slot_or_role)["holder"]


## @experimental
func slot_holder(quest_id: String, slot_name: StringName) -> StringName:
	return _resolved(quest_id, String(slot_name))["holder"]


## @experimental
func slot_state(slot_name: StringName, quest_id: String = "") -> StringName:
	var quest := quest_id if not quest_id.is_empty() else _primary(String(slot_name))
	return resolve_slot(quest, slot_name, false)["state"]


## Resolves one slot. [param trace_it] asks the runtime to log one line when the
## state or reason changed. The returned [code]variant[/code] is the first
## declared match, or null when the stage does not cover the winning state.
## @experimental
func resolve_slot(quest_id: String, slot_name: StringName, trace_it: bool = false) -> Dictionary:
	var resolved: Dictionary = _resolved(quest_id, String(slot_name))
	var who: StringName = resolved["holder"]
	var status: StringName = resolved["status"]
	var role: StringName = resolved["role"]
	var kind := String(_slot_row(quest_id, String(slot_name)).get("kind", ""))
	var variants := _stage_variants(quest_id, String(slot_name))
	var gone := _gone_reason(quest_id, String(slot_name), who)
	var higher := false
	var winner_state := EMPTY
	var winner_reason := "no_holder"
	var winner: WyrdVariantDef = null
	var saw := false
	for state_name in _STATE_ORDER:
		if not kind.is_empty() and state_name != "locked_gone" and state_name != "empty" and state_name != "default":
			continue
		if not _state_applies(state_name, who, status, role, gone, variants):
			continue
		if not saw:
			winner_state = StringName(state_name)
			winner_reason = _state_reason(state_name, gone)
			saw = true
		if state_name == "contested":
			var contest := _match_variant("contested", variants, who)
			if contest != null:
				winner = contest
				winner_state = CONTESTED
				winner_reason = "contested"
				break
			var fallback := _match_variant("empty", variants, who)
			if fallback != null:
				winner = fallback
				winner_state = CONTESTED
				winner_reason = "fallback_empty"
				break
			higher = true
			continue
		var match := _match_variant(state_name, variants, who)
		if match == null:
			higher = true
			continue
		winner = match
		winner_state = StringName(state_name)
		winner_reason = "fallthrough" if higher else _state_reason(state_name, gone)
		break
	if trace_it and trace_of.is_valid():
		var traced := {
			"quest": quest_id,
			"reason": winner_reason,
			"slot": String(slot_name),
			"state": String(winner_state),
		}
		if kind.is_empty():
			traced["role"] = String(role)
		else:
			traced["kind"] = kind
		trace_of.call("slot_state", traced)
	return {
		"reason": winner_reason,
		"role": role,
		"state": winner_state,
		"variant": winner,
	}


## @experimental
func binding_status(role: StringName) -> StringName:
	return _binding(role)["status"]


## Sorted table of every role. [param prefix] keeps ids that start with that text.
## Columns are role, holder, status, strategy, flags (pending and/or abolished),
## and frozen slots. Built in one pass so a few hundred roles stay cheap.
## @experimental
func render_table(prefix: String = "") -> String:
	var header := PackedStringArray(["role", "holder", "status", "strategy", "flags", "frozen"])
	var frozen_of := _frozen_by_role()
	var ids := PackedStringArray()
	var seen := {}
	for role in _bindings.keys():
		var name := String(role)
		if not seen.has(name):
			seen[name] = true
			ids.append(name)
	for role in _defs.keys():
		var name := String(role)
		if not seen.has(name):
			seen[name] = true
			ids.append(name)
	ids.sort()
	var rows: Array[PackedStringArray] = []
	for name in ids:
		if not prefix.is_empty() and not name.begins_with(prefix):
			continue
		rows.append(_table_cells(StringName(name), frozen_of))
	return _format_table(header, rows)


## @experimental
func binding_since(role: StringName) -> int:
	return int(_binding(role)["since"])


## @experimental
func history(role: StringName) -> Array:
	return (_binding(role)["history"] as Array).duplicate(true)


## @experimental
func revealed(agent: StringName, key: StringName) -> bool:
	var role := _role_of_key(key)
	if role == &"":
		return false
	if bool(_spec(role)["secret"]):
		return _is_told(role, agent)
	return _binding(role)["holder"] != &""


## Appends slot rows for one generated instance. Content rows stay first.
## @experimental
func bind_instance(instance_id: String, quest: WyrdQuestDef) -> void:
	if quest == null or instance_id.is_empty():
		return
	for slot in quest.slots:
		var name := String(slot.name)
		if not _slots.has(name):
			_slots[name] = []
		var rows: Array = _slots[name]
		var found := false
		for item in rows:
			if str((item as Dictionary).get("quest", "")) == instance_id:
				found = true
				break
		if found:
			continue
		rows.append({
			"kind": slot.kind,
			"mode": slot.mode,
			"quest": instance_id,
			"role": StringName(slot.role),
			"stage": slot.locked_stage,
		})


## Drops freeze keys and slot rows whose quest id contains [code]#[/code].
## @experimental
func drop_instances() -> void:
	var locks: Array = _frozen.keys()
	for lock in locks:
		var parts := String(lock).split("\t")
		if parts.size() > 0 and parts[0].contains("#"):
			_frozen.erase(lock)
	var names: Array = _slots.keys()
	for name in names:
		var rows: Array = _slots[name]
		var kept: Array = []
		for item in rows:
			if not str((item as Dictionary).get("quest", "")).contains("#"):
				kept.append(item)
		if kept.is_empty():
			_slots.erase(name)
		else:
			_slots[name] = kept


## Freezes one supplied cast and logs [code]reason=given[/code].
## @experimental
func freeze_given(quest_id: String, slot: WyrdSlotDef, holder: StringName) -> void:
	if slot == null:
		return
	var status := DEFAULT if holder != &"" else EMPTY
	var snap := {"holder": holder, "status": status}
	if slot.kind == "item" and holder != &"":
		var inventory := _inventory()
		if inventory != null:
			snap["owner"] = String(inventory.owner_of(holder))
	_frozen[_freeze_key(quest_id, slot.name)] = snap
	_trace_cast(quest_id, slot, holder, snap, "given")


## Loads saved instance casts. Load logs nothing.
## @experimental
func install_casts(quest_id: String, casts: Dictionary) -> void:
	for slot_name in casts.keys():
		var snap: Variant = casts[slot_name]
		if not (snap is Dictionary):
			continue
		var item: Dictionary = snap
		var row := {
			"holder": StringName(str(item.get("holder", ""))),
			"status": StringName(str(item.get("status", ""))),
		}
		if item.has("owner"):
			row["owner"] = WyrdSave.text_of(item.get("owner", ""), "")
		_frozen[_freeze_key(quest_id, String(slot_name))] = row


## Instance id to slot name to [code]{holder, status[, owner]}[/code].
## @experimental
func instance_casts() -> Dictionary:
	var out := {}
	var locks: Array = _frozen.keys()
	locks.sort()
	for lock in locks:
		var parts := String(lock).split("\t")
		if parts.size() != 2 or not parts[0].contains("#"):
			continue
		if not out.has(parts[0]):
			out[parts[0]] = {}
		var snap: Dictionary = _frozen[lock]
		var row := {
			"holder": String(snap.get("holder", "")),
			"status": String(snap.get("status", "")),
		}
		if snap.has("owner"):
			row["owner"] = String(snap.get("owner", ""))
		(out[parts[0]] as Dictionary)[parts[1]] = row
	return out


## @experimental
func begin_quest(quest_id: String) -> void:
	var quest := _quest(quest_id)
	if quest == null:
		return
	for slot in quest.slots:
		if slot.mode != &"cast":
			continue
		var key := _freeze_key(quest_id, slot.name)
		if _frozen.has(key):
			continue
		var picked := _cast_pick(quest_id, slot)
		var status := DEFAULT if picked != &"" else EMPTY
		var snap := {"holder": picked, "status": status}
		if slot.kind == "item" and picked != &"":
			var inventory := _inventory()
			if inventory != null:
				snap["owner"] = String(inventory.owner_of(picked))
		_frozen[key] = snap
		_trace_cast(quest_id, slot, picked, snap)


## @experimental
func enter_stage(quest_id: String, stage_id: String) -> void:
	var quest := _quest(quest_id)
	if quest == null:
		return
	for slot in quest.slots:
		if slot.mode != &"locked_at" or slot.locked_stage != stage_id:
			continue
		var key := _freeze_key(quest_id, slot.name)
		if _frozen.has(key):
			continue
		var live := _binding(StringName(slot.role))
		_frozen[key] = {"holder": live["holder"], "status": live["status"]}


func _resolved(quest_id: String, slot_name: String) -> Dictionary:
	var row := _slot_row(quest_id, slot_name)
	var role: StringName = row.get("role", StringName(slot_name))
	var key := _freeze_key(quest_id, slot_name)
	if quest_id != "" and _frozen.has(key):
		var snap: Dictionary = _frozen[key]
		return {"holder": snap["holder"], "role": role, "status": snap["status"]}
	var live := _binding(role)
	return {"holder": live["holder"], "role": role, "status": live["status"]}


func _relation_successor(role: StringName, old: StringName) -> StringName:
	var spec := _spec(role)
	if social == null:
		return &""
	var kinds: PackedStringArray = spec["kinds"]
	for kind in kinds:
		for candidate in social.targets(old, StringName(kind)):
			var id := StringName(candidate)
			if id == old or id == &"":
				continue
			if _alive(id) and eligible(role, id):
				return id
	return &""


func _faction_successor(role: StringName, old: StringName) -> StringName:
	var faction := StringName(str(_spec(role).get("succession_arg", "")))
	var world := _world()
	if world == null or faction == &"":
		return &""
	var seen := {}
	var ids: Array = []
	for raw in world.members(faction):
		var who := StringName(str(raw))
		if who == &"" or who == old or seen.has(who):
			continue
		seen[who] = true
		if _alive(who) and eligible(role, who):
			ids.append(String(who))
	if ids.is_empty():
		return &""
	ids.sort()
	var key := StringName("%s|%s|%s" % [String(role), String(faction), String(old)])
	var rng := WyrdRng.for_decision(_game_seed(), &"faction_assigns", key, _now())
	var rolls := {}
	for id in ids:
		rolls[String(id)] = rng.next_u32()
	var best := ""
	var best_rank := 0
	var best_roll := 0
	for id in ids:
		var text := String(id)
		var rank := _rank(faction, text)
		var roll := int(rolls[text])
		var better := best.is_empty() or rank > best_rank
		if not better and rank == best_rank:
			better = roll > best_roll or (roll == best_roll and text < best)
		if better:
			best = text
			best_rank = rank
			best_roll = roll
	return StringName(best)


func _begin_contested(role: StringName, prior: Dictionary, old: StringName, strategy: String) -> void:
	prior["holder"] = &""
	prior["since"] = _now()
	prior["status"] = CONTESTED
	_bindings[role] = prior
	_pending[role] = {"departed": old, "since": int(prior["since"])}
	_refresh_told(role)
	_trace_succession(role, strategy, old, &"", "contested")
	if strategy == "election":
		election_needed.emit(role, old)
		var poll := _election()
		if poll != null:
			poll.start_election(role, old)
		return
	succession_requested.emit(role, old)
	if host_decides.is_valid():
		host_decides.call(role, old)


func _take_successor(role: StringName, prior: Dictionary, old: StringName, next: StringName) -> void:
	prior["holder"] = next
	prior["since"] = _now()
	prior["status"] = SUCCESSOR
	_bindings[role] = prior
	_refresh_told(role)
	role_holder_changed.emit(role, old, next)
	_record_role_changed(role, old, next)


func _leave_empty(role: StringName, prior: Dictionary) -> void:
	prior["holder"] = &""
	prior["since"] = _now()
	prior["status"] = EMPTY
	_bindings[role] = prior
	_refresh_told(role)
	role_vacant.emit(role)


func _abolish(role: StringName, prior: Dictionary, old: StringName) -> void:
	prior["holder"] = &""
	prior["since"] = _now()
	prior["status"] = EMPTY
	_bindings[role] = prior
	_abolished[role] = true
	_pending.erase(role)
	_refresh_told(role)
	if deeds != null and old != &"":
		deeds.record(&"role_abolished", old, role, &"", PackedStringArray(), 1.0, null, &"public", false)
	role_vacant.emit(role)
	_trace_succession(role, String(_spec(role)["strategy"]), old, &"", "abolished")


func _record_role_changed(role: StringName, old: StringName, next: StringName) -> void:
	if deeds == null or old == &"" or next == &"" or old == next:
		return
	deeds.record(&"role_changed", old, next, &"", PackedStringArray([String(role)]), 1.0, null, &"public", false)


## Sorted candidate ids and the ids the cast condition accepts.
## [code]raw[/code] is every deduped host answer. [code]accepted[/code] is that
## list after the condition. Both are sorted. A missing world yields two empty lists.
## @experimental
func cast_pool(slot: WyrdSlotDef) -> Dictionary:
	if slot == null:
		_note_scan_pool()
		return {"accepted": [], "raw": []}
	if _use_cast_index(slot.cast_plan):
		return _pool_indexed(slot.cast_plan)
	_note_scan_pool()
	return cast_pool_scan(slot)


## The full candidate walk. Same result as [method cast_pool] when the index is off.
## @experimental
func cast_pool_scan(slot: WyrdSlotDef) -> Dictionary:
	if slot == null:
		return {"accepted": [], "raw": []}
	var filtered := slot.kind == "object" or slot.kind == "item"
	return _candidate_pool(slot.cast_when, slot.cast_tag, slot.kind, filtered)


## Sorted candidate ids for one param. The filter always carries the param kind and tag.
## @experimental
func param_pool(param: WyrdParamDef) -> Dictionary:
	if param == null:
		_note_scan_pool()
		return {"accepted": [], "raw": []}
	if _use_cast_index(param.cast_plan):
		return _pool_indexed(param.cast_plan)
	_note_scan_pool()
	return param_pool_scan(param)


## The full candidate walk for one param.
## @experimental
func param_pool_scan(param: WyrdParamDef) -> Dictionary:
	if param == null:
		return {"accepted": [], "raw": []}
	return _candidate_pool(param.cast_when, param.cast_tag, param.kind, true)


## Drops every cached candidate list. Role changes do not call this.
## @experimental
func drop_cast_index() -> void:
	_cast_index.clear()
	_note_scan_pool()


## [param ids] empty drops the cache. Otherwise those entities are checked again
## on the next cast, and every cached host answer is refreshed once.
## @experimental
func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void:
	_cast_index.invalidate(ids)
	_note_scan_pool()


## @experimental
func indexed_pool() -> bool:
	return _indexed_pool


## @experimental
func indexed_digest_ready() -> bool:
	return _indexed_ready


## @experimental
func indexed_digest() -> int:
	return _indexed_digest


## @experimental
func store_indexed_digest(digest: int) -> void:
	if _indexed_filter.is_empty():
		return
	_cast_index.store_digest(_indexed_filter, digest)
	_indexed_digest = digest
	_indexed_ready = true


## Picks one id from an already sorted list. Empty yields [code]&""[/code].
## @experimental
func pick_id(ids: Array, stream: StringName, decision_key: String) -> StringName:
	if ids.is_empty():
		return &""
	var rng := WyrdRng.for_decision(_game_seed(), stream, StringName(decision_key), _now())
	return StringName(String(ids[rng.randi_bounded(ids.size())]))


func _cast_pick(quest_id: String, slot: WyrdSlotDef, stream: StringName = &"cast", decision_key: String = "") -> StringName:
	var key := decision_key
	if key.is_empty():
		key = "%s|%s" % [quest_id, slot.name]
	var accepted: Array = cast_pool(slot)["accepted"]
	return pick_id(accepted, stream, key)


func _use_cast_index(plan: WyrdCastPlan) -> bool:
	if not cast_index_enabled or plan == null or plan.scan:
		return false
	var world := _world()
	if world == null or not world.reports_changes():
		return false
	return true


func _pool_indexed(plan: WyrdCastPlan) -> Dictionary:
	var found: Dictionary = _cast_index.pool(
		plan,
		_world(),
		Callable(self, &"_condition_accepts"),
		Callable(self, &"_pin_value"),
		Callable(self, &"_scope_accepts")
	)
	_indexed_pool = true
	_indexed_filter = str(found.get("filter", ""))
	_indexed_ready = bool(found.get("digest_ready", false))
	_indexed_digest = int(found.get("digest", 0))
	return {"accepted": found["accepted"], "raw": found["raw"]}


func _note_scan_pool() -> void:
	_indexed_pool = false
	_indexed_ready = false
	_indexed_digest = 0
	_indexed_filter = ""


func _scope_accepts(cond: WyrdCompiledCondition) -> bool:
	if cond == null:
		return true
	if not eval_with.is_valid():
		push_error("WyrdRoles: cast has no condition evaluator")
		return false
	return bool(eval_with.call(cond, {}))


func _pin_value(cond: WyrdCompiledCondition) -> Variant:
	if cond == null or not eval_value.is_valid():
		return null
	return eval_value.call(cond, {})


func _candidate_pool(cond: WyrdCompiledCondition, tag: String, kind: String, use_filter: bool) -> Dictionary:
	var raw: Array = []
	var accepted: Array = []
	var world := _world()
	if world == null:
		return {"accepted": accepted, "raw": raw}
	var seen := {}
	var filter := WyrdEntityFilter.new()
	if use_filter:
		filter = WyrdEntityFilter.new(StringName(tag), StringName(kind))
	for item in world.candidates(filter):
		var who := StringName(str(item))
		if who == &"" or seen.has(who):
			continue
		seen[who] = true
		raw.append(String(who))
		if _condition_accepts(cond, who):
			accepted.append(String(who))
	raw.sort()
	accepted.sort()
	return {"accepted": accepted, "raw": raw}


func _cast_accepts(slot: WyrdSlotDef, entity: StringName) -> bool:
	if slot == null:
		return false
	return _condition_accepts(slot.cast_when, entity)


func _condition_accepts(cond: WyrdCompiledCondition, entity: StringName) -> bool:
	if cond == null:
		return true
	if not eval_with.is_valid():
		push_error("WyrdRoles: cast has no condition evaluator")
		return false
	return bool(eval_with.call(cond, {"candidate": entity}))


func _trace_cast(quest_id: String, slot: WyrdSlotDef, picked: StringName, snap: Dictionary, reason: String = "") -> void:
	if not trace_of.is_valid():
		return
	var why := reason
	if why.is_empty():
		why = "picked" if picked != &"" else "empty"
	var fields := {
		"entity": String(picked),
		"quest": quest_id,
		"reason": why,
		"slot": slot.name,
	}
	if slot.kind.is_empty():
		fields["role"] = slot.role
	else:
		fields["kind"] = slot.kind
		if snap.has("owner"):
			fields["owner"] = String(snap.get("owner", ""))
	trace_of.call("cast", fields)


func _trace_succession(role: StringName, strategy: String, old: StringName, next: StringName, reason: String) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call("succession", {
		"from": String(old),
		"reason": reason,
		"role": String(role),
		"strategy": strategy,
		"to": String(next),
	})


func _rank(faction: StringName, entity: String) -> int:
	if not faction_rank.is_valid():
		return 0
	var value: Variant = faction_rank.call(faction, StringName(entity))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0


func _game_seed() -> int:
	if seed_of.is_valid():
		return int(seed_of.call())
	return 0


func _any_strategy(strategy: String) -> bool:
	for role in _defs.keys():
		if String((_defs[role] as Dictionary).get("strategy", "")) == strategy:
			return true
	return false


func _host_ready() -> bool:
	return host_decides.is_valid() or succession_requested.get_connections().size() > 0


func _election_ready() -> bool:
	return _election() != null or election_needed.get_connections().size() > 0


func _election() -> WyrdElectionAdapter:
	if not election_of.is_valid():
		return null
	var found: Variant = election_of.call()
	if found is WyrdElectionAdapter:
		return found as WyrdElectionAdapter
	return null


func _stage_variants(quest_id: String, slot_name: String) -> Array:
	var rows: Array = []
	var stage := _stage_def(quest_id)
	if stage == null:
		return rows
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.slot == slot_name:
			rows.append(variant)
	return rows


func _stage_def(quest_id: String) -> WyrdStageDef:
	if quest_id.is_empty() or not stage_of.is_valid():
		return null
	var stage_id := str(stage_of.call(quest_id))
	if stage_id.is_empty():
		return null
	var quest := _quest(quest_id)
	if quest == null:
		return null
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null


func _gone_reason(quest_id: String, slot_name: String, _who: StringName) -> String:
	var row := _slot_row(quest_id, slot_name)
	var kind := String(row.get("kind", ""))
	if kind == "object" or kind == "item":
		return _kind_gone(quest_id, slot_name, kind)
	if row.get("mode", &"") != &"locked_at":
		return ""
	var key := _freeze_key(quest_id, slot_name)
	if not _frozen.has(key):
		return ""
	var snap: Dictionary = _frozen[key]
	var frozen := StringName(snap.get("holder", &""))
	if frozen == &"":
		return ""
	if not _alive(frozen):
		return "frozen_dead"
	var role := StringName(row.get("role", &""))
	if _binding(role)["holder"] == frozen:
		return ""
	# assign, from the host or from content, is not a vacate.
	if _departure_reason(role, frozen) == &"assign":
		return ""
	return "frozen_vacated"


func _state_applies(
	state_name: String,
	who: StringName,
	status: StringName,
	role: StringName,
	gone: String,
	variants: Array
) -> bool:
	var present := gone.is_empty() and who != &"" and status != EMPTY
	match state_name:
		"locked_gone":
			return not gone.is_empty()
		"contested":
			return gone.is_empty() and status == CONTESTED
		"empty":
			return gone.is_empty() and status != CONTESTED and (who == &"" or status == EMPTY)
		"barred":
			return present and _match_variant("barred", variants, who) != null
		"hostile":
			return present and _hostile(role, who)
		"unwilling":
			return present and _match_variant("unwilling", variants, who) != null
		"successor":
			return present and status == SUCCESSOR
		"default":
			return present
		_:
			return false


func _state_reason(state_name: String, gone: String) -> String:
	match state_name:
		"locked_gone":
			return gone if not gone.is_empty() else "frozen_vacated"
		"contested":
			return "contested"
		"empty":
			return "no_holder"
		"barred":
			return "barred"
		"hostile":
			return "disposition"
		"unwilling":
			return "unwilling"
		"successor":
			return "status"
		_:
			return "holder"


func _match_variant(state_name: String, variants: Array, who: StringName) -> WyrdVariantDef:
	for entry in variants:
		var variant := entry as WyrdVariantDef
		if variant == null or String(variant.state) != state_name:
			continue
		if state_name == "barred" or state_name == "unwilling":
			if _variant_cond(variant, who, state_name == "unwilling"):
				return variant
			continue
		return variant
	return null


func _variant_cond(variant: WyrdVariantDef, who: StringName, bind_holder: bool) -> bool:
	if variant.condition == null or not eval_with.is_valid():
		return false
	var locals := {}
	if bind_holder:
		locals["$h"] = who
	return bool(eval_with.call(variant.condition, locals))


func _hostile(role: StringName, who: StringName) -> bool:
	if social == null or who == &"":
		return false
	return social.disposition(who, PLAYER) < _threshold(role)


func _threshold(role: StringName) -> int:
	var over := int(_spec(role)["threshold"])
	if over >= 0:
		return over
	var cfg := _config()
	if cfg == null:
		return 20
	return cfg.hostile_threshold


func _kind_gone(quest_id: String, slot_name: String, kind: String) -> String:
	var key := _freeze_key(quest_id, slot_name)
	if not _frozen.has(key):
		return ""
	var snap: Dictionary = _frozen[key]
	var held := StringName(str(snap.get("holder", "")))
	if held == &"":
		return ""
	var world := _world()
	if world == null or not world.exists(held):
		return "gone"
	if kind != "item" or not snap.has("owner"):
		return ""
	var inventory := _inventory()
	if inventory == null:
		return ""
	if inventory.owner_of(held) != StringName(str(snap.get("owner", ""))):
		return "moved"
	return ""


func _inventory() -> WyrdInventoryAdapter:
	if not inventory_of.is_valid():
		return null
	var found: Variant = inventory_of.call()
	if found is WyrdInventoryAdapter:
		return found as WyrdInventoryAdapter
	return null


func _alive(id: StringName) -> bool:
	var world := _world()
	if world == null:
		return true
	return world.is_alive(id)


func _frozen_by_role() -> Dictionary:
	var grouped := {}
	var locks: Array = _frozen.keys()
	locks.sort()
	for lock in locks:
		var parts := String(lock).split("\t")
		if parts.size() != 2:
			continue
		var row := _slot_row(parts[0], parts[1])
		var role_name := String(row.get("role", ""))
		if role_name.is_empty():
			continue
		if not grouped.has(role_name):
			grouped[role_name] = []
		var snap: Dictionary = _frozen[lock]
		var who := String(snap.get("holder", ""))
		if who.is_empty():
			who = "-"
		var cell := "%s/%s=%s:%s" % [parts[0], parts[1], who, String(snap.get("status", ""))]
		(grouped[role_name] as Array).append(cell)
	return grouped


func _table_cells(role: StringName, frozen_of: Dictionary) -> PackedStringArray:
	var binding := _binding(role)
	var who := String(binding.get("holder", ""))
	if who.is_empty():
		who = "-"
	var status := String(binding.get("status", ""))
	if status.is_empty():
		status = "empty"
	var strategy := String(_spec(role).get("succession", "none"))
	if strategy.is_empty():
		strategy = "none"
	var flags := PackedStringArray()
	if _pending.has(role):
		flags.append("pending")
	if _abolished.has(role):
		flags.append("abolished")
	var flag_text := "-" if flags.is_empty() else ",".join(flags)
	var frozen := "-"
	if frozen_of.has(String(role)):
		var cells: Array = frozen_of[String(role)]
		if not cells.is_empty():
			var packed := PackedStringArray()
			for item in cells:
				packed.append(String(item))
			frozen = ", ".join(packed)
	return PackedStringArray([String(role), who, status, strategy, flag_text, frozen])


func _format_table(header: PackedStringArray, rows: Array[PackedStringArray]) -> String:
	var width := PackedInt32Array()
	width.resize(header.size())
	for i in header.size():
		width[i] = header[i].length()
	for row in rows:
		for i in header.size():
			if row[i].length() > width[i]:
				width[i] = row[i].length()
	var lines := PackedStringArray()
	lines.resize(rows.size() + 1)
	lines[0] = _format_line(header, width)
	for i in rows.size():
		lines[i + 1] = _format_line(rows[i], width)
	return "\n".join(lines) + "\n"


func _format_line(cells: PackedStringArray, width: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	parts.resize(cells.size())
	for i in cells.size():
		parts[i] = cells[i].rpad(width[i])
	return "  ".join(parts)


func _binding(role: StringName) -> Dictionary:
	if not _bindings.has(role):
		return {"history": [], "holder": &"", "since": 0, "status": EMPTY}
	return _bindings[role]


func _departure_reason(role: StringName, holder: StringName) -> StringName:
	var history: Array = _binding(role)["history"]
	for i in range(history.size() - 1, -1, -1):
		var prior: Dictionary = history[i]
		if prior.get("holder", &"") != holder:
			continue
		return StringName(prior.get("reason", &""))
	return &""


func _push_history(prior: Dictionary, reason: StringName) -> void:
	(prior["history"] as Array).append({
		"holder": prior["holder"],
		"reason": reason,
		"since": int(prior["since"]),
		"status": prior["status"],
		"until": _now(),
	})


func _spec(role: StringName) -> Dictionary:
	if _defs.has(role):
		return _defs[role]
	return _blank_spec()


func _blank_spec() -> Dictionary:
	return {
		"default_holder": &"",
		"eligibility": "",
		"eligibility_cond": null,
		"kinds": PackedStringArray(),
		"scope": &"world",
		"scope_id": &"",
		"secret": false,
		"strategy": &"none",
		"succession": "none",
		"succession_arg": &"",
		"threshold": -1,
		"vacancy": &"hold",
		"visibility": &"public",
	}


func _apply_all_defaults() -> void:
	var ids: Array = _defs.keys()
	ids.sort()
	for role in ids:
		_apply_default(StringName(str(role)))


func _apply_default(role: StringName) -> void:
	if _abolished.has(role):
		return
	var who := StringName(str(_spec(role).get("default_holder", "")))
	if who == &"":
		return
	var prior := _binding(role)
	if prior["holder"] != &"" and prior["status"] != EMPTY:
		return
	assign(role, who)


func _trace_eligible(role: StringName, entity: StringName, ok: bool) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call("eligible", {"entity": String(entity), "ok": ok, "role": String(role)})


func _schema() -> WyrdFactSchema:
	if content_of.is_valid():
		var content: Variant = content_of.call()
		if content is WyrdContent and (content as WyrdContent).schema != null:
			return (content as WyrdContent).schema
	return WyrdFactSchema.new()


func _recompile_eligibility() -> void:
	var schema := _schema()
	for role in _defs.keys():
		var spec: Dictionary = _defs[role]
		var text := String(spec.get("eligibility", ""))
		if text.is_empty():
			spec["eligibility_cond"] = null
			continue
		var diags := WyrdDiagnostics.new()
		var compiled := WyrdRoleDef.compile_eligibility(text, schema, diags, "save", 1, 1)
		if diags.has_errors():
			push_error("WyrdRoles: eligibility for \"%s\" did not recompile" % String(role))
			spec["eligibility_cond"] = null
			continue
		spec["eligibility_cond"] = compiled


func _succession_text(strategy: String, kind_list: Array) -> String:
	if strategy == "relation":
		var joined := ""
		for i in kind_list.size():
			if i > 0:
				joined += "|"
			joined += String(kind_list[i])
		if joined.is_empty():
			return "none"
		return "relation(%s)" % joined
	if strategy.is_empty():
		return "none"
	return strategy


func _is_told(role: StringName, agent: StringName) -> bool:
	if not _told.has(role):
		return false
	return (_told[role] as Dictionary).has(agent)


func _refresh_told(role: StringName) -> void:
	if not _told.has(role) or facts == null:
		return
	for agent in (_told[role] as Dictionary).keys():
		_write_known(role, StringName(str(agent)))


func _write_known(role: StringName, agent: StringName) -> void:
	if facts == null:
		return
	facts.remember(
		_known_key(role),
		_binding(role)["holder"],
		StringName("known/%s" % String(agent))
	)


func _known_key(role: StringName) -> StringName:
	return StringName("role.%s.holder" % String(role))


func _role_of_key(key: StringName) -> StringName:
	var text := String(key)
	if not text.begins_with("role.") or not text.ends_with(".holder"):
		return &""
	var inner := text.substr(5, text.length() - 12)
	if inner.is_empty():
		return &""
	return StringName(inner)


func _primary(slot_name: String) -> String:
	if not _slots.has(slot_name):
		return ""
	var rows: Array = _slots[slot_name]
	if rows.is_empty():
		return ""
	return str((rows[0] as Dictionary)["quest"])


func _slot_row(quest_id: String, slot_name: String) -> Dictionary:
	if not _slots.has(slot_name):
		return {}
	for item in _slots[slot_name]:
		var row: Dictionary = item
		if str(row["quest"]) == quest_id:
			return row
	return {}


func _freeze_key(quest_id: String, slot_name: String) -> String:
	return "%s\t%s" % [quest_id, slot_name]


func _quest(quest_id: String) -> WyrdQuestDef:
	if not content_of.is_valid():
		return null
	var content: Variant = content_of.call()
	if content == null or not (content is WyrdContent):
		return null
	var pack := content as WyrdContent
	if pack.quests.has(quest_id):
		return pack.quests[quest_id] as WyrdQuestDef
	if quest_id.contains("#"):
		var template_id := quest_id.split("#")[0]
		return pack.templates.get(template_id) as WyrdQuestDef
	return null


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null


func _world() -> WyrdWorldAdapter:
	if not world_of.is_valid():
		return null
	var found: Variant = world_of.call()
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
