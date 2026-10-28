class_name WyrdRumor
extends RefCounted

## Precise rumor hops and coarse reach.
##
## @experimental
## A deed starts a rumor when it carries a reveal claim and the first registered
## policy matches its verb. Origins are the actor and that row's witnesses.
## That slice is the witness index for the deed, so this does not scan the log.
## Each origin offers the claim to sorted [method WyrdSocial.targets] of the
## policy kinds. A listener is queued once, from the earliest speaker.
## The hop rolls [method WyrdRng.for_decision] on stream [code]rumor[/code].
## The decision key is [code]deed, from, to, hop[/code]. The time bucket is the
## hour bucket of [code]now[/code]. Adoption uses the credibility score and
## threshold, and writes [code]believed/<listener>[/code] only.
## A listener in a coarse place does not adopt and does not pass the claim on.
## Empty places count as precise.
## A deed in a coarse place stores a reach row instead of hops. Each coarse
## tick enqueues one rumor unit that raises that row's level by one.
## [method materialize] rolls once when content asks about one NPC there.
## An accepted hop or materialize then evaluates [member WyrdRumorPolicy.mutations]
## on the claim value. The listener stores that copy. The deed row is unchanged.
## Jobs, the seen set, the queued set, reach rows, the once-set, and those
## copies are saved in [code]flight.rumor[/code]. Mutation callables are not.
## Load rebinds them from the registered policy with the same id.
## A job or reach row whose policy is not registered is [code]push_error[/code]
## and that deed's in-flight state is left out. Beliefs already written stay.

## Level at or above this is a certain materialize roll, because [code]randf[/code]
## is below 1. Chance is [code]level / REACH_FULL[/code]. Level 0 does not roll.
const REACH_FULL := 4

var social: WyrdSocial
var facts: WyrdFactStore
var deeds: WyrdDeedLog
var config_of: Callable = Callable()
var seed_of: Callable = Callable()
var now_of: Callable = Callable()
var spatial_of: Callable = Callable()
var score_of: Callable = Callable()
var threshold_of: Callable = Callable()
var trace_of: Callable = Callable()
## [code]() -> bool[/code]. When this is valid and false, hop traces are not built.
var tracing_of: Callable = Callable()
## [code](token: String)[/code]. One rumor unit. The token is saved with the scheduler.
var enqueue_hop: Callable = Callable()
## [code](present: bool)[/code]. Fired when the reach list goes from empty to
## occupied, or back. The belief cache reads this so an empty list can return
## without calling in here.
var on_reach: Callable = Callable()
## True when any coarse reach row is stored, including level 0.
var reach_any: bool = false

var _policies: Array[WyrdRumorPolicy] = []
var _jobs: Dictionary = {}
var _seen: Dictionary = {}
var _queued: Dictionary = {}
var _reach: Dictionary = {}
var _drawn: Dictionary = {}
var _held: Dictionary = {}
var _gone: Dictionary = {}


func register(policy: WyrdRumorPolicy) -> void:
	if policy == null or String(policy.id).is_empty():
		push_error("WyrdRumor.register: policy needs an id")
		return
	var copy := WyrdRumorPolicy.new()
	copy.id = policy.id
	copy.kinds = policy.kinds.duplicate()
	copy.max_hops = maxi(policy.max_hops, 0)
	copy.verbs = policy.verbs.duplicate()
	var chance := policy.pass_chance
	if is_nan(chance) or is_inf(chance):
		chance = 0.0
	copy.pass_chance = clampf(chance, 0.0, 1.0)
	copy.mutations = _copy_mutations(policy.mutations)
	_policies.append(copy)


## Drops in-flight claims, hop memory, reach rows, materialize draws, and
## mutated copies. Registered policies stay.
func clear_flight() -> void:
	_jobs.clear()
	_seen.clear()
	_queued.clear()
	_reach.clear()
	_reach_changed(false)
	_drawn.clear()
	_held.clear()
	_gone.clear()


