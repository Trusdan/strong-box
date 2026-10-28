class_name WyrdGenerator
extends RefCounted

## Unsaved story-pressure queue.
##
## [method offer] appends a host offer, or replaces tier and payload when the
## same source and key are already queued. Deed hooks use [method queue_deed].
## The queue is not saved. [member generate_handler] is the runtime's handler.

## @experimental
var generate_handler: Callable = Callable()
## @experimental
var config_of: Callable = Callable()
## @experimental
var trace_of: Callable = Callable()
## @experimental
var runtime: WyrdRuntime = null

var _offers: Array[Dictionary] = []
var _proposals: Dictionary = {}
var _pending: Array[WyrdProposal] = []
var _reserved: Dictionary = {}
var _seq: int = 0
## Template id to the last decision that considered it. Not saved.
var _why: Dictionary = {}
## How many times [method _trace_candidates] ran. Not saved.
## @experimental
var candidate_traces: int = 0


## Queues a host offer, or replaces the tier and payload when that source and key are already queued. Returns false when the source, key, tier, or payload is refused.
func offer(source: StringName, key: String, tier: StringName = &"", payload: Dictionary = {}) -> bool:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if source == &"" or key.is_empty():
		push_error("Wyrd.generator.offer: source and key are required")
		return false
	if tier != &"" and tier_rank(String(tier)) < 0:
		push_error("Wyrd.generator.offer: unknown pressure tier \"%s\"" % String(tier))
		return false
	if not _payload_ok(payload):
		push_error("Wyrd.generator.offer: payload values must be string, number, or bool")
		return false
	_enqueue(source, key, tier, _copy_payload(payload), "host", "")
	return true


## Queues one deed-hook offer. [param deed_id] is the deed's id text.
## @experimental
func queue_deed(template_id: String, deed_id: String, payload: Dictionary) -> void:
	if template_id.is_empty() or deed_id.is_empty():
		return
	_enqueue(&"deed", "%s:%s" % [template_id, deed_id], &"", _copy_payload(payload), "deed", template_id)


## @experimental
func pending() -> Array:
	var out: Array = []
	for entry in _offers:
		out.append(_copy_entry(entry))
	return out


## @experimental
func pending_count() -> int:
	return _offers.size()


## @experimental
func bind(host: WyrdRuntime) -> void:
	runtime = host


## @experimental
func clear() -> void:
	_offers.clear()
	_proposals.clear()
	_pending.clear()
	_reserved.clear()
	_why.clear()
	_seq = 0
	candidate_traces = 0


## [code]-1[/code] when [param name] is empty or not in [member WyrdConfig.pressure_tiers].
## @experimental
func tier_rank(name: String) -> int:
	if name.is_empty():
		return -1
	var tiers := _tiers()
	for index in tiers.size():
		if String(tiers[index]) == name:
			return index
	return -1


## An empty offer tier matches every template. A template with no tier matches
## every offer. Unknown names do not match a tiered template.
## @experimental
func tier_matches(offer_tier: StringName, template: WyrdTemplateDef) -> bool:
	if offer_tier == &"":
		return true
	if template == null or _untiered(template):
		return true
	var offer_rank := tier_rank(String(offer_tier))
	if offer_rank < 0:
		return false
	var low := template.tier_low
	var high := template.tier_high if template.tier_range else template.tier_low
	var low_rank := tier_rank(low)
	var high_rank := tier_rank(high)
	if low_rank < 0 or high_rank < 0:
		return false
	return low_rank <= offer_rank and offer_rank <= high_rank


## Pops the oldest offer. Empty when the queue is empty.
## @experimental
func take_next() -> Dictionary:
	if _offers.is_empty():
		return {}
	var entry := _offers[0]
	_offers.remove_at(0)
	return _copy_entry(entry)


func _enqueue(
	source: StringName,
	key: String,
	tier: StringName,
	payload: Dictionary,
	origin: String,
	template_id: String
) -> void:
	for index in _offers.size():
		var row := _offers[index]
		if row["source"] != source or str(row["key"]) != key:
			continue
		row["tier"] = tier
		row["payload"] = payload
		_offers[index] = row
		_trace(source, key, tier, str(row["origin"]), str(row["template"]), _offers.size(), true, payload)
		return
	_offers.append({
		"key": key,
		"origin": origin,
		"payload": payload,
		"source": source,
		"template": template_id,
		"tier": tier,
	})
	_trace(source, key, tier, origin, template_id, _offers.size(), false, payload)


