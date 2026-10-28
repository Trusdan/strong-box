class_name WyrdTrace
extends RefCounted

## Debug record of host answers and Wyrd decisions.
##
## @experimental
## Turn [member enabled] on before play. [method replay] drives the recorded
## inputs ([code]open_scene[/code], [code]advance[/code], [code]choose[/code],
## [code]abort[/code], [code]tick[/code], [code]emit[/code],
## [code]complete_host[/code], [code]draw[/code], [code]batch_begin[/code],
## [code]batch_end[/code], [code]emit_rejected[/code], [code]open_document[/code],
## [code]create_copy[/code], [code]ai_deliver[/code], [code]quest_summary[/code],
## [code]ai_host_request[/code], [code]host_call[/code]) on another runtime. Host
## answers and decisions are compared with [method diff]. A different host
## answer shows up there.

var enabled: bool = false
## When set, a line is kept when its quest, role, slot, who, key, scope,
## speaker, path, or instance equals this text or begins with it. Empty keeps every line.
## Belief, knowledge, credibility, event witness, and evidence lines use who and key.
## A credibility line's who is the listener. An evidence line's who is empty.
## A director line and a why_not line use scope, speaker, and key. Key is the scope id.
## A director_candidate line uses the same fields. Its path is the storylet id.
## A region line uses quest and path. A quest_start, quest_advance, or quest_status
## line uses quest. Replay skips them. Load does not log them.
## A role_assign or role_vacate line uses role. A baseline_adjust line uses who,
## which is a. Replay skips them. Load does not log them.
## A sequence line's key is the sequence id.
## A voice line's key is the name-free line id, and its who is the holder.
## A secrecy line's key is the storylet id, or the line id when there is no storylet.
## Its path is the line id. The prefix matches either.
## A debug_snapshot line is one inspector read. key is the caller prefix.
## path is the section list, or * when every section was requested.
## The prefix matches key or path. Load does not log one. Replay skips it.
## A choice_summary line is one provenance read. key is the key prefix.
## path is the scene filter. A choice_compact line is one provenance drop.
## Its path is the dropped keys, joined by commas. Replay skips both.
## A coverage line is one recorded hit. hit is storylet, line, or variant.
## key is the id. path is the source file.
## A coverage_report line is one never-hit read. Replay skips both.
## A console line is one playtest command. path is console. key is the target.
## role is set for kill, vacate, and replace. source is console.
## Replay skips it. Load does not log one.
## A deed_index line is one snapshot read of the witness or time-bucket index.
## scope is deeds, social, or precedence. key is the caller prefix.
## ids is the deed-row count, or the agent-name count for precedence.
## Replay skips it. Load does not log one. Lookup off does not log one.
## A gen_create line is one generated instance. template is the template id.
## instance is [code]<template>#<n>[/code], or empty when creation was refused.
## n is the new counter, or 0 when nothing was created. ok is true or false.
## reason is created, unknown_template, bad_cast, or bad_param. Replay skips it.
## Load does not log one.
## A gen_offer line is one queued or replaced story-pressure offer.
## source is host or deed. key is the offer key. tier may be empty.
## origin is host or deed. template is empty for a host offer.
## queued is the queue length after the change. replaced is true or false.
## The record also stores payload. The printed line does not.
## The prefix matches key or template. A host-origin row is a replay input and
## calls [method WyrdGenerator.offer]. A deed-origin row is skipped, because the
## replayed deed queues it again. Load does not log one.
## An ai_provider line is one provider registration or one enabled change.
## id is the provider id. state is on when the hook is enabled and the provider
## is not the null provider. An ai_request line is one request call.
## id is the request id, or 0 when it was refused. path is the line id.
## state is sent or refused. reason is -, kind, off, or null.
## An ai_result line is one deliver call. ok is true or false.
## rule is -, late, unknown_request, or thread. An ai_cancel line is one pending
## request removed without a delivery. reason is host, provider, off, new_game,
## load, scene_end, superseded, or expired. The printed kind is stored as slot_kind.
## An ai_deliver row is a replay input: it calls [method WyrdAI.deliver].
## It is recorded and not printed. A provider that answers inside [code]request[/code]
## records that row during the input that sent it, so replay delivers it only
## after that input returns. Lines shown during that input can then differ.
## A provider that answers on a later frame replays the same text.
## A [code]quest_summary[/code] row calls [method WyrdQuestRunner.summary].
## An [code]ai_host_request[/code] row calls [method WyrdAI.request]. The request
## kind is stored as [code]slot_kind[/code], because [code]kind[/code] is the event name.
## With those rows a replay sends the same requests with the same ids, so each
## recorded [code]ai_deliver[/code] answers the right request.
## ai_prefetch, ai_use, ai_late, and ai_sweep are skipped, like the other ai rows.
## An ai_sweep line is one bark sweep armed or dropped. op is arm or drop.
## reason is start, change, floor, off, provider, new_game, or load.
## Load does not log them. The prefix matches path.
## A gen_tier line is one eligibility pass. eligible is the template count.
## A gen_pick line is one weighted pick. score is [code]<priority>/<specificity>[/code].
## band is the top-band size. seed_key is the decision key. template is empty and
## reason is no_template when nothing is eligible. Replay skips both. Load does not log them.
## A gen_candidates line is one host candidate list, sorted, before the cast condition.
## count is that list. digest is the [WyrdHash] of those ids. key is the decision key.
## A gen_cast line is one cast slot on a proposal. A gen_bind line is one param.
## Replay skips them. The accept that follows logs the existing cast and gen_create lines.
## A gen_propose line is one host proposal. ok is true or false. reason is proposed,
## no_template, no_candidate, or rejected. The record also stores tier and payload. The printed
## line does not. Replay calls [method WyrdGenerator.propose]. Load does not log one.
## A background generate unit does not log gen_propose.
## A gen_reject line is one validator failure. rule is exists, place, protected,
## bounds, assumes, or known. attempt is 0 on the first try. Replay skips it;
## propose regenerates it. Load does not log one.
## A gen_cap line is one template [code]max_active[/code] excluded. Replay skips it.
## A gen_expire line is one generated instance abandoned because [code]expires:[/code]
## elapsed. reason is timeout. Replay skips it; the replayed tick regenerates it.
## A gen_accept line is one accept. reason is created, refused, stale, accepted, or
## unknown. instance is the id, or empty. Replay calls [method WyrdGenerator.accept].
## Load does not log one. The other gen lines are regenerated by propose or accept
## and compared by [method diff]. The prefix matches key, instance, or template.
## An object or item cast stores the slot kind as [code]slot_kind[/code].
## The printed line labels that field [code]kind[/code]. [code]kind[/code] on the
## record stays the event name ([code]cast[/code] or [code]slot_state[/code]).
## An item cast also stores [code]owner[/code] when it was recorded.
## A social_cache line is one cache invalidation, miss, or hit.
## event is invalidate, miss, or hit. cache is axis, disposition, reputation, path,
## or the invalidation reason, and the printed line labels it kind.
## who is the source or subject. key is the other
## party, or the reason on an invalidation. path is the axis name or kind list.
## bucket is the time bucket. entries is how many entries were dropped.
## Reads and hits log only when tracing is on. Replay skips the line. Load does not log one.
## A scheduler line is one queue's units for a game tick, or one enqueued item.
## key and queue are waits, rumor, publish, cache_refresh, generate, or frame.
## units is the work done. carry is the unfinished count. A frame line is the
## debug soft warning: us is the measured time and threshold is the config.
## The default threshold is 2000 microseconds (2 ms). 0 disables the line.
## The warning does not change the work. It sets timing true, because us and
## the row's presence depend on wall-clock time. [method diff] leaves out every
## row with timing true and compares every other row exactly. The row stays in
## the trace. Replay skips the line. It is not saved.
## A rumor_hop line is one precise hop: deed, speaker, listener, and hop.
## path is the policy id. who is the listener. key is the fact.
## taken is true when the seeded roll offers the hop. reason is pass, chance, or coarse.
## A rumor_adopt line is that offer's credibility check. accepted is true when
## believed/<listener> was written. Replay skips both. Load does not log them.
## A rumor_reach line is one coarse rise: deed, place, policy, level, and fact.
## who is the place. path is the policy id. A rumor_materialize line is one
## seeded draw for an NPC in that place. who is the listener. path is the policy
## id. accepted is true when believed/<listener> was written. Replay skips both.
## Load does not log them.
## A rumor_mutate line is one field of an accepted hop or materialize.
## who is the listener. path is the policy id. key is the field.
## kept is true when the seeded roll retains the value. result is keep, mutate,
## or drop. Replay skips it. Load does not log it.
## A publish line is one frozen issue. path is the document id.
## key and issue are the copy id. who is the group. deeds is the deed count.
## Replay skips it. Load does not log it.
## A text_translate line is one rendered line that used or rejected a translated
## template. key is the line id. path is the locale. ok is true when the
## translation was used. reason is translated, placeholder_mismatch,
## compile_error, or frozen_shape. Replay skips it. Load does not log one.
## A storylet_index line is one index read. scope is the scope text.
## speaker is the query speaker. key is the scope id, empty for a bark.
## ids is the count returned before secrecy, when, and cooldown.
## Replay skips it. Load does not log one. A null index does not log one.
var prefix: String = ""
var events: Array[Dictionary] = []