## Claim table, hop memory, reach rows, draws, and mutated copies.
## Callables are omitted. An empty bag is omitted by the save.
func export_state() -> Dictionary:
	var out := {}
	var drawn := _sorted_keys(_drawn)
	if not drawn.is_empty():
		out["drawn"] = drawn
	var gone := _export_pairs(_gone)
	if not gone.is_empty():
		out["gone"] = gone
	var held := _export_held()
	if not held.is_empty():
		out["held"] = held
	var jobs := _export_jobs()
	if not jobs.is_empty():
		out["jobs"] = jobs
	var queued := _export_people(_queued)
	if not queued.is_empty():
		out["queued"] = queued
	var reach := _export_reach()
	if not reach.is_empty():
		out["reach"] = reach
	var seen := _export_people(_seen)
	if not seen.is_empty():
		out["seen"] = seen
	return out


## Replaces in-flight state. [param data] empty clears it.
## Mutations come from the policy already registered under that id.
## Each returned row is a deed whose policy id was not registered.
## That deed's jobs, reach rows, copies, and claim table are not loaded.
## [method WyrdSave.apply] drops that deed's rumor tokens and records
## [constant WyrdDiagnostic.E_SAVE_POLICY].
func import_state(data: Dictionary) -> Array:
	clear_flight()
	var missing := _missing_policies(data)
	var dropped := {}
	for row in missing:
		dropped[str(row.get("deed", ""))] = true
	for item in _rows(data.get("jobs", [])):
		var deed_id := str(item.get("deed", ""))
		if deed_id.is_empty() or dropped.has(deed_id):
			continue
		var policy_id := str(item.get("policy", ""))
		_jobs[deed_id] = {
			"chance": WyrdSave.number_of(item.get("chance", 0.0), 0.0),
			"key": str(item.get("key", "")),
			"kinds": _kind_list(item.get("kinds", [])),
			"max_hops": WyrdSave._whole(item.get("max_hops", 0), 0),
			"mutations": _mutations_for(policy_id),
			"policy": policy_id,
			"value": WyrdSave.unpack_claim(item.get("value")),
			"verb": str(item.get("verb", "")),
		}
	_import_people(_seen, data.get("seen", []), dropped)
	_import_people(_queued, data.get("queued", []), dropped)
	for item in _rows(data.get("reach", [])):
		var deed_id := str(item.get("deed", ""))
		var place := str(item.get("place", ""))
		if deed_id.is_empty() or place.is_empty() or dropped.has(deed_id):
			continue
		var policy_id := str(item.get("policy", ""))
		_reach["%s\t%s" % [deed_id, place]] = {
			"born": WyrdSave._whole(item.get("born", 0), 0),
			"deed": deed_id,
			"key": str(item.get("key", "")),
			"level": WyrdSave._whole(item.get("level", 0), 0),
			"pending": WyrdSave._whole(item.get("pending", 0), 0),
			"mutations": _mutations_for(policy_id),
			"place": place,
			"policy": policy_id,
			"value": WyrdSave.unpack_claim(item.get("value")),
			"verb": str(item.get("verb", "")),
		}
	for item in _list(data.get("drawn", [])):
		var token := WyrdSave.text_of(item, "")
		if token.is_empty() or dropped.has(_deed_of_pair(token)):
			continue
		_drawn[token] = true
	for item in _rows(data.get("held", [])):
		var deed_id := str(item.get("deed", ""))
		var who := str(item.get("who", ""))
		if deed_id.is_empty() or who.is_empty() or dropped.has(deed_id):
			continue
		_held["%s\t%s" % [deed_id, who]] = WyrdSave.unpack_claim(item.get("value"))
	for item in _rows(data.get("gone", [])):
		var deed_id := str(item.get("deed", ""))
		var who := str(item.get("who", ""))
		if deed_id.is_empty() or who.is_empty() or dropped.has(deed_id):
			continue
		_gone["%s\t%s" % [deed_id, who]] = true
	_reach_changed(not _reach.is_empty())
	return missing


## Names the policy id and the deed. Used by [code]push_error[/code] and [code]E_SAVE_POLICY[/code].
static func missing_policy_message(policy_id: String, deed_id: String) -> String:
	return "rumor policy \"%s\" is not registered for deed %s" % [policy_id, deed_id]