func _trace(
	source: StringName,
	key: String,
	tier: StringName,
	origin: String,
	template_id: String,
	queued: int,
	replaced: bool,
	payload: Dictionary
) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call({
		"key": key,
		"origin": origin,
		"payload": _copy_payload(payload),
		"queued": queued,
		"replaced": "true" if replaced else "false",
		"source": String(source),
		"template": template_id,
		"tier": String(tier),
	})


func _tiers() -> PackedStringArray:
	if not config_of.is_valid():
		return PackedStringArray()
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return (config as WyrdConfig).pressure_tiers
	return PackedStringArray()


func _untiered(template: WyrdTemplateDef) -> bool:
	return template.tier_low.is_empty() and template.tier_high.is_empty() and not template.tier_range


func _payload_ok(payload: Dictionary) -> bool:
	for key in payload.keys():
		if not (key is String):
			return false
		if not _value_ok(payload[key]):
			return false
	return true


func _value_ok(value: Variant) -> bool:
	if value is String or value is StringName or value is bool:
		return true
	var kind := typeof(value)
	return kind == TYPE_INT or kind == TYPE_FLOAT


func _copy_payload(payload: Dictionary) -> Dictionary:
	var copy := {}
	for key in payload.keys():
		copy[String(key)] = payload[key]
	return copy


func _copy_entry(entry: Dictionary) -> Dictionary:
	return {
		"key": str(entry.get("key", "")),
		"origin": str(entry.get("origin", "")),
		"payload": _copy_payload(entry.get("payload", {})),
		"source": StringName(str(entry.get("source", ""))),
		"template": str(entry.get("template", "")),
		"tier": StringName(str(entry.get("tier", ""))),
	}


## @experimental
func proposal(id: String) -> WyrdProposal:
	return _proposals.get(id) as WyrdProposal


## @experimental
func pending_creations() -> Array:
	var out: Array = []
	for item in _pending:
		out.append(item)
	return out


## @experimental
func finish_reservations() -> void:
	_pending.clear()
	_reserved.clear()


func _accept_origin(proposal: WyrdProposal) -> String:
	if proposal == null:
		return "host"
	for item in _pending:
		if item == proposal:
			return "queue"
	return "host"


## Host pick. Not queued. Null when the input is rejected or nothing can be proposed.
func propose(context: Dictionary) -> WyrdProposal:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	if context == null:
		push_error("Wyrd.generator.propose: source and key are required")
		return null
	var source := StringName(str(context.get("source", "")))
	var key := str(context.get("key", ""))
	if source == &"" or key.is_empty():
		push_error("Wyrd.generator.propose: source and key are required")
		return null
	var tier := StringName(str(context.get("tier", "")))
	if tier != &"" and tier_rank(String(tier)) < 0:
		push_error("Wyrd.generator.propose: unknown pressure tier \"%s\"" % String(tier))
		return null
	var payload: Dictionary = context.get("payload", {}) if context.get("payload") is Dictionary else {}
	if not _payload_ok(payload):
		push_error("Wyrd.generator.propose: payload values must be string, number, or bool")
		return null
	return _decide(source, key, tier, str(context.get("template", "")), _copy_payload(payload), "host", false)