func clear() -> void:
	events.clear()


func add(kind: String, fields: Dictionary) -> void:
	if not enabled:
		return
	# kind is the event name and stays first, matching every existing record.
	# A field also named kind is the slot kind. It is stored as slot_kind.
	var row := {"kind": kind}
	var keys: Array = fields.keys()
	keys.sort()
	var slot_kind := ""
	var has_slot_kind := false
	for key in keys:
		var name := String(key)
		if name == "kind":
			slot_kind = str(_plain(fields[key]))
			has_slot_kind = true
			continue
		row[name] = _plain(fields[key])
	if has_slot_kind:
		row["slot_kind"] = slot_kind
	events.append(row)


func snapshot() -> Array:
	return events.duplicate(true)


static func replay(runtime: WyrdRuntime, recorded: Array) -> void:
	for item in recorded:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		match String(row.get("kind", "")):
			"abort":
				runtime.dialogue.abort(StringName(str(row.get("reason", ""))))
			"batch_begin":
				runtime.events.begin_batch()
			"batch_end":
				runtime.events.end_batch()
			"advance":
				runtime.dialogue.advance()
			"choose":
				runtime.dialogue.choose(int(row.get("index", -1)))
			"complete_host":
				runtime.quests.complete_host_step(String(row.get("quest", "")), _dict(row.get("values", {})))
			"draw":
				runtime.draw_u32(StringName(str(row.get("stream", ""))))
			"emit", "emit_rejected":
				runtime.events.emit(StringName(str(row.get("name", ""))), _dict(row.get("payload", {})))
			"open_scene":
				runtime.dialogue.open_scene(String(row.get("id", "")))
			"tick":
				runtime.tick(float(row.get("minutes", 0)))
			"ask_topic":
				runtime.dialogue.ask_topic(str(row.get("npc", "")), str(row.get("topic", "")))
			"open_topic":
				runtime.dialogue.open(str(row.get("npc", "")))
			"open_document":
				if runtime.documents != null:
					runtime.documents.open(StringName(str(row.get("doc", ""))), str(row.get("copy", "")), StringName(str(row.get("reader", ""))))
			"create_copy":
				if runtime.documents != null:
					runtime.documents.create_copy(StringName(str(row.get("doc", ""))), str(row.get("copy", "")))
			"gen_offer":
				if str(row.get("origin", "")) == "host" and runtime.generator != null:
					runtime.generator.offer(StringName(str(row.get("source", ""))), str(row.get("key", "")), StringName(str(row.get("tier", ""))), _dict(row.get("payload", {})))
			"gen_propose":
				if runtime.generator != null:
					runtime.generator.propose({
						"key": str(row.get("key", "")),
						"payload": _dict(row.get("payload", {})),
						"source": str(row.get("source", "")),
						"tier": str(row.get("tier", "")),
					})
			"gen_accept":
				if str(row.get("origin", "")) != "queue" and runtime.generator != null:
					runtime.generator.accept(runtime.generator.proposal(str(row.get("proposal", ""))))
			"ai_deliver":
				if runtime.ai != null:
					var delivered := WyrdAIResult.new()
					delivered.ok = bool(row.get("ok", false))
					delivered.text = str(row.get("text", ""))
					delivered.error = str(row.get("error", ""))
					runtime.ai.deliver(int(row.get("id", 0)), delivered)
			"quest_summary":
				if runtime.quests != null:
					runtime.quests.summary(str(row.get("quest", "")))
			"ai_host_request":
				if runtime.ai != null:
					runtime.ai.request(StringName(str(row.get("slot_kind", ""))), _dict(row.get("packet", {})), _dict(row.get("constraints", {})), StringName(str(row.get("path", ""))))
			"host_call":
				_replay_host(runtime, row)
			"ai_provider", "ai_request", "ai_result", "ai_cancel", "ai_prefetch", "ai_use", "ai_late", "ai_sweep", "console", "storylet_index", "deed_index", "scheduler", "social_cache", "rumor_hop", "rumor_adopt", "rumor_reach", "rumor_materialize", "rumor_mutate", "publish", "quest_start", "quest_advance", "quest_status", "role_assign", "role_vacate", "baseline_adjust", "topic_unlock", "topic_lock", "topic_ask", "topic_open", "effect_run", "skill_check", "document_open", "document_copy", "document_stale", "text_translate":
				pass
			_:
				pass