## Applied coarse ticks for [param deed_id] at [param place]. [code]-1[/code]
## when that pair has no row.
func reach_level(deed_id: String, place: StringName) -> int:
	var key := "%s\t%s" % [deed_id, String(place)]
	if not _reach.has(key):
		return -1
	return int((_reach[key] as Dictionary).get("level", 0))


## Starts a rumor for [param deed] when a policy matches.
## A precise place queues hops. A coarse place stores a reach row at level 0.
func note_deed(deed: Dictionary, claim_key: String, claim_value: Variant) -> void:
	if claim_key.is_empty() or social == null:
		return
	var verb := StringName(str(deed.get("verb", "")))
	var policy := _policy_for(verb)
	if policy == null or policy.max_hops < 1 or policy.kinds.is_empty():
		return
	var place := StringName(str(deed.get("place", "")))
	if _place_is_coarse(place):
		_note_reach(deed, policy, claim_key, claim_value, place, verb)
		return
	var deed_id := str(int(deed.get("id", 0)))
	if deed_id == "0" or _jobs.has(deed_id):
		return
	_jobs[deed_id] = {
		"chance": policy.pass_chance,
		"key": claim_key,
		"kinds": policy.kinds.duplicate(),
		"max_hops": policy.max_hops,
		"mutations": policy.mutations,
		"policy": String(policy.id),
		"value": claim_value,
		"verb": String(verb),
	}
	var seen := {}
	for person in _origins(deed):
		seen[String(person)] = true
	_seen[deed_id] = seen
	_queued[deed_id] = {}
	var speakers := PackedStringArray()
	for person in seen.keys():
		speakers.append(String(person))
	speakers.sort()
	for person in speakers:
		_enqueue_from(deed_id, person, 1)


## Queues one rumor unit per coarse boundary crossed since each row was born.
## The spatial adapter is read here. A place that is no longer coarse gains no
## new unit. Units already queued still run.
func enqueue_due() -> void:
	if not enqueue_hop.is_valid() or _reach.is_empty():
		return
	var coarse := _coarse_minutes()
	if coarse <= 0:
		return
	var now := _now()
	var keys := PackedStringArray()
	for key in _reach.keys():
		keys.append(String(key))
	keys.sort()
	for key in keys:
		var row: Dictionary = _reach[key]
		var place := StringName(str(row.get("place", "")))
		if not _place_is_coarse(place):
			continue
		var target := _coarse_index(now, coarse) - _coarse_index(int(row.get("born", 0)), coarse)
		if target < 0:
			target = 0
		var have := int(row.get("level", 0)) + int(row.get("pending", 0))
		var deed_id := str(row.get("deed", ""))
		while have < target:
			have += 1
			row["pending"] = int(row.get("pending", 0)) + 1
			enqueue_hop.call("reach\t%s\t%s\t%d" % [deed_id, String(place), have])


## One rumor unit. A token this runtime did not write is ignored.
func hop(token: String) -> void:
	var parts := token.split("\t")
	if parts.size() == 4 and parts[0] == "reach":
		_apply_reach(parts[1], parts[2], int(parts[3]))
		return
	if parts.size() != 4:
		return
	var deed_id := parts[0]
	var from_who := parts[1]
	var to_who := parts[2]
	var hop_n := int(parts[3])
	if deed_id.is_empty() or from_who.is_empty() or to_who.is_empty() or not _jobs.has(deed_id):
		return
	if not _seen.has(deed_id):
		_seen[deed_id] = {}
	var seen: Dictionary = _seen[deed_id]
	if bool(seen.get(to_who, false)):
		return
	seen[to_who] = true
	var job: Dictionary = _jobs[deed_id]
	var key := str(job.get("key", ""))
	var policy_id := str(job.get("policy", ""))
	var verb := str(job.get("verb", ""))
	if _listener_is_coarse(StringName(to_who)):
		_trace_hop(deed_id, from_who, to_who, hop_n, key, policy_id, verb, false, "coarse")
		return
	var taken := _roll(deed_id, from_who, to_who, hop_n, float(job.get("chance", 0.0)))
	_trace_hop(deed_id, from_who, to_who, hop_n, key, policy_id, verb, taken, "pass" if taken else "chance")
	if not taken:
		return
	var score := _score(to_who, from_who)
	var accepted := score >= _threshold()
	if not accepted:
		_trace_adopt(from_who, to_who, key, policy_id, verb, score, false)
		return
	var offered := _speaker_copy(deed_id, from_who, job.get("value"))
	if not bool(offered.get("present", false)):
		_trace_adopt(from_who, to_who, key, policy_id, verb, score, false)
		return
	var mutated := _apply_mutations(
		deed_id,
		from_who,
		to_who,
		hop_n,
		key,
		policy_id,
		offered.get("value"),
		job.get("mutations", [])
	)
	if not bool(mutated.get("present", false)):
		_mark_gone(deed_id, to_who)
		_trace_adopt(from_who, to_who, key, policy_id, verb, score, false)
		return
	accepted = facts != null and facts.set_in(StringName(key), mutated.get("value"), StringName("believed/%s" % to_who))
	if accepted:
		_mark_held(deed_id, to_who, mutated.get("value"))
		_note_believer(deed_id, to_who)
	_trace_adopt(from_who, to_who, key, policy_id, verb, score, accepted)
	if not accepted:
		return
	if hop_n < int(job.get("max_hops", 0)):
		_enqueue_from(deed_id, to_who, hop_n + 1)