## One generate-queue unit. Reserves a successful proposal for the end of the tick.
## @experimental
func fulfill(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_decide(
		StringName(str(entry.get("source", ""))),
		str(entry.get("key", "")),
		StringName(str(entry.get("tier", ""))),
		str(entry.get("template", "")),
		_copy_payload(entry.get("payload", {})),
		str(entry.get("origin", "")),
		true
	)


## [code]unknown[/code], [code]accepted[/code], [code]stale[/code], or the new instance id.
func accept(proposal: WyrdProposal) -> String:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var proposal_id := ""
	var instance := ""
	var reason := "unknown"
	var ok := false
	if proposal != null:
		proposal_id = proposal.id
	if proposal == null or proposal.id.is_empty() or not _proposals.has(proposal.id):
		reason = "unknown"
	elif proposal.used:
		reason = "accepted"
		instance = proposal.instance
	elif runtime == null or runtime.quests == null or runtime.quests.template_counter(proposal.template) != proposal.expected_counter:
		reason = "stale"
	else:
		instance = runtime.quests.create_instance(proposal.template, proposal.casts, proposal.params)
		if instance == "":
			reason = "refused"
		else:
			proposal.used = true
			proposal.instance = instance
			ok = true
			reason = "created"
			_why_put(proposal.template, "created")
	_trace_line("gen_accept", {
		"instance": instance,
		"ok": "true" if ok else "false",
		"origin": _accept_origin(proposal),
		"proposal": proposal_id,
		"reason": reason,
	}, "wyrd gen_accept proposal=%s ok=%s reason=%s instance=%s" % [proposal_id, "true" if ok else "false", reason, instance])
	if reason == "unknown" or reason == "stale" or reason == "accepted":
		return reason
	return instance


## [code]{template, reason, rules}[/code], or [code]{reason: missing}[/code] for an unknown id.
## An existing template with no decision yet has an empty reason. Not saved.
## @experimental
func why_not(template_id: String) -> Dictionary:
	if runtime == null or runtime.content() == null or not runtime.content().templates.has(template_id):
		return {"reason": "missing"}
	if not _why.has(template_id):
		return {"filter": "", "name": "", "reason": "", "rules": [], "template": template_id}
	var row: Dictionary = _why[template_id]
	var rules: Array = row.get("rules", [])
	return {
		"filter": str(row.get("filter", "")),
		"name": str(row.get("name", "")),
		"reason": str(row.get("reason", "")),
		"rules": rules.duplicate(true),
		"template": template_id,
	}


func _decide(
	source: StringName,
	key: String,
	tier: StringName,
	template_filter: String,
	payload: Dictionary,
	origin: String,
	reserve: bool
) -> WyrdProposal:
	var retries := _retry_limit()
	var excluded := {}
	var rejected := false
	var stop_reason := ""
	var tracing := _tracing()
	for attempt in range(retries + 1):
		var eligible := _eligible(tier, template_filter, tracing)
		var seed_key := _attempt_key("pick:%s:%s" % [String(source), key], attempt)
		if tracing:
			_trace_line("gen_tier", {
				"eligible": eligible.size(),
				"key": key,
				"source": String(source),
				"tier": String(tier),
			}, "wyrd gen_tier source=%s key=%s tier=%s eligible=%d" % [String(source), key, String(tier), eligible.size()])
		if eligible.is_empty():
			if tracing:
				_trace_line("gen_pick", {
					"band": 0,
					"key": key,
					"reason": "no_template",
					"score": "0/0",
					"seed_key": seed_key,
					"source": String(source),
					"template": "",
				}, "wyrd gen_pick source=%s key=%s template= reason=no_template score=0/0 band=0 seed_key=%s" % [String(source), key, seed_key])
			stop_reason = "no_template"
			break
		var band := _top_band(eligible)
		var chosen: WyrdTemplateDef = _weighted(band, seed_key)
		for template in eligible:
			if template.id != chosen.id:
				_why_put(template.id, "not_picked")
		if tracing:
			var score := "%d/%d" % [chosen.priority, chosen.specificity]
			_trace_line("gen_pick", {
				"band": band.size(),
				"key": key,
				"score": score,
				"seed_key": seed_key,
				"source": String(source),
				"template": chosen.id,
			}, "wyrd gen_pick source=%s key=%s template=%s score=%s band=%d seed_key=%s" % [String(source), key, chosen.id, score, band.size(), seed_key])
		var expected := _counter(chosen.id) + _reserved_count(chosen.id)
		var instance := "%s#%d" % [chosen.id, expected + 1]
		var casts := {}
		var params := {}
		if runtime != null:
			runtime.begin_provisional(instance)
			runtime.push_scope(instance)
		var failed_name := _bind_template(chosen, instance, casts, params, attempt, excluded, tracing)
		var problem := {}
		if failed_name.is_empty():
			problem = _validate(chosen, instance, casts, params, attempt)
		if runtime != null:
			runtime.pop_scope()
			runtime.end_provisional()
		if not failed_name.is_empty():
			_why_put(chosen.id, "no_candidate", "", failed_name)
			stop_reason = "no_candidate"
			break
		if not problem.is_empty():
			rejected = true
			var rule := str(problem.get("rule", ""))
			var ident := str(problem.get("id", ""))
			if tracing:
				_trace_line("gen_reject", {
					"attempt": attempt,
					"id": ident,
					"instance": instance,
					"rule": rule,
					"template": chosen.id,
				}, "wyrd gen_reject template=%s instance=%s rule=%s id=%s attempt=%d" % [chosen.id, instance, rule, ident, attempt])
			_why_reject(chosen.id, rule, ident, attempt)
			if rule == "exists" or rule == "place" or rule == "protected" or rule == "bounds":
				excluded[ident] = true
			continue
		_why_put(chosen.id, "proposed")
		var proposal := WyrdProposal.new()
		_seq += 1
		proposal.id = "p%d" % _seq
		proposal.source = String(source)
		proposal.key = key
		proposal.tier = String(tier)
		proposal.origin = origin
		proposal.template = chosen.id
		proposal.instance = instance
		proposal.casts = casts
		proposal.params = params
		proposal.payload = _copy_payload(payload)
		proposal.expected_counter = expected
		_proposals[proposal.id] = proposal
		if reserve:
			_reserved[chosen.id] = _reserved_count(chosen.id) + 1
			_pending.append(proposal)
		else:
			if tracing:
				_trace_propose(source, key, tier, payload, true, "proposed", proposal.id)
		return proposal
	var reason := stop_reason
	if rejected:
		reason = "rejected"
	if reason.is_empty():
		reason = "no_template"
	if not reserve and tracing:
		_trace_propose(source, key, tier, payload, false, reason, "")
	return null


func _trace_propose(
	source: StringName,
	key: String,
	tier: StringName,
	payload: Dictionary,
	ok: bool,
	reason: String,
	proposal_id: String
) -> void:
	var flag := "true" if ok else "false"
	_trace_line("gen_propose", {
		"key": key,
		"ok": flag,
		"payload": _copy_payload(payload),
		"proposal": proposal_id,
		"reason": reason,
		"source": String(source),
		"tier": String(tier),
	}, "wyrd gen_propose source=%s key=%s ok=%s reason=%s proposal=%s" % [String(source), key, flag, reason, proposal_id])


func _eligible(tier: StringName, template_filter: String, tracing: bool = false) -> Array[WyrdTemplateDef]:
	var found: Array[WyrdTemplateDef] = []
	if runtime == null or runtime.content() == null:
		return found
	var ids: Array = runtime.content().templates.keys()
	ids.sort()
	for id in ids:
		var template: WyrdTemplateDef = runtime.content().templates[id]
		if template == null:
			continue
		if not template_filter.is_empty() and template.id != template_filter:
			continue
		if not tier_matches(tier, template):
			_why_put(template.id, "filtered", "tier")
			continue
		if template.weight <= 0:
			_why_put(template.id, "filtered", "weight")
			continue
		if not _when_ok(template):
			_why_put(template.id, "filtered", "when")
			continue
		var live := 0
		if runtime.quests != null:
			live = runtime.quests.active_count(template.id)
		var reserved := _reserved_count(template.id)
		if live + reserved >= template.max_active:
			if tracing:
				_trace_line("gen_cap", {
					"active": live,
					"max": template.max_active,
					"reserved": reserved,
					"template": template.id,
				}, "wyrd gen_cap template=%s active=%d reserved=%d max=%d" % [template.id, live, reserved, template.max_active])
			_why_put(template.id, "filtered", "cap")
			continue
		found.append(template)
	return found


func _when_ok(template: WyrdTemplateDef) -> bool:
	if template.when_cond == null or runtime == null:
		return true
	return runtime.eval_storylet(template.when_cond, template.id)


func _top_band(eligible: Array[WyrdTemplateDef]) -> Array[WyrdTemplateDef]:
	var best_priority := 0
	var best_specificity := 0
	var first := true
	for template in eligible:
		if first or template.priority > best_priority or (template.priority == best_priority and template.specificity > best_specificity):
			best_priority = template.priority
			best_specificity = template.specificity
			first = false
	var band: Array[WyrdTemplateDef] = []
	for template in eligible:
		if template.priority == best_priority and template.specificity == best_specificity:
			band.append(template)
	return band


func _weighted(band: Array[WyrdTemplateDef], seed_key: String) -> WyrdTemplateDef:
	var total := 0
	for template in band:
		total += maxi(template.weight, 0)
	if band.size() == 1 or total <= 0 or runtime == null:
		return band[0]
	var rng := WyrdRng.for_decision(runtime.game_seed(), &"generator", StringName(seed_key), runtime.now_minutes())
	var roll := rng.randi_bounded(total)
	var cursor := 0
	for template in band:
		cursor += maxi(template.weight, 0)
		if roll < cursor:
			return template
	return band[band.size() - 1]


func _bind_template(
	template: WyrdTemplateDef,
	instance: String,
	casts: Dictionary,
	params: Dictionary,
	attempt: int,
	excluded: Dictionary,
	tracing: bool = false
) -> String:
	if runtime == null or runtime.roles == null:
		return "bind"
	for slot in template.slots:
		if slot.mode != &"cast":
			continue
		var pool := runtime.roles.cast_pool(slot)
		var decision := _attempt_key("cast:%s.%s" % [instance, slot.name], attempt)
		if tracing:
			_trace_candidates(decision, pool["raw"])
		var picked := runtime.roles.pick_id(_without(pool["accepted"], excluded), &"generator", decision)
		if picked == &"":
			return slot.name
		casts[slot.name] = String(picked)
		runtime.provisional_cast(slot.name, picked)
		if tracing:
			_trace_line("gen_cast", {
				"entity": String(picked),
				"instance": instance,
				"kind": slot.kind,
				"slot": slot.name,
			}, "wyrd gen_cast instance=%s slot=%s kind=%s entity=%s" % [instance, slot.name, slot.kind, String(picked)])
	for param in template.params:
		var pool := runtime.roles.param_pool(param)
		var decision := _attempt_key("param:%s.%s" % [instance, param.name], attempt)
		if tracing:
			_trace_candidates(decision, pool["raw"])
		var picked := runtime.roles.pick_id(_without(pool["accepted"], excluded), &"generator", decision)
		if picked == &"":
			return param.name
		params[param.name] = _param_snapshot(param, picked)
		runtime.provisional_param(param.name, picked)
		if tracing:
			_trace_line("gen_bind", {
				"entity": String(picked),
				"instance": instance,
				"kind": param.kind,
				"param": param.name,
			}, "wyrd gen_bind instance=%s param=%s kind=%s entity=%s" % [instance, param.name, param.kind, String(picked)])
	return ""


func _param_snapshot(param: WyrdParamDef, entity: StringName) -> Dictionary:
	var snap := {"entity": String(entity), "kind": param.kind}
	if param.kind == "item" and runtime != null:
		var inventory := runtime.adapter(WyrdInventoryAdapter) as WyrdInventoryAdapter
		if inventory != null:
			snap["owner"] = String(inventory.owner_of(entity))
	if (param.kind == "item" or param.kind == "object") and runtime != null:
		var spatial := runtime.adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
		if spatial != null:
			snap["place"] = String(spatial.place_of(entity))
	return snap


func _trace_candidates(decision_key: String, raw: Array) -> void:
	candidate_traces += 1
	var digest := _candidate_digest(raw)
	var shown := WyrdRng.format_u64(digest)
	_trace_line("gen_candidates", {
		"count": raw.size(),
		"digest": shown,
		"key": decision_key,
	}, "wyrd gen_candidates key=%s count=%d digest=%s" % [decision_key, raw.size(), shown])


func _candidate_digest(raw: Array) -> int:
	if runtime != null and runtime.roles != null and runtime.roles.indexed_pool():
		if runtime.roles.indexed_digest_ready():
			return runtime.roles.indexed_digest()
		var stored := _hash_candidates(raw)
		runtime.roles.store_indexed_digest(stored)
		return stored
	return _hash_candidates(raw)


func _hash_candidates(raw: Array) -> int:
	var digest := WyrdHash.of_int(0)
	for id in raw:
		digest = WyrdHash.combine(digest, WyrdHash.of_string_name(StringName(str(id))))
	return digest


func _tracing() -> bool:
	return runtime != null and runtime.trace != null and runtime.trace.enabled


func _trace_line(kind: String, fields: Dictionary, line: String) -> void:
	if runtime == null:
		return
	runtime.trace_gen_line(kind, fields, line)


func _counter(template_id: String) -> int:
	if runtime == null or runtime.quests == null:
		return 0
	return runtime.quests.template_counter(template_id)


func _reserved_count(template_id: String) -> int:
	return int(_reserved.get(template_id, 0))


func _retry_limit() -> int:
	if not config_of.is_valid():
		return 8
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return maxi((config as WyrdConfig).generator_retries, 0)
	return 8


func _attempt_key(base: String, attempt: int) -> String:
	if attempt <= 0:
		return base
	return "%s:%d" % [base, attempt]


func _without(ids: Array, excluded: Dictionary) -> Array:
	if excluded.is_empty():
		return ids
	var kept: Array = []
	for item in ids:
		if excluded.has(String(item)):
			continue
		kept.append(item)
	return kept


func _why_put(template_id: String, reason: String, filter_name: String = "", slot_name: String = "") -> void:
	var row: Dictionary = _why.get(template_id, {"filter": "", "name": "", "reason": "", "rules": []})
	if reason == "not_picked" and str(row.get("reason", "")) == "rejected":
		return
	row["reason"] = reason
	if reason == "filtered":
		row["filter"] = filter_name
	elif reason != "rejected":
		row["filter"] = ""
	if reason == "no_candidate":
		row["name"] = slot_name
	elif reason != "rejected":
		row["name"] = ""
	_why[template_id] = row


func _why_reject(template_id: String, rule: String, ident: String, attempt: int) -> void:
	var row: Dictionary = _why.get(template_id, {"filter": "", "name": "", "reason": "", "rules": []})
	var rules: Array = row.get("rules", [])
	rules.append({"attempt": attempt, "id": ident, "rule": rule})
	row["reason"] = "rejected"
	row["rules"] = rules
	_why[template_id] = row


## Empty when the proposal passes. Otherwise [code]{rule, id}[/code].
## [code]place[/code] stays in this order and rejects nothing: an empty
## [code]place_of[/code] is "not tracked", and the adapters cannot tell that
## from a place the host tracks and left empty.
func _validate(
	template: WyrdTemplateDef,
	_instance: String,
	casts: Dictionary,
	params: Dictionary,
	_attempt: int
) -> Dictionary:
	var world := _world()
	for row in _bound_rows(template, casts, params):
		var id := StringName(str(row.get("id", "")))
		var kind := str(row.get("kind", ""))
		if world != null and not world.exists(id):
			return {"id": String(id), "rule": "exists"}
		if _spatial() != null and _place_rejected(id, kind):
			return {"id": String(id), "rule": "place"}
		if world != null and not template.allow_protected and world.is_protected(id):
			return {"id": String(id), "rule": "protected"}
		var pack := ""
		if runtime != null and runtime.content() != null:
			pack = runtime.content().pack_id
		if world != null and not world.in_bounds(id, pack):
			return {"id": String(id), "rule": "bounds"}
	var index := 0
	for cond in template.assumption_conds:
		index += 1
		if not _assumption_true(cond):
			return {"id": "assumes.%d" % index, "rule": "assumes"}
		var known := _known_conflict(cond)
		if not known.is_empty():
			return known
	return {}


func _bound_rows(template: WyrdTemplateDef, casts: Dictionary, params: Dictionary) -> Array:
	var rows: Array = []
	for slot in template.slots:
		if slot.mode != &"cast":
			continue
		if not casts.has(slot.name):
			continue
		rows.append({"id": String(casts[slot.name]), "kind": slot.kind})
	for param in template.params:
		if not params.has(param.name):
			continue
		var snap: Variant = params[param.name]
		var entity := ""
		if snap is Dictionary:
			entity = str((snap as Dictionary).get("entity", ""))
		rows.append({"id": entity, "kind": param.kind})
	return rows


## The carried-item case this rule would reject cannot be told from an untracked
## place, so the step passes.
func _place_rejected(_id: StringName, _kind: String) -> bool:
	return false


func _assumption_true(cond: WyrdCompiledCondition) -> bool:
	if cond == null or runtime == null:
		return true
	# eval_storylet pushes an empty scope, which would hide this provisional
	# instance and could read another instance's casts.
	return runtime.eval_bool(cond)


func _known_conflict(cond: WyrdCompiledCondition) -> Dictionary:
	if cond == null or runtime == null or runtime.facts == null:
		return {}
	for key in cond.reads:
		var known: Variant = runtime.facts.get_in(key, &"known/player")
		if not _known_differs(known, runtime.facts.get_in(key)):
			continue
		return {"id": String(key), "rule": "known"}
	return {}


func _known_differs(known: Variant, world_value: Variant) -> bool:
	if known == null:
		return false
	return known != world_value


func _world() -> WyrdWorldAdapter:
	if runtime == null:
		return null
	return runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter


func _spatial() -> WyrdSpatialAdapter:
	if runtime == null:
		return null
	return runtime.adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