static func diff(expected: Array, actual: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	var left := 0
	var right := 0
	var left_kept := 0
	var right_kept := 0
	while left < expected.size() and right < actual.size():
		while left < expected.size() and _timing_only(expected[left]):
			left += 1
		while right < actual.size() and _timing_only(actual[right]):
			right += 1
		if left >= expected.size() or right >= actual.size():
			break
		left_kept += 1
		right_kept += 1
		if JSON.stringify(expected[left]) != JSON.stringify(actual[right]):
			var kind := ""
			if expected[left] is Dictionary:
				kind = String((expected[left] as Dictionary).get("kind", ""))
			rows.append("%d %s" % [left, kind])
			if rows.size() >= 8:
				return rows
		left += 1
		right += 1
	while left < expected.size():
		if not _timing_only(expected[left]):
			left_kept += 1
		left += 1
	while right < actual.size():
		if not _timing_only(actual[right]):
			right_kept += 1
		right += 1
	if left_kept != right_kept:
		rows.append("length %d/%d" % [left_kept, right_kept])
	return rows


## A timing row is a wall-clock diagnostic. Its presence and measured fields
## are not part of replay equivalence. Decisions and every other row are.
static func _timing_only(row: Variant) -> bool:
	return row is Dictionary and bool((row as Dictionary).get("timing", false))


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _replay_host(runtime: WyrdRuntime, row: Dictionary) -> void:
	var call := str(row.get("call", ""))
	var dot := call.find(".")
	if dot <= 0:
		return
	var target: Object = null
	match call.substr(0, dot):
		"facts":
			target = runtime.facts
		"deeds":
			target = runtime.deeds
		"social":
			target = runtime.social
		"roles":
			target = runtime.roles
		"topics":
			target = runtime.topics
		"quests":
			target = runtime.quests
		"director":
			target = runtime.director
		"ai":
			target = runtime.ai
		_:
			return
	var method := call.substr(dot + 1)
	if target == null or method.is_empty() or not target.has_method(method):
		return
	var raw: Variant = row.get("args", [])
	var args: Array = raw if raw is Array else []
	target.callv(method, _coerce_args(target, method, args))


static func _coerce_args(target: Object, method: String, args: Array) -> Array:
	var spec: Array = []
	for entry in target.get_method_list():
		if String(entry.get("name", "")) != method:
			continue
		var found: Variant = entry.get("args", [])
		if found is Array:
			spec = found
		break
	var out: Array = []
	for i in args.size():
		var typ := TYPE_NIL
		if i < spec.size() and spec[i] is Dictionary:
			typ = int((spec[i] as Dictionary).get("type", TYPE_NIL))
		out.append(_coerce_arg(args[i], typ))
	if method == "set_in" and target is WyrdFactStore and out.size() >= 2:
		out[1] = (target as WyrdFactStore)._saved_value(String(out[0]), out[1])
	return out


static func _coerce_arg(value: Variant, typ: int) -> Variant:
	match typ:
		TYPE_STRING_NAME:
			return StringName(str(value)) if value != null else StringName()
		TYPE_PACKED_STRING_ARRAY:
			var packed := PackedStringArray()
			if value is Array or value is PackedStringArray:
				for item in value:
					packed.append(str(item))
			return packed
		TYPE_INT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				return int(value)
			return value
		TYPE_FLOAT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				return float(value)
			return value
		TYPE_STRING:
			return "" if value == null else str(value)
		TYPE_DICTIONARY:
			return value if value is Dictionary else {}
		_:
			return value


static func _plain(value: Variant) -> Variant:
	if value == null or value is bool or typeof(value) == TYPE_INT or value is float or value is String:
		return value
	if value is StringName:
		return String(value)
	if value is PackedStringArray:
		var packed: Array = []
		for item in value:
			packed.append(String(item))
		return packed
	if value is Array:
		var rows: Array = []
		for item in value:
			rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			out[String(key)] = _plain(value[key])
		return out
	return str(value)