## True when any coarse reach row is stored, including a row still at level 0.
func has_reach() -> bool:
	return reach_any


func _reach_changed(present: bool) -> void:
	if reach_any == present:
		return
	reach_any = present
	if on_reach.is_valid():
		on_reach.call(present)


## Rolls once for the lowest undrawn reach row at [param who]'s coarse place.
## An accept writes [code]believed/<who>[/code]. A reject is also once.
## Level 0 does not roll. An existing belief is left as it is.
func materialize(who: StringName, key: StringName) -> void:
	if _reach.is_empty() or who == &"" or key == &"":
		return
	var who_text := String(who)
	var fact := String(key)
	if facts != null and facts.get_in(key, StringName("believed/%s" % who_text)) != null:
		return
	var spatial := _spatial()
	if spatial == null:
		return
	var place := spatial.place_of(who)
	if place == &"" or not _place_is_coarse(place):
		return
	var place_text := String(place)
	var best: Dictionary = {}
	var best_id := -1
	for item in _reach.values():
		var row: Dictionary = item
		if str(row.get("place", "")) != place_text or str(row.get("key", "")) != fact:
			continue
		if int(row.get("level", 0)) < 1:
			continue
		var deed_num := str(row.get("deed", ""))
		if _drawn.has("%s\t%s" % [deed_num, who_text]):
			continue
		var id_num := int(deed_num)
		if best_id >= 0 and id_num >= best_id:
			continue
		best = row
		best_id = id_num
	if best.is_empty():
		return
	var deed_id := str(best.get("deed", ""))
	var level := int(best.get("level", 0))
	var chance := clampf(float(level) / float(REACH_FULL), 0.0, 1.0)
	var decision := StringName("materialize\t%s\t%s\t%s\t%d" % [deed_id, place_text, who_text, level])
	var roll := WyrdRng.decision_unit(_seed(), &"rumor", decision, _time_bucket())
	var accepted := roll < chance
	_drawn["%s\t%s" % [deed_id, who_text]] = true
	var policy_id := str(best.get("policy", ""))
	if accepted:
		var mutated := _apply_mutations(
			deed_id,
			place_text,
			who_text,
			level,
			fact,
			policy_id,
			best.get("value"),
			best.get("mutations", [])
		)
		if bool(mutated.get("present", false)):
			accepted = facts != null and facts.set_in(key, mutated.get("value"), StringName("believed/%s" % who_text))
			if accepted:
				_mark_held(deed_id, who_text, mutated.get("value"))
				_note_believer(deed_id, who_text)
		else:
			accepted = false
			_mark_gone(deed_id, who_text)
	_trace_materialize(who_text, place_text, policy_id, fact, deed_id, level, chance, accepted)


func _export_jobs() -> Array:
	var out: Array = []
	var ids := _sorted_keys(_jobs)
	for deed_id in ids:
		var job: Dictionary = _jobs[deed_id]
		out.append({
			"chance": float(job.get("chance", 0.0)),
			"deed": String(deed_id),
			"key": str(job.get("key", "")),
			"kinds": _string_list(job.get("kinds", PackedStringArray())),
			"max_hops": int(job.get("max_hops", 0)),
			"policy": str(job.get("policy", "")),
			"value": WyrdSave.pack_claim(job.get("value")),
			"verb": str(job.get("verb", "")),
		})
	return out


