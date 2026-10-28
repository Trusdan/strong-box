class_name WyrdDirector
extends RefCounted

## Picks one storylet for a scope and speaker.
##
## @experimental
## [code]speaker: any[/code] is a wildcard. A specific query speaker matches
## that speaker and [code]any[/code]. An empty query speaker, or [code]any[/code],
## matches every storylet in the scope. [code]Any[/code] is not the wildcard.
## Exact speaker is a filter, not a rank key.
##
## Filters are scope, speaker, secrecy, [code]when[/code], then cooldown.
## A storylet whose secrecy name sits above the unlocked tier is dropped
## before ranking. An empty secrecy name stays visible. Each dropped
## candidate logs one [code]secrecy[/code] line when tracing is on.
## Cooldown is
## hard: a storylet is eligible when it has never been selected, its cooldown
## is 0, or the minutes since [code]last_minute[/code] are at least
## [member WyrdStoryletDef.cooldown_minutes]. If every match is cooling, the
## query has no winner.
##
## A bark also consults [member WyrdStoryletDef.speaker_cooldown_minutes].
## The clock key is the query speaker when that name is concrete, otherwise
## the storylet speaker when that name is concrete. [code]any[/code] and an
## empty name are not concrete and do not start a clock. Topic, event, and
## beat queries ignore it. A win with a positive cooldown stores that
## duration for the key. A candidate is cooling while [code]now - last[/code]
## is still below the stored duration.
##
## Ranking, highest first: priority, specificity, weight, then fewer times
## seen, then the older [code]last_minute[/code]. Never selected sorts as
## older than any selection. Generics stay in this pool at specificity 0.
## A higher priority beats a more specific storylet.
##
## Remaining ties are sorted by id. [method WyrdRng.for_decision] on
## [constant STREAM] breaks them. The decision key is the scope text and the
## query speaker. The time bucket is the current game minute. A bark query
## ignores [code]scope_id[/code] for both the match and that key. A unique
## winner does not roll.
##
## A win records the selection, then draws the body. [method WyrdStoryletDeck.draw]
## alone does not record one. Candidates in the trace are the count after the
## filters. When [member WyrdConfig.trace_director] is true and tracing is on,
## each scope-and-speaker match logs one [code]director_candidate[/code] line
## before that summary. The line carries the score and the first failing clause.
##
## The id list comes from the link-time storylet index: one sorted list per
## scope kind, scope id, and speaker, plus the [code]any[/code] speaker bucket.
## A bark query still runs inside this call. A null index scans every storylet.

const STREAM: StringName = &"storylet_director"
const WILDCARD := "any"

var _runtime: WyrdRuntime


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime


func query(scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary:
	var _host_gate: Variant = _runtime._host_enter() if _runtime != null else null
	if _runtime != null and _runtime._host_logs():
		_runtime._host_mark("director.query", [scope_kind, scope_id, speaker])
	var kind := StringName(scope_kind)
	var scope_text := _scope_text(kind, scope_id)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		push_error("Wyrd.director.query: load content before a storylet query")
		return _finish(scope_text, speaker, [], null, {}, 0)
	if not _known_scope(kind):
		push_error("Wyrd.director.query: unknown scope \"%s\"" % scope_kind)
		return _finish(scope_text, speaker, [], null, {}, 0)
	if _wants_candidate_trace():
		candidate_rows(scope_kind, scope_id, speaker)
	var matched := _eligible(kind, scope_id, speaker)
	return _commit(kind, scope_text, speaker, matched, true)


## Ranks storylets whose speaker is [param entity], a role that entity holds, or [code]any[/code].
## One pool, the same rank and tie-break as [method query]. The decision key uses [param entity].
## Does not log [code]director_candidate[/code] lines and does not present a bark.
func query_for_entity(scope_kind: String, scope_id: String, entity: String) -> Dictionary:
	var kind := StringName(scope_kind)
	var scope_text := _scope_text(kind, scope_id)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		push_error("Wyrd.director.query_for_entity: load content before a storylet query")
		return _finish(scope_text, entity, [], null, {}, 0)
	if not _known_scope(kind):
		push_error("Wyrd.director.query_for_entity: unknown scope \"%s\"" % scope_kind)
		return _finish(scope_text, entity, [], null, {}, 0)
	var matched := eligible_for_entity(kind, scope_id, entity)
	return _commit(kind, scope_text, entity, matched, false)


## Eligible storylets for [param entity]. Does not record a selection or draw a body.
func eligible_for_entity(scope_kind: StringName, scope_id: String, entity: String) -> Array:
	return _eligible_entity(scope_kind, scope_id, entity)


## True when the storylet [code]when[/code] holds. Does not check cooldowns,
## draw a body, record a selection, or write state.
func when_holds(story: WyrdStoryletDef) -> bool:
	if story == null or _runtime == null:
		return false
	return _when_passes(story)


func _commit(kind: StringName, scope_text: String, speaker: String, matched: Array, present: bool) -> Dictionary:
	var winner: WyrdStoryletDef = _pick(matched, scope_text, speaker)
	var drawn := {}
	var seen_before := 0
	if winner != null:
		seen_before = _runtime.storylets.seen_of(winner.id)
		var minute := _runtime.now_minutes()
		_runtime.storylets.note_selected(winner.id, minute)
		_note_speaker(winner, speaker, minute)
		drawn = _runtime.storylets.draw(winner.id, _allow_for(winner))
		_run_storylet_effects(winner)
		if present and kind == &"bark":
			_runtime.present_bark(winner, drawn)
	return _finish(scope_text, speaker, matched, winner, drawn, seen_before)


func _run_storylet_effects(winner: WyrdStoryletDef) -> void:
	if winner == null or winner.effects.is_empty() or _runtime == null or _runtime.effects == null:
		return
	var saved_scene := _runtime.effects.scene_id
	var saved_choice := _runtime.effects.choice_id
	_runtime.effects.scene_id = "storylet:%s" % winner.id
	_runtime.effects.choice_id = ""
	for effect in winner.effects:
		_runtime.trace_effect_run("storylet", winner.id, String(effect.kind))
		var divert := _runtime.effects.run_one(effect)
		if divert != "":
			break
	_runtime.effects.scene_id = saved_scene
	_runtime.effects.choice_id = saved_choice


func _finish(
	scope_text: String,
	speaker: String,
	matched: Array,
	winner: WyrdStoryletDef,
	drawn: Dictionary,
	seen_before: int
) -> Dictionary:
	var score := "-"
	var priority := 0
	var specificity := 0
	var weight := 0
	var winner_id := ""
	var body := ""
	var line_id := ""
	var scene := ""
	if winner != null:
		priority = winner.priority
		specificity = winner.specificity
		weight = winner.weight
		winner_id = winner.id
		body = String(winner.body_kind)
		score = "%d/%d/%d/%d" % [priority, specificity, weight, seen_before]
		line_id = str(drawn.get("line_id", ""))
		scene = str(drawn.get("scene", winner.scene_id))
	var row := {
		"body": body,
		"candidates": matched.size(),
		"id": winner_id,
		"line_id": line_id,
		"priority": priority,
		"scene": scene,
		"score": score,
		"seen": seen_before,
		"specificity": specificity,
		"weight": weight,
	}
	if _runtime != null:
		_runtime.trace_director({
			"candidates": matched.size(),
			"key": _scope_id_of(scope_text),
			"scope": scope_text,
			"score": score,
			"speaker": speaker,
			"winner": winner_id,
		})
	return row


## Explains one storylet for a query. Does not record a selection.
func why_not(storylet_id: String, scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary:
	var kind := StringName(scope_kind)
	var scope_text := _scope_text(kind, scope_id)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		push_error("Wyrd.director.why_not: load content before a storylet query")
		return _finish_why(storylet_id, scope_text, speaker, false, "missing", "", "-", 0, 0, "")
	var found: Variant = _runtime.content().storylets.get(storylet_id, null)
	if not (found is WyrdStoryletDef):
		push_error("Wyrd.director.why_not: unknown storylet \"%s\"" % storylet_id)
		return _finish_why(storylet_id, scope_text, speaker, false, "missing", "", "-", 0, 0, "")
	var story: WyrdStoryletDef = found
	var score := "%d/%d/%d/%d" % [story.priority, story.specificity, story.weight, _runtime.storylets.seen_of(story.id)]
	var remaining := _remaining(story)
	if not _known_scope(kind):
		push_error("Wyrd.director.why_not: unknown scope \"%s\"" % scope_kind)
		return _finish_why(storylet_id, scope_text, speaker, false, "scope", "", score, story.cooldown_minutes, remaining, "")
	if _wants_candidate_trace():
		candidate_rows(scope_kind, scope_id, speaker)
	if not _scope_matches(story, kind, scope_id):
		return _finish_why(storylet_id, scope_text, speaker, false, "scope", "", score, story.cooldown_minutes, remaining, "")
	if not _speaker_matches(story.speaker, speaker):
		return _finish_why(storylet_id, scope_text, speaker, false, "speaker", "", score, story.cooldown_minutes, remaining, "")
	if _blocked(story):
		return _finish_why(storylet_id, scope_text, speaker, false, "secrecy", "", score, story.cooldown_minutes, remaining, "")
	var clause := _failing_clause(story)
	if not clause.is_empty():
		return _finish_why(storylet_id, scope_text, speaker, false, "when", clause, score, story.cooldown_minutes, remaining, "")
	if _cooling(story):
		return _finish_why(storylet_id, scope_text, speaker, false, "cooldown", "", score, story.cooldown_minutes, remaining, "")
	if _speaker_cooling(story, speaker):
		var key := _speaker_key(story, speaker)
		var stored := _runtime.storylets.speaker_cooldown_of(key)
		var left := _runtime.storylets.speaker_remaining(key, _runtime.now_minutes())
		return _finish_why(storylet_id, scope_text, speaker, false, "cooldown", "", score, stored, left, "")
	var matched := _eligible(kind, scope_id, speaker)
	var winner: WyrdStoryletDef = _pick(matched, scope_text, speaker)
	var winner_id := "" if winner == null else winner.id
	if winner_id == story.id:
		return _finish_why(storylet_id, scope_text, speaker, true, "ok", "", score, story.cooldown_minutes, remaining, winner_id)
	return _finish_why(storylet_id, scope_text, speaker, false, "outranked", "", score, story.cooldown_minutes, remaining, winner_id)


static func format_why_not(row: Dictionary) -> String:
	var clause := str(row.get("clause", ""))
	if clause.is_empty():
		clause = "-"
	var spoken := str(row.get("speaker", ""))
	if spoken.is_empty():
		spoken = "-"
	var winner := str(row.get("winner", ""))
	if winner.is_empty():
		winner = "-"
	var eligible := "true" if bool(row.get("eligible", false)) else "false"
	return "wyrd why_not storylet=%s scope=%s speaker=%s eligible=%s reason=%s clause=\"%s\" score=%s cooldown=%s remaining=%s winner=%s tier=%s unlocked=%s" % [
		str(row.get("storylet", "")),
		str(row.get("scope", "")),
		spoken,
		eligible,
		str(row.get("reason", "")),
		clause,
		str(row.get("score", "-")),
		str(row.get("cooldown", 0)),
		str(row.get("remaining", 0)),
		winner,
		_dash(row, "tier"),
		_dash(row, "unlocked"),
	]


## Scope-and-speaker matches, sorted by id. Does not record a selection or roll.
## Each row is traced when [member WyrdConfig.trace_director] and tracing are on.
func candidate_rows(scope_kind: String, scope_id: String = "", speaker: String = "") -> Array:
	var rows: Array = []
	var kind := StringName(scope_kind)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		return rows
	if not _known_scope(kind):
		return rows
	var scope_text := _scope_text(kind, scope_id)
	var ids := _story_ids(kind, scope_id, speaker)
	for raw_id in ids:
		var id := String(raw_id)
		var found: Variant = _runtime.content().storylets.get(id, null)
		if not (found is WyrdStoryletDef):
			continue
		var story: WyrdStoryletDef = found
		if not _scope_matches(story, kind, scope_id):
			continue
		if not _speaker_matches(story.speaker, speaker):
			continue
		var diagnosed := _diagnose(story, speaker)
		var row := {
			"clause": str(diagnosed["clause"]),
			"eligible": str(diagnosed["eligible"]),
			"key": _scope_id_of(scope_text),
			"path": story.id,
			"scope": scope_text,
			"score": str(diagnosed["score"]),
			"speaker": speaker,
			"storylet": story.id,
		}
		rows.append(row)
		_runtime.trace_director_candidate(row)
	return rows


## First failing filter for one storylet. Does not record a selection or roll.
## [code]block[/code] is empty when the storylet passes secrecy, [code]when[/code],
## and cooldown for this speaker. Scope and speaker failures use those names.
func diagnose(storylet_id: String, scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary:
	var empty := {"block": "missing", "clause": "-", "eligible": "false", "score": "-", "seen": 0}
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		return empty
	var found: Variant = _runtime.content().storylets.get(storylet_id, null)
	if not (found is WyrdStoryletDef):
		return empty
	var story: WyrdStoryletDef = found
	var kind := StringName(scope_kind)
	if not _known_scope(kind) or not _scope_matches(story, kind, scope_id):
		empty["block"] = "scope"
		empty["score"] = _score_text(story)
		empty["seen"] = _runtime.storylets.seen_of(story.id)
		return empty
	if not _speaker_matches(story.speaker, speaker):
		empty["block"] = "speaker"
		empty["score"] = _score_text(story)
		empty["seen"] = _runtime.storylets.seen_of(story.id)
		return empty
	var diagnosed := _diagnose(story, speaker)
	diagnosed["seen"] = _runtime.storylets.seen_of(story.id)
	return diagnosed


func speaker_matches(story_speaker: String, query_speaker: String) -> bool:
	return _speaker_matches(story_speaker, query_speaker)


static func format_candidate(row: Dictionary) -> String:
	var spoken := str(row.get("speaker", ""))
	if spoken.is_empty():
		spoken = "-"
	var clause := str(row.get("clause", "-")).replace("\"", "'")
	if clause.is_empty():
		clause = "-"
	return "wyrd director_candidate scope=%s speaker=%s storylet=%s score=%s eligible=%s clause=\"%s\"" % [
		str(row.get("scope", "")),
		spoken,
		str(row.get("storylet", "")),
		str(row.get("score", "-")),
		str(row.get("eligible", "false")),
		clause,
	]


func _wants_candidate_trace() -> bool:
	return (
		_runtime != null
		and _runtime.config() != null
		and _runtime.config().trace_director
		and _runtime.trace != null
		and _runtime.trace.enabled
	)


func _diagnose(story: WyrdStoryletDef, speaker: String) -> Dictionary:
	var block := ""
	var clause := ""
	if _blocked(story):
		block = "secrecy"
		clause = _secrecy_clause(story)
	else:
		clause = _failing_clause(story)
		if not clause.is_empty():
			block = "when"
		elif _cooling(story):
			block = "cooldown"
			clause = "cooldown"
		elif _speaker_cooling(story, speaker):
			block = "cooldown"
			clause = "speaker_cooldown"
	if block.is_empty():
		clause = "-"
	elif clause.is_empty():
		clause = block
	return {
		"block": block,
		"clause": clause,
		"eligible": "true" if block.is_empty() else "false",
		"score": _score_text(story),
	}


func _score_text(story: WyrdStoryletDef) -> String:
	var seen := 0
	if _runtime != null and _runtime.storylets != null:
		seen = _runtime.storylets.seen_of(story.id)
	return "%d/%d/%d/%d" % [story.priority, story.specificity, story.weight, seen]


func _secrecy_clause(story: WyrdStoryletDef) -> String:
	var tier := story.secrecy
	if tier.is_empty():
		for line in story.lines:
			var name := _line_tier(story, line)
			if not name.is_empty() and not _runtime.secrecy_allows(name):
				tier = name
				break
	if tier.is_empty():
		return "secrecy"
	return "secrecy:%s" % tier


func _finish_why(
	storylet_id: String,
	scope_text: String,
	speaker: String,
	eligible: bool,
	reason: String,
	clause: String,
	score: String,
	cooldown: int,
	remaining: int,
	winner: String
) -> Dictionary:
	var row := {
		"clause": clause,
		"cooldown": cooldown,
		"eligible": eligible,
		"key": _scope_id_of(scope_text),
		"reason": reason,
		"remaining": remaining,
		"scope": scope_text,
		"score": score,
		"speaker": speaker,
		"storylet": storylet_id,
		"tier": _tier_text(storylet_id),
		"unlocked": _unlocked_text(),
		"winner": winner,
	}
	if _runtime != null:
		_runtime.trace_why_not(row)
	return row


func _eligible_entity(kind: StringName, scope_id: String, entity: String) -> Array:
	var matched: Array = []
	if _runtime == null or _runtime.content() == null:
		return matched
	var ids := _entity_ids(kind, scope_id, entity)
	for raw_id in ids:
		var id := String(raw_id)
		var found: Variant = _runtime.content().storylets.get(id, null)
		if not (found is WyrdStoryletDef):
			continue
		var story: WyrdStoryletDef = found
		if not _scope_matches(story, kind, scope_id):
			continue
		if not _entity_speaker(story, entity):
			continue
		if _blocked(story):
			_trace_blocked(story)
			continue
		if not _when_passes(story):
			continue
		if _cooling(story):
			continue
		if _speaker_cooling(story, entity):
			continue
		matched.append(story)
	return matched


func _entity_ids(kind: StringName, scope_id: String, entity: String) -> PackedStringArray:
	var index: WyrdStoryletIndex = null
	if _runtime != null and _runtime.content() != null:
		index = _runtime.content().storylet_index
	if index == null:
		return _scan_ids()
	var seen := {}
	var ids := PackedStringArray()
	var speakers: Array = [entity]
	if _runtime.roles != null and not entity.is_empty():
		for role_id in _runtime.roles.roles_of(StringName(entity)):
			speakers.append(String(role_id))
	for speaker in speakers:
		for raw_id in index.ids_for(kind, scope_id, String(speaker)):
			var id := String(raw_id)
			if seen.has(id):
				continue
			seen[id] = true
			ids.append(id)
	return ids


func _entity_speaker(story: WyrdStoryletDef, entity: String) -> bool:
	if story.speaker == WILDCARD or story.speaker == entity:
		return true
	if entity.is_empty() or _runtime == null or _runtime.roles == null:
		return false
	return _runtime.roles.roles_of(StringName(entity)).has(story.speaker)


func _eligible(kind: StringName, scope_id: String, speaker: String) -> Array:
	var matched: Array = []
	if _runtime == null or _runtime.content() == null:
		return matched
	var ids := _story_ids(kind, scope_id, speaker)
	for raw_id in ids:
		var id := String(raw_id)
		var found: Variant = _runtime.content().storylets.get(id, null)
		if not (found is WyrdStoryletDef):
			continue
		var story: WyrdStoryletDef = found
		if not _scope_matches(story, kind, scope_id):
			continue
		if not _speaker_matches(story.speaker, speaker):
			continue
		if _blocked(story):
			_trace_blocked(story)
			continue
		if not _when_passes(story):
			continue
		if _cooling(story):
			continue
		if _speaker_cooling(story, speaker):
			continue
		matched.append(story)
	return matched


func _failing_clause(story: WyrdStoryletDef) -> String:
	if story.condition == null:
		return ""
	if story.clauses.is_empty():
		if _runtime.eval_storylet(story.condition, story.id):
			return ""
		return story.when_text
	for index in story.clauses.size():
		if _runtime.eval_storylet(story.clauses[index], story.id):
			continue
		if index < story.clause_text.size():
			return story.clause_text[index]
		return story.when_text
	return ""


func _remaining(story: WyrdStoryletDef) -> int:
	if story.cooldown_minutes <= 0 or _runtime == null or _runtime.storylets == null:
		return 0
	var last := _runtime.storylets.last_minute_of(story.id)
	if last < 0:
		return 0
	var elapsed := _runtime.now_minutes() - last
	if elapsed >= story.cooldown_minutes:
		return 0
	return story.cooldown_minutes - elapsed


func _pick(matched: Array, scope_text: String, speaker: String) -> WyrdStoryletDef:
	if matched.is_empty():
		return null
	var best: Array = [matched[0]]
	for index in range(1, matched.size()):
		var story: WyrdStoryletDef = matched[index]
		var cmp := _compare(story, best[0])
		if cmp > 0:
			best = [story]
		elif cmp == 0:
			best.append(story)
	if best.size() == 1:
		return best[0]
	var by_id := {}
	var names: Array = []
	for story in best:
		by_id[story.id] = story
		names.append(story.id)
	names.sort()
	var key := StringName("%s\t%s" % [scope_text, speaker])
	var rng := WyrdRng.for_decision(_runtime.game_seed(), STREAM, key, _runtime.now_minutes())
	return by_id[names[rng.randi_bounded(names.size())]]


## Above zero when [param a] should win over [param b].
func _compare(a: WyrdStoryletDef, b: WyrdStoryletDef) -> int:
	if a.priority != b.priority:
		return 1 if a.priority > b.priority else -1
	if a.specificity != b.specificity:
		return 1 if a.specificity > b.specificity else -1
	if a.weight != b.weight:
		return 1 if a.weight > b.weight else -1
	var seen_a := _runtime.storylets.seen_of(a.id)
	var seen_b := _runtime.storylets.seen_of(b.id)
	if seen_a != seen_b:
		return 1 if seen_a < seen_b else -1
	var last_a := _runtime.storylets.last_minute_of(a.id)
	var last_b := _runtime.storylets.last_minute_of(b.id)
	if last_a != last_b:
		return 1 if last_a < last_b else -1
	return 0


func _story_ids(kind: StringName, scope_id: String, speaker: String) -> PackedStringArray:
	var index: WyrdStoryletIndex = null
	if _runtime != null and _runtime.content() != null:
		index = _runtime.content().storylet_index
	if index == null:
		return _scan_ids()
	var ids := index.ids_for(kind, scope_id, speaker)
	_runtime.trace_storylet_index(_scope_text(kind, scope_id), "" if kind == &"bark" else scope_id, speaker, ids.size())
	return ids


func _scan_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if _runtime == null or _runtime.content() == null:
		return ids
	var names: Array = _runtime.content().storylets.keys()
	names.sort()
	for raw_id in names:
		ids.append(String(raw_id))
	return ids


func _scope_matches(story: WyrdStoryletDef, kind: StringName, scope_id: String) -> bool:
	if story.scope_kind != kind:
		return false
	if kind == &"bark":
		return true
	return story.scope_id == scope_id


func _speaker_matches(story_speaker: String, query_speaker: String) -> bool:
	if query_speaker.is_empty() or query_speaker == WILDCARD:
		return true
	if story_speaker == WILDCARD:
		return true
	return story_speaker == query_speaker


func _when_passes(story: WyrdStoryletDef) -> bool:
	if story.condition == null:
		return true
	return _runtime.eval_storylet(story.condition, story.id)


func _cooling(story: WyrdStoryletDef) -> bool:
	if story.cooldown_minutes <= 0:
		return false
	var last := _runtime.storylets.last_minute_of(story.id)
	if last < 0:
		return false
	return _runtime.now_minutes() - last < story.cooldown_minutes


func _note_speaker(story: WyrdStoryletDef, query_speaker: String, minute: int) -> void:
	if story.scope_kind != &"bark" or story.speaker_cooldown_minutes <= 0:
		return
	var key := _speaker_key(story, query_speaker)
	if key.is_empty():
		return
	_runtime.storylets.note_bark_speaker(key, story.speaker_cooldown_minutes, minute)


func _speaker_cooling(story: WyrdStoryletDef, query_speaker: String) -> bool:
	if story.scope_kind != &"bark":
		return false
	var key := _speaker_key(story, query_speaker)
	if key.is_empty() or _runtime == null or _runtime.storylets == null:
		return false
	return _runtime.storylets.speaker_cooling(key, _runtime.now_minutes())


func _speaker_key(story: WyrdStoryletDef, query_speaker: String) -> String:
	if _concrete(query_speaker):
		return query_speaker
	if _concrete(story.speaker):
		return story.speaker
	return ""


func _concrete(name: String) -> bool:
	return not name.is_empty() and name != WILDCARD


func _known_scope(kind: StringName) -> bool:
	return kind == &"topic" or kind == &"bark" or kind == &"event" or kind == &"beat"


func _scope_text(kind: StringName, scope_id: String) -> String:
	if kind == &"bark":
		return "bark"
	return "%s %s" % [String(kind), scope_id]


func _allow_for(story: WyrdStoryletDef) -> Callable:
	return func(line: WyrdLineDef) -> bool:
		return _line_visible(story, line)


func _line_visible(story: WyrdStoryletDef, line: WyrdLineDef) -> bool:
	var tier := _line_tier(story, line)
	if _runtime.secrecy_allows(tier):
		return true
	_runtime.trace_secrecy(story.id, line.line_id, tier, _runtime.secrecy_unlocked_name(), story.scope_text(), story.speaker)
	return false


func _blocked(story: WyrdStoryletDef) -> bool:
	if not _runtime.secrecy_allows(story.secrecy):
		return true
	if story.lines.is_empty():
		return false
	for line in story.lines:
		if _runtime.secrecy_allows(_line_tier(story, line)):
			return false
	return true


func _trace_blocked(story: WyrdStoryletDef) -> void:
	var tier := story.secrecy
	if tier.is_empty():
		for line in story.lines:
			var name := _line_tier(story, line)
			if not name.is_empty() and not _runtime.secrecy_allows(name):
				tier = name
				break
	_runtime.trace_secrecy(story.id, "", tier, _runtime.secrecy_unlocked_name(), story.scope_text(), story.speaker)


func _line_tier(story: WyrdStoryletDef, line: WyrdLineDef) -> String:
	if line != null and not line.secrecy.is_empty():
		return line.secrecy
	return story.secrecy


func _tier_text(storylet_id: String) -> String:
	if _runtime == null or _runtime.content() == null:
		return "-"
	var found: Variant = _runtime.content().storylets.get(storylet_id, null)
	if not (found is WyrdStoryletDef):
		return "-"
	var story := found as WyrdStoryletDef
	if not story.secrecy.is_empty():
		return story.secrecy
	var labeled := ""
	var any_open := story.lines.is_empty()
	for line in story.lines:
		var name := _line_tier(story, line)
		if name.is_empty() or _runtime.secrecy_allows(name):
			any_open = true
			break
		if labeled.is_empty():
			labeled = name
	if any_open or labeled.is_empty():
		return "-"
	return labeled


func _unlocked_text() -> String:
	if _runtime == null:
		return "-"
	var name := _runtime.secrecy_unlocked_name()
	if name.is_empty():
		return "-"
	return name


static func _dash(row: Dictionary, key: String) -> String:
	var text := str(row.get(key, ""))
	if text.is_empty():
		return "-"
	return text


func _scope_id_of(scope_text: String) -> String:
	if scope_text == "bark":
		return ""
	var split := scope_text.find(" ")
	if split < 0:
		return ""
	return scope_text.substr(split + 1)