func _export_reach() -> Array:
	var out: Array = []
	var keys := _sorted_keys(_reach)
	for key in keys:
		var row: Dictionary = _reach[key]
		out.append({
			"born": int(row.get("born", 0)),
			"deed": str(row.get("deed", "")),
			"key": str(row.get("key", "")),
			"level": int(row.get("level", 0)),
			"pending": int(row.get("pending", 0)),
			"place": str(row.get("place", "")),
			"policy": str(row.get("policy", "")),
			"value": WyrdSave.pack_claim(row.get("value")),
			"verb": str(row.get("verb", "")),
		})
	return out


func _export_held() -> Array:
	var out: Array = []
	var keys := _sorted_keys(_held)
	for key in keys:
		var parts := String(key).split("\t")
		if parts.size() != 2:
			continue
		out.append({
			"deed": parts[0],
			"value": WyrdSave.pack_claim(_held[key]),
			"who": parts[1],
		})
	return out


func _export_pairs(bag: Dictionary) -> Array:
	var out: Array = []
	var keys := _sorted_keys(bag)
	for key in keys:
		var parts := String(key).split("\t")
		if parts.size() != 2:
			continue
		out.append({"deed": parts[0], "who": parts[1]})
	return out


func _export_people(bag: Dictionary) -> Array:
	var out: Array = []
	var ids := _sorted_keys(bag)
	for deed_id in ids:
		var who: Array = []
		var people: Variant = bag[deed_id]
		if people is Dictionary:
			for person in (people as Dictionary).keys():
				who.append(String(person))
		who.sort()
		out.append({"deed": String(deed_id), "who": who})
	return out


func _import_people(into: Dictionary, raw: Variant, dropped: Dictionary) -> void:
	for item in _rows(raw):
		var deed_id := str(item.get("deed", ""))
		if deed_id.is_empty() or dropped.has(deed_id):
			continue
		var bag := {}
		for person in _list(item.get("who", [])):
			var name := WyrdSave.text_of(person, "")
			if not name.is_empty():
				bag[name] = true
		into[deed_id] = bag


func _mutations_for(policy_id: String) -> Array:
	if policy_id.is_empty():
		return []
	for policy in _policies:
		if String(policy.id) == policy_id:
			return policy.mutations
	return []


func _has_policy(policy_id: String) -> bool:
	if policy_id.is_empty():
		return false
	for policy in _policies:
		if String(policy.id) == policy_id:
			return true
	return false


## One row per missing policy id and deed, jobs first, then reach rows.
func _missing_policies(data: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	_collect_missing(out, seen, data.get("jobs", []))
	_collect_missing(out, seen, data.get("reach", []))
	return out


func _collect_missing(out: Array, seen: Dictionary, raw: Variant) -> void:
	for item in _rows(raw):
		var deed_id := str(item.get("deed", ""))
		if deed_id.is_empty():
			continue
		var policy_id := str(item.get("policy", ""))
		if _has_policy(policy_id):
			continue
		var key := "%s\t%s" % [policy_id, deed_id]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"deed": deed_id, "policy": policy_id})
		push_error("WyrdRumor: %s" % missing_policy_message(policy_id, deed_id))


func _deed_of_pair(token: String) -> String:
	var cut := token.find("\t")
	if cut < 0:
		return token
	return token.substr(0, cut)


func _kind_list(raw: Variant) -> PackedStringArray:
	var kinds := PackedStringArray()
	for item in _list(raw):
		kinds.append(WyrdSave.text_of(item, ""))
	return kinds


func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if raw is PackedStringArray:
		for item in raw:
			out.append(String(item))
		return out
	for item in _list(raw):
		out.append(String(item))
	return out


func _sorted_keys(bag: Dictionary) -> Array:
	var keys: Array = []
	for key in bag.keys():
		keys.append(String(key))
	keys.sort()
	return keys


func _rows(raw: Variant) -> Array:
	var out: Array = []
	for item in _list(raw):
		if item is Dictionary:
			out.append(item)
	return out


func _list(raw: Variant) -> Array:
	if raw is Array:
		return raw
	return []


func _copy_mutations(items: Array) -> Array:
	var copied: Array = []
	for item in items:
		if item is Dictionary:
			copied.append((item as Dictionary).duplicate())
			continue
		push_error("WyrdRumor.register: a mutation must be a dictionary")
	return copied


func _speaker_copy(deed_id: String, speaker: String, original: Variant) -> Dictionary:
	var token := "%s\t%s" % [deed_id, speaker]
	if _gone.has(token):
		return {"present": false, "value": null}
	if _held.has(token):
		return {"present": true, "value": _held[token]}
	return {"present": true, "value": original}


func _note_believer(deed_id: String, who_text: String) -> void:
	if deeds == null or who_text.is_empty():
		return
	var id_num := int(deed_id)
	if id_num <= 0:
		return
	deeds.note_believer(id_num, StringName(who_text), _now())


func _mark_held(deed_id: String, who_text: String, value: Variant) -> void:
	var token := "%s\t%s" % [deed_id, who_text]
	_gone.erase(token)
	_held[token] = value


func _mark_gone(deed_id: String, who_text: String) -> void:
	var token := "%s\t%s" % [deed_id, who_text]
	_held.erase(token)
	_gone[token] = true


## Evaluates mutations whose field is [param fact]. Hop number for a precise
## hop is the hop. For a materialize it is the reach level, and the speaker is
## the place. A keep roll uses stream [code]rumor[/code].
func _apply_mutations(
	deed_id: String,
	from_who: String,
	to_who: String,
	hop_n: int,
	fact: String,
	policy_id: String,
	value: Variant,
	found: Variant
) -> Dictionary:
	var current: Variant = value
	var present := true
	var mutations := _mutation_list(found)
	for index in mutations.size():
		if not present:
			break
		var item: Variant = mutations[index]
		if not item is Dictionary:
			continue
		var spec: Dictionary = item
		var field := str(spec.get("field", ""))
		if field.is_empty() or field != fact:
			continue
		var chance := _keep_chance(spec.get("keep_chance_fn", null), current, hop_n)
		var kept := _mutate_kept(deed_id, from_who, to_who, hop_n, field, index, chance)
		var result := "keep"
		var shown: Variant = current
		if not kept:
			var change: Variant = spec.get("to", "drop")
			if _is_drop(change):
				present = false
				result = "drop"
				shown = null
			elif change is Callable and (change as Callable).is_valid():
				current = _call_fn(change, current, hop_n)
				result = "mutate"
				shown = current
			else:
				push_error("WyrdRumor: mutation to must be a callable or drop")
				result = "keep"
				shown = current
		_trace_mutate(deed_id, from_who, to_who, hop_n, field, policy_id, kept, result, shown)
	return {"present": present, "value": current}


func _mutation_list(found: Variant) -> Array:
	if found is Array:
		return found as Array
	return []


func _keep_chance(fn: Variant, value: Variant, hop_n: int) -> float:
	if not fn is Callable or not (fn as Callable).is_valid():
		push_error("WyrdRumor: mutation keep_chance_fn must be a callable")
		return 1.0
	var result: Variant = _call_fn(fn, value, hop_n)
	if not (result is float or typeof(result) == TYPE_INT) or is_nan(float(result)) or is_inf(float(result)):
		push_error("WyrdRumor: keep_chance_fn must return a number")
		return 1.0
	return clampf(float(result), 0.0, 1.0)


func _call_fn(fn: Variant, value: Variant, hop_n: int) -> Variant:
	var callable := fn as Callable
	var argc := callable.get_argument_count()
	if argc <= 0:
		return callable.call()
	if argc == 1:
		return callable.call(value)
	return callable.call(value, hop_n)


func _is_drop(change: Variant) -> bool:
	return (change is String or change is StringName) and String(change) == "drop"


func _mutate_kept(
	deed_id: String,
	from_who: String,
	to_who: String,
	hop_n: int,
	field: String,
	index: int,
	chance: float
) -> bool:
	# decision_unit is in [0, 1). A chance outside that range does not need a roll.
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	var key := StringName("mutate\t%s\t%s\t%s\t%d\t%s\t%d" % [deed_id, from_who, to_who, hop_n, field, index])
	return WyrdRng.decision_unit(_seed(), &"rumor", key, _time_bucket()) < chance


func _policy_for(verb: StringName) -> WyrdRumorPolicy:
	var text := String(verb)
	for policy in _policies:
		if policy.verbs.is_empty() or policy.verbs.has(text):
			return policy
	return null


func _origins(deed: Dictionary) -> PackedStringArray:
	var bag := {}
	var actor := String(deed.get("actor", ""))
	if not actor.is_empty():
		bag[actor] = true
	var witnesses: Variant = deed.get("witnesses", PackedStringArray())
	if witnesses is PackedStringArray:
		for person in witnesses as PackedStringArray:
			var text := String(person)
			if not text.is_empty():
				bag[text] = true
	elif witnesses is Array:
		for person in witnesses:
			var text := String(person)
			if not text.is_empty():
				bag[text] = true
	var names := PackedStringArray()
	for person in bag.keys():
		names.append(String(person))
	names.sort()
	return names


func _enqueue_from(deed_id: String, source: String, hop_n: int) -> void:
	if not enqueue_hop.is_valid() or not _jobs.has(deed_id) or social == null:
		return
	if not _queued.has(deed_id):
		_queued[deed_id] = {}
	var queued: Dictionary = _queued[deed_id]
	var seen: Dictionary = _seen[deed_id] if _seen.has(deed_id) else {}
	var job: Dictionary = _jobs[deed_id]
	var kinds: PackedStringArray = job["kinds"]
	var picked := {}
	var names := PackedStringArray()
	for kind in kinds:
		var kind_name := String(kind)
		if kind_name.is_empty():
			continue
		for target in social.targets(StringName(source), StringName(kind_name)):
			var person := String(target)
			if person.is_empty() or person == source or seen.has(person) or queued.has(person) or picked.has(person):
				continue
			picked[person] = true
			names.append(person)
	names.sort()
	for person in names:
		queued[person] = true
		enqueue_hop.call(_token(deed_id, source, person, hop_n))


func _note_reach(
	deed: Dictionary,
	policy: WyrdRumorPolicy,
	claim_key: String,
	claim_value: Variant,
	place: StringName,
	verb: StringName
) -> void:
	var deed_id := str(int(deed.get("id", 0)))
	if deed_id == "0":
		return
	var row_key := "%s\t%s" % [deed_id, String(place)]
	if _reach.has(row_key):
		return
	_reach[row_key] = {
		"born": _now(),
		"deed": deed_id,
		"key": claim_key,
		"level": 0,
		"pending": 0,
		"mutations": policy.mutations,
		"place": String(place),
		"policy": String(policy.id),
		"value": claim_value,
		"verb": String(verb),
	}
	_reach_changed(true)


func _apply_reach(deed_id: String, place: String, seq: int) -> void:
	if deed_id.is_empty() or place.is_empty():
		return
	var row_key := "%s\t%s" % [deed_id, place]
	if not _reach.has(row_key):
		return
	var row: Dictionary = _reach[row_key]
	if seq != int(row.get("level", 0)) + 1:
		return
	row["level"] = int(row.get("level", 0)) + 1
	row["pending"] = maxi(int(row.get("pending", 0)) - 1, 0)
	_trace_reach(row)


func _roll(deed_id: String, from_who: String, to_who: String, hop_n: int, chance: float) -> bool:
	# decision_unit is in [0, 1). A chance outside that range does not need a roll.
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	var key := StringName(_token(deed_id, from_who, to_who, hop_n))
	return WyrdRng.decision_unit(_seed(), &"rumor", key, _time_bucket()) < chance


func _seed() -> int:
	if seed_of.is_valid():
		return int(seed_of.call())
	return 0


func _now() -> int:
	if now_of.is_valid():
		return int(now_of.call())
	return 0


func _coarse_minutes() -> int:
	if not config_of.is_valid():
		return 60
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return int((cfg as WyrdConfig).rumor_coarse_minutes)
	return 60


func _coarse_index(minute: int, coarse: int) -> int:
	if coarse <= 0:
		return 0
	return int(floor(float(minute) / float(coarse)))


func _time_bucket() -> int:
	var now := _now()
	var size := 60
	if config_of.is_valid():
		var cfg: Variant = config_of.call()
		if cfg is WyrdConfig:
			size = maxi((cfg as WyrdConfig).hour_bucket_minutes, 0)
	if size <= 0:
		return now
	return int(floor(float(now) / float(size))) * size


func _score(listener: String, speaker: String) -> float:
	if not score_of.is_valid():
		return 0.0
	return float(score_of.call(StringName(listener), StringName(speaker)))


func _threshold() -> float:
	if not threshold_of.is_valid():
		return 0.5
	return float(threshold_of.call())


func _place_is_coarse(place: StringName) -> bool:
	if place == &"":
		return false
	var spatial := _spatial()
	if spatial == null:
		return false
	return String(spatial.precision(place)) == "coarse"


func _listener_is_coarse(who: StringName) -> bool:
	var spatial := _spatial()
	if spatial == null:
		return false
	var place := spatial.place_of(who)
	if place == &"":
		return false
	return String(spatial.precision(place)) == "coarse"


func _spatial() -> WyrdSpatialAdapter:
	if not spatial_of.is_valid():
		return null
	var found: Variant = spatial_of.call()
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _wants_trace() -> bool:
	if tracing_of.is_valid():
		return bool(tracing_of.call())
	return trace_of.is_valid()


func _trace_hop(
	deed_id: String,
	from_who: String,
	to_who: String,
	hop_n: int,
	key: String,
	policy_id: String,
	verb: String,
	taken: bool,
	reason: String
) -> void:
	if not _wants_trace():
		return
	trace_of.call("rumor_hop", {
		"deed": deed_id,
		"from": from_who,
		"hop": hop_n,
		"key": key,
		"path": policy_id,
		"reason": reason,
		"speaker": from_who,
		"taken": "true" if taken else "false",
		"to": to_who,
		"verb": verb,
		"who": to_who,
	})


func _trace_adopt(
	from_who: String,
	to_who: String,
	key: String,
	policy_id: String,
	verb: String,
	score: float,
	accepted: bool
) -> void:
	if not _wants_trace():
		return
	trace_of.call("rumor_adopt", {
		"accepted": "true" if accepted else "false",
		"key": key,
		"listener": to_who,
		"path": policy_id,
		"score": score,
		"speaker": from_who,
		"verb": verb,
		"who": to_who,
	})


func _trace_reach(row: Dictionary) -> void:
	if not _wants_trace():
		return
	var place := str(row.get("place", ""))
	trace_of.call("rumor_reach", {
		"deed": str(row.get("deed", "")),
		"key": str(row.get("key", "")),
		"level": int(row.get("level", 0)),
		"path": str(row.get("policy", "")),
		"place": place,
		"who": place,
	})


func _trace_mutate(
	deed_id: String,
	from_who: String,
	to_who: String,
	hop_n: int,
	field: String,
	policy_id: String,
	kept: bool,
	result: String,
	shown: Variant
) -> void:
	if not _wants_trace():
		return
	trace_of.call("rumor_mutate", {
		"deed": deed_id,
		"field": field,
		"hop": hop_n,
		"kept": "true" if kept else "false",
		"key": field,
		"listener": to_who,
		"path": policy_id,
		"result": result,
		"speaker": from_who,
		"value": "" if shown == null else str(shown),
		"who": to_who,
	})


func _trace_materialize(
	who_text: String,
	place_text: String,
	policy_id: String,
	fact: String,
	deed_id: String,
	level: int,
	chance: float,
	accepted: bool
) -> void:
	if not _wants_trace():
		return
	trace_of.call("rumor_materialize", {
		"accepted": "true" if accepted else "false",
		"chance": chance,
		"deed": deed_id,
		"key": fact,
		"level": level,
		"listener": who_text,
		"path": policy_id,
		"place": place_text,
		"who": who_text,
	})


static func _token(deed_id: String, from_who: String, to_who: String, hop_n: int) -> String:
	return "%s\t%s\t%s\t%d" % [deed_id, from_who, to_who, hop_n]
