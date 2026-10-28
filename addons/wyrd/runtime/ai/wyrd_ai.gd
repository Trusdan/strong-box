class_name WyrdAI
extends RefCounted

## AI hook for one runtime. Open requests are not saved.
##
## The null provider is the default. A request keeps no pending state while that
## provider is active, or while the hook is disabled. [method deliver] closes a
## pending request, validates the text, and caches it when it passes.
## [method present] shows that cached text for an opted-in line when the
## provider lists the current locale. Otherwise the authored line shows.
## Dialogue does not wait. The cache is saved only when
## [member WyrdConfig.ai_save_cache] is true and it is not empty.
## [method packet_for_line] builds a packet without sending.
## [method kind_for_line] is [code]gossip[/code] when the line is opted in and tagged
## [code]gossip[/code]. [method summary_for] returns a journal summary.
## [method host_text] reads cached text for a host-called kind and does not send.

var _runtime: WyrdRuntime
var _provider: WyrdAIProvider
var _enabled: bool = true
var _next_id: int = 1
var _pending: Dictionary = {}
var _classifier: Callable = Callable()
var _classifier_set: bool = false
var _cache := WyrdAICache.new()
## Keys whose last validation failed, oldest first. Not saved.
var _rejected: Dictionary = {}
## Requests cancelled because their scene ended or a topic menu replaced them.
## A later delivery is still validated. Not saved.
var _late: Array[WyrdAIRequest] = []
## Bark storylet ids still to visit, oldest first. Not saved.
var _sweep: Array[String] = []
## True after a sweep has been armed since AI became active, a new game, or a load.
var _sweep_once: bool = false
## Game minute of the last arm. [code]-1[/code] until then.
var _sweep_at: int = -1


## @experimental
func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime


## Turns the hook on or off. Turning it off drops pending requests.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if not _enabled:
		drop_pending(&"off")
	_trace_provider()


## @experimental
func is_enabled() -> bool:
	return _enabled


## @experimental
func provider() -> WyrdAIProvider:
	return _provider


## @experimental
func provider_id() -> StringName:
	if _provider == null:
		return &""
	return _provider.id()


## True when the hook is enabled and the provider is not [WyrdNullAIProvider].
## @experimental
func is_active() -> bool:
	return _enabled and _provider != null and not (_provider is WyrdNullAIProvider)


## @experimental
func kinds() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(WyrdAIRequest.KINDS)
	return copy


## Sends one host request. Returns 0 when the kind is unknown, the hook is off, or the provider is null.
func request(kind: StringName, packet: Dictionary, constraints: Dictionary = {}, path: StringName = &"") -> int:
	var _host_gate: Variant = _runtime._host_enter() if _runtime != null else null
	if _runtime != null:
		_runtime.trace_add("ai_host_request", {
			"constraints": constraints.duplicate(true),
			"kind": String(kind),
			"packet": packet.duplicate(true),
			"path": String(path),
		})
	if not _known(kind):
		push_warning("WyrdAI.request: unknown kind %s" % String(kind))
		_trace_request(0, kind, path, &"refused", &"kind", "-")
		return 0
	if not _enabled:
		_trace_request(0, kind, path, &"refused", &"off", "-")
		return 0
	if _provider == null or _provider is WyrdNullAIProvider:
		_trace_request(0, kind, path, &"refused", &"null", "-")
		return 0
	return _send(kind, packet, path, "", constraints)


## Validates a provider answer on the main thread and caches the text when it passes. Returns false off the main thread or for an unknown request.
func deliver(request_id: int, result: WyrdAIResult) -> bool:
	var _host_gate: Variant = _runtime._host_enter() if _runtime != null else null
	var off_thread := OS.get_thread_caller_id() != OS.get_main_thread_id()
	if not off_thread:
		_record_deliver(request_id, result)
	var req := _pending.get(request_id) as WyrdAIRequest
	var late := false
	if req == null and not off_thread:
		req = _take_late(request_id)
		late = req != null
	var kind := "-"
	var path := ""
	if req != null:
		kind = String(req.kind)
		path = String(req.path)
	var ok := result != null and result.ok
	if off_thread:
		push_error("WyrdAI.deliver: not on the main thread")
		_trace_result(request_id, kind, path, ok, "thread", "-")
		return false
	if req == null:
		_trace_result(request_id, "-", "", ok, "unknown_request", "-")
		return false
	if not late:
		_pending.erase(request_id)
	var shown := "late" if late else "-"
	_trace_result(request_id, kind, path, ok, shown, req.key)
	var rule := "provider"
	if result != null and result.ok:
		rule = String(validate(result.text, req.kind, req.packet, req.constraints))
		if rule.is_empty():
			rule = "-"
	_trace_validate(request_id, kind, path, rule == "-", rule, req.key)
	if rule == "-":
		_rejected.erase(req.key)
		_remember(req.key, result.text)
	else:
		_mark_rejected(req.key)
	return true


## Cancels one pending request and tells the provider. Returns false when that id is not pending.
func cancel(request_id: int) -> bool:
	var _host_gate: Variant = _runtime._host_enter() if _runtime != null else null
	if not _pending.has(request_id):
		return false
	if _runtime != null and _runtime._host_logs():
		_runtime._host_mark("ai.cancel", [request_id])
	var req := _pending[request_id] as WyrdAIRequest
	_pending.erase(request_id)
	if _provider != null:
		_provider.cancel(request_id)
	_trace_cancel(req, &"host")
	return true


## @experimental
func pending_count() -> int:
	return _pending.size()


## Sends one request. [param owner] is empty for a host call.
func _send(kind: StringName, packet: Dictionary, path: StringName, owner: String, constraints: Dictionary = {}) -> int:
	var request_id := _next_id
	_next_id += 1
	var req := WyrdAIRequest.new()
	req.id = request_id
	req.kind = kind
	req.packet = packet.duplicate(true)
	req.constraints = constraints.duplicate(true)
	req.locale = StringName(TranslationServer.get_locale())
	req.path = path
	req.owner = owner
	req.sent_minute = _runtime.now_minutes() if _runtime != null else -1
	req.key = cache_key(kind, req.packet, req.locale)
	req.set_deliver(Callable(self, &"deliver"))
	_pending[request_id] = req
	_trace_request(request_id, kind, path, &"sent", &"-", req.key)
	_provider.request(req)
	return request_id


## True when [param locale] is listed by the provider, or its language part is.
## An empty argument means the current locale. The null provider is never OK.
## @experimental
func locale_ok(locale: String = "") -> bool:
	if not is_active():
		return false
	var loc := locale
	if loc.is_empty():
		loc = TranslationServer.get_locale()
	var language := loc
	var split := loc.find("_")
	if split > 0:
		language = loc.substr(0, split)
	for item in _provider.locales():
		var name := String(item)
		if name == loc or name == language:
			return true
	return false


## One prefetch pass. Each row is [code]{line_id, speaker}[/code].
## Returns without a trace when AI is off, the provider is null, or the cap is off.
## [param owner_cap] of 0 or more also caps rows when that many requests with this
## source's owner prefix are already open. [code]-1[/code] does not.
## @experimental
func prefetch_lines(source: StringName, id: String, rows: Array, owner_cap: int = -1) -> void:
	if not is_active():
		return
	var cap := _inflight_cap()
	if cap <= 0:
		return
	var sent := 0
	var cached := 0
	var already := 0
	var capped := 0
	var skipped := 0
	var prefix := "%s:" % String(source)
	var owned := _owned_count(prefix) if owner_cap >= 0 else 0
	for row in rows:
		if not locale_ok():
			skipped += 1
			continue
		var line_id := ""
		var speaker := &""
		if row is Dictionary:
			line_id = str((row as Dictionary).get("line_id", ""))
			speaker = StringName(str((row as Dictionary).get("speaker", "")))
		var kind := kind_for_line(line_id)
		var packet := packet_for_line(line_id, kind, speaker)
		var key := cache_key(kind, packet)
		if _cache.has(key):
			cached += 1
		elif _pending_has_key(key):
			already += 1
		elif pending_count() >= cap or (owner_cap >= 0 and owned >= owner_cap):
			capped += 1
		else:
			_send(kind, packet, StringName(line_id), "%s%s" % [prefix, id])
			sent += 1
			owned += 1
	_trace_prefetch(String(source), id, rows.size(), sent, cached, already, capped, skipped)


## Expires old bark requests, then arms a bark sweep when one is due.
## Called once per game tick, before the scheduler runs.
## @experimental
func tick_prefetch(now: int, scheduler: WyrdScheduler) -> void:
	_expire_owned(now)
	if not is_active() or _inflight_cap() <= 1 or not _sweep.is_empty():
		return
	var candidates := _bark_candidates()
	if candidates.is_empty():
		return
	var reason := ""
	if not _sweep_once:
		reason = "start"
	elif scheduler != null and scheduler.marked:
		reason = "change"
	elif _sweep_at >= 0 and now - _sweep_at >= 60:
		reason = "floor"
	else:
		return
	_sweep = candidates
	_sweep_once = true
	_sweep_at = now
	if scheduler != null:
		scheduler.marked = false
	_trace_sweep("arm", _sweep.size(), reason)


## True when a bark sweep can send another request.
## @experimental
func prefetch_has_work() -> bool:
	return is_active() and not _sweep.is_empty() and _owned_count("bark:") < _bark_cap()


## Storylets still waiting in the current sweep.
## @experimental
func prefetch_carry() -> int:
	return _sweep.size()


## Visits the next bark storylet. Does not write gameplay state.
## @experimental
func prefetch_unit() -> void:
	if _sweep.is_empty():
		return
	var story_id := _sweep[0]
	_sweep.remove_at(0)
	_visit_bark(story_id)


## Sets [member WyrdLineView.text_source] for an opted-in line. Does not send.
## @experimental
func present(view: WyrdLineView, line_id: String) -> void:
	if view == null or _runtime == null or _runtime.content() == null:
		return
	if not _runtime.content().ai_lines.has(line_id):
		return
	var kind := kind_for_line(line_id)
	var kind_name := String(kind)
	if not is_active():
		view.text_source = &"authored"
		_trace_use(line_id, "authored", "off", "-", kind_name)
		return
	if not locale_ok():
		view.text_source = &"authored"
		_trace_use(line_id, "authored", "locale", "-", kind_name)
		return
	var packet := packet_for_line(line_id, kind, _view_speaker(view))
	var key := cache_key(kind, packet)
	if _cache.has(key):
		view.text = _cache.text_for(key)
		view.text_source = &"ai"
		_trace_use(line_id, "ai", "hit", key, kind_name)
		return
	view.text_source = &"authored"
	if _pending_has_key(key):
		_trace_use(line_id, "authored", "waiting", key, kind_name)
	elif _rejected.has(key):
		_trace_use(line_id, "authored", "rejected", key, kind_name)
	else:
		_trace_use(line_id, "authored", "miss", key, kind_name)


## Moves open requests with this owner to the late list, in id order.
## @experimental
func close_owner(owner: String, reason: StringName) -> void:
	_move_owned(owner, false, reason)


## Moves open requests whose owner starts with [param prefix] to the late list.
## @experimental
func close_prefixed(prefix: String, reason: StringName) -> void:
	_move_owned(prefix, true, reason)


## 16 lowercase hex digits. Constraints are not part of the key. A host that
## sends the same packet under different constraints should vary the packet.
## An empty [param locale] means the current locale.
## @experimental
func cache_key(kind: StringName, packet: Dictionary, locale: StringName = &"") -> String:
	var loc := String(locale)
	if loc.is_empty():
		loc = TranslationServer.get_locale()
	var version := 0
	if _provider != null:
		version = _provider.prompt_version()
	var mixed := WyrdHash.of_text(String(kind))
	mixed = WyrdHash.combine(mixed, WyrdHash.of_text(WyrdAIPacket.canonical(packet)))
	mixed = WyrdHash.combine(mixed, WyrdHash.of_text(String(provider_id())))
	mixed = WyrdHash.combine(mixed, WyrdHash.of_int(version))
	mixed = WyrdHash.combine(mixed, WyrdHash.of_text(loc))
	return WyrdRng.format_u64(mixed)


## [code]gossip[/code] when [param line_id] is opted in and tagged [code]gossip[/code].
## Otherwise [code]bark_paraphrase[/code]. A gossip tag without [code]#tag:ai[/code] does nothing.
## @experimental
func kind_for_line(line_id: String) -> StringName:
	if _runtime == null or _runtime.content() == null or not _runtime.content().ai_lines.has(line_id):
		return &"bark_paraphrase"
	var line_def := _runtime.content().lines.get(line_id) as WyrdLineDef
	if line_def != null and line_def.tags.has("gossip"):
		return &"gossip"
	return &"bark_paraphrase"


## Packet for an opted-in line. Does not send a request, and ignores the provider and the on/off state.
## @experimental
func packet_for_line(line_id: String, kind: StringName = &"bark_paraphrase", speaker: StringName = &"") -> Dictionary:
	return WyrdAIPacket.for_line(_runtime, line_id, kind, speaker)


## Journal summary packet. [param entries] are frozen journal rows. Does not send.
## @experimental
func summary_packet(quest_id: String, entries: Array) -> Dictionary:
	var ids: Array = []
	var texts: Array = []
	for item in entries:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		ids.append(str(row.get("id", "")))
		texts.append(str(row.get("text", "")))
	var lines := PackedStringArray()
	for text in texts:
		lines.append(String(text))
	return {
		"entities": _summary_entities("\n".join(lines)),
		"entries": texts,
		"kind": "journal_summary",
		"line_ids": ids,
		"quest": quest_id,
		"text": "\n".join(lines),
		"v": 1,
	}


## Joined journal text, or validated cached summary text. Sends one request on a miss.
## An empty journal returns [code]""[/code] and logs nothing.
## @experimental
func summary_for(quest_id: String, entries: Array) -> String:
	if entries.is_empty():
		return ""
	var packet := summary_packet(quest_id, entries)
	var fallback := WyrdAIPacket.fallback_text(&"journal_summary", packet)
	var path := "summary:%s" % quest_id
	if not is_active():
		_trace_use(path, "authored", "off", "-", "journal_summary")
		return fallback
	if not locale_ok():
		_trace_use(path, "authored", "locale", "-", "journal_summary")
		return fallback
	var key := cache_key(&"journal_summary", packet)
	if _cache.has(key):
		_trace_use(path, "ai", "hit", key, "journal_summary")
		return _cache.text_for(key)
	var reason := "miss"
	if _pending_has_key(key):
		reason = "waiting"
	elif _rejected.has(key):
		reason = "rejected"
	_trace_use(path, "authored", reason, key, "journal_summary")
	if reason == "miss":
		_send_summary(quest_id, packet)
	return fallback


## Cached text for a host-called kind. Sends nothing and logs nothing.
## The read side of [method request] for [code]epilogue_stitch[/code] and [code]tts_prep[/code].
func host_text(kind: StringName, packet: Dictionary, fallback: String) -> String:
	if not _known(kind) or not is_active() or not locale_ok():
		return fallback
	var key := cache_key(kind, packet)
	if not _cache.has(key):
		return fallback
	return _cache.text_for(key)


## First failing rule, or an empty name when [param text] passes.
## @experimental
func validate(text: String, kind: StringName, packet: Dictionary, constraints: Dictionary = {}) -> StringName:
	var checker := WyrdAIValidator.new()
	checker.classifier = _classifier
	checker.classifier_registered = _classifier_set
	if _runtime != null and _runtime.config() != null:
		checker.banned_terms = _runtime.config().ai_banned_terms.duplicate()
	checker.entity_names = _entity_names()
	checker.spoilers = _spoilers(packet)
	return checker.check(text, kind, packet, constraints)


## One classifier per runtime. [code]Callable()[/code] clears it. Not saved.
## It survives [method WyrdRuntime.start_new_game] and [method WyrdRuntime.load_state].
func register_classifier(fn: Callable) -> void:
	if not fn.is_valid():
		_classifier = Callable()
		_classifier_set = false
		_trace_classifier("clear")
		return
	_classifier = fn
	_classifier_set = true
	_trace_classifier("set")


## @experimental
func set_provider(next: WyrdAIProvider) -> void:
	if next == null:
		push_error("WyrdAI.set_provider: provider is null")
		return
	drop_pending(&"provider")
	_provider = next
	_trace_provider()


## Drops every pending request. [code]new_game[/code] and [code]load[/code] also reset the id counter.
## @experimental
func drop_pending(reason: StringName) -> void:
	_forget_late(String(reason))
	var ids: Array = _pending.keys()
	ids.sort()
	var current := _provider
	for raw in ids:
		var request_id := int(raw)
		var req := _pending[request_id] as WyrdAIRequest
		_pending.erase(request_id)
		if current != null:
			current.cancel(request_id)
		_trace_cancel(req, reason)
	if reason == &"load":
		_rejected.clear()
	if reason == &"off" or reason == &"provider" or reason == &"new_game" or reason == &"load":
		_drop_sweep(String(reason))
	if reason == &"new_game" or reason == &"load":
		_next_id = 1


func _known(kind: StringName) -> bool:
	for name in WyrdAIRequest.KINDS:
		if name == kind:
			return true
	return false


func _trace_provider() -> void:
	if _runtime == null:
		return
	var state := "on" if is_active() else "off"
	_runtime.trace_ai_provider(String(provider_id()), state)


## @experimental
func cached_text(key: String) -> String:
	return _cache.text_for(key)


## @experimental
func cache_size() -> int:
	return _cache.size()


## Oldest first.
## @experimental
func cache_keys() -> PackedStringArray:
	return _cache.keys()


## Empties the cache. Traces [code]op=clear[/code] only when it held entries.
## @experimental
func clear_cache() -> void:
	var _host_gate: Variant = _runtime._host_enter() if _runtime != null else null
	if _runtime != null and _runtime._host_logs() and (_cache.size() > 0 or not _rejected.is_empty()):
		_runtime._host_mark("ai.clear_cache", [])
	_rejected.clear()
	if _cache.size() == 0:
		return
	_cache.clear()
	_trace_cache("clear", "-", 0)


## [code]v[/code] 1 and the rows, oldest first.
## @experimental
func export_cache() -> Dictionary:
	return {"cache": _cache.export_rows(), "v": 1}


## Applies an [code]ai[/code] save key. A missing key clears the cache.
## A malformed key warns [code]W_SAVE_AI[/code] and clears it. The load still succeeds.
## @experimental
func import_cache(raw: Variant, present: bool, report: WyrdLoadReport) -> void:
	if not present:
		clear_cache()
		return
	if not _bag_ok(raw):
		_cache.clear()
		_warn_ai(report, "AI cache is not valid and was ignored", 0)
		_trace_cache("load", "-", 0)
		return
	var bag: Dictionary = raw
	var skipped := _cache.import_rows(bag.get("cache", []), _cache_cap())
	_trace_cache("load", "-", _cache.size())
	if skipped > 0:
		_warn_ai(report, "AI cache: %d entries were not valid and were skipped" % skipped, skipped)


func _remember(key: String, text: String) -> void:
	var cap := _cache_cap()
	var evicted := _cache.insert(key, text, cap)
	if cap <= 0:
		return
	var count := _cache.size() + evicted.size()
	_trace_cache("insert", key, count)
	for old in evicted:
		count -= 1
		_trace_cache("evict", String(old), count)


func _cache_cap() -> int:
	if _runtime == null or _runtime.config() == null:
		return 256
	return _runtime.config().ai_cache_max


func _bag_ok(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var bag: Dictionary = raw
	if not _version_one(bag.get("v", null)):
		return false
	return bag.get("cache", null) is Array


func _version_one(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) == 1
	if typeof(value) == TYPE_FLOAT:
		return float(value) == 1.0
	return false


func _warn_ai(report: WyrdLoadReport, message: String, count: int = 0) -> void:
	if report == null:
		return
	report.diagnostics.add(
		WyrdDiagnostic.W_SAVE_AI,
		message,
		"",
		1,
		1,
		WyrdDiagnostic.SEVERITY_WARNING
	)
	report.add_row("ai", "", "", "", count, "W_SAVE_AI")


func _trace_request(request_id: int, kind: StringName, path: StringName, state: StringName, reason: StringName, key: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_request(request_id, String(kind), String(path), String(state), String(reason), key)


func _trace_result(request_id: int, kind: String, path: String, ok: bool, rule: String, key: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_result(request_id, kind, path, ok, rule, key)


func _trace_cancel(req: WyrdAIRequest, reason: StringName) -> void:
	if _runtime == null or req == null:
		return
	var key := req.key
	if key.is_empty():
		key = "-"
	_runtime.trace_ai_cancel(req.id, String(req.kind), String(req.path), String(reason), key)


func _trace_validate(request_id: int, kind: String, path: String, ok: bool, rule: String, key: String) -> void:
	if _runtime == null:
		return
	var shown := key
	if shown.is_empty():
		shown = "-"
	_runtime.trace_ai_validate(request_id, kind, path, ok, rule, shown)


func _trace_cache(op: String, key: String, count: int) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_cache(op, key, count)


func _trace_classifier(state: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_classifier(state)


func _trace_prefetch(source: String, path: String, lines: int, sent: int, cached: int, already: int, capped: int, skipped: int) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_prefetch(source, path, lines, sent, cached, already, capped, skipped)


func _trace_use(line_id: String, source: String, reason: String, key: String, kind: String = "bark_paraphrase") -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_use(line_id, source, reason, key, kind)


func _trace_sweep(op: String, count: int, reason: String) -> void:
	if _runtime == null:
		return
	_runtime.trace_ai_sweep(op, count, reason)


func _trace_late(req: WyrdAIRequest, reason: String) -> void:
	if _runtime == null or req == null:
		return
	var key := req.key
	if key.is_empty():
		key = "-"
	_runtime.trace_ai_late(req.id, String(req.path), reason, key)


func _record_deliver(request_id: int, result: WyrdAIResult) -> void:
	if _runtime == null:
		return
	var text := ""
	var error := ""
	if result != null:
		text = result.text
		error = result.error
	_runtime.trace_add("ai_deliver", {
		"error": error,
		"id": request_id,
		"ok": result != null and result.ok,
		"text": text,
	})


func _inflight_cap() -> int:
	if _runtime == null or _runtime.config() == null:
		return 4
	return _runtime.config().ai_max_inflight


## Barks leave one open slot for a scene or a topic menu.
func _bark_cap() -> int:
	return maxi(_inflight_cap() - 1, 0)


func _owned_count(prefix: String) -> int:
	var count := 0
	for raw in _pending.values():
		var req := raw as WyrdAIRequest
		if req != null and req.owner.begins_with(prefix):
			count += 1
	return count


func _expire_owned(now: int) -> void:
	var ids: Array = _pending.keys()
	ids.sort()
	for raw in ids:
		var request_id := int(raw)
		var req := _pending.get(request_id) as WyrdAIRequest
		if req == null or not (req.owner.begins_with("bark:") or req.owner.begins_with("summary:")):
			continue
		if req.sent_minute < 0 or now - req.sent_minute < 60:
			continue
		_pending.erase(request_id)
		_late_add(req)
		_trace_cancel(req, &"expired")
		if _provider != null:
			_provider.cancel(request_id)


func _bark_candidates() -> Array[String]:
	var ids: Array[String] = []
	if _runtime == null or _runtime.content() == null:
		return ids
	var content := _runtime.content()
	var found := {}
	for line_id in content.ai_lines.keys():
		var entry: Dictionary = content.ai_lines[line_id]
		if str(entry.get("owner", "")) != "storylet":
			continue
		var story_id := str(entry.get("id", ""))
		var story := content.storylets.get(story_id) as WyrdStoryletDef
		if story == null or story.scope_kind != &"bark":
			continue
		found[story_id] = true
	var names: Array = found.keys()
	names.sort()
	for name in names:
		ids.append(String(name))
	return ids


func _visit_bark(story_id: String) -> void:
	if _runtime == null or _runtime.content() == null or _runtime.director == null:
		return
	var story := _runtime.content().storylets.get(story_id) as WyrdStoryletDef
	if story == null:
		return
	if story.speaker.is_empty() or story.speaker == "any":
		return
	if not _runtime.director.when_holds(story):
		return
	var line_ids: Array = []
	for line_def in story.lines:
		if line_def == null or line_def.line_id.is_empty():
			continue
		if not _runtime.content().ai_lines.has(line_def.line_id):
			continue
		var entry: Dictionary = _runtime.content().ai_lines[line_def.line_id]
		if str(entry.get("owner", "")) != "storylet" or str(entry.get("id", "")) != story.id:
			continue
		line_ids.append(line_def.line_id)
	line_ids.sort()
	var shown := _runtime.bark_entity(story)
	if shown.is_empty() or shown == "narrator":
		shown = ""
	var rows: Array = []
	for line_id in line_ids:
		rows.append({"line_id": String(line_id), "speaker": shown})
	prefetch_lines(&"bark", story.id, rows, _bark_cap())


func _drop_sweep(reason: String) -> void:
	if not _sweep.is_empty():
		_trace_sweep("drop", _sweep.size(), reason)
	_sweep.clear()
	_sweep_once = false
	_sweep_at = -1


func _pending_has_key(key: String) -> bool:
	for raw in _pending.values():
		var req := raw as WyrdAIRequest
		if req != null and req.key == key:
			return true
	return false


func _view_speaker(view: WyrdLineView) -> StringName:
	if view.speaker == &"" or view.speaker == &"narrator":
		return &""
	return view.speaker


func _move_owned(owner: String, prefixed: bool, reason: StringName) -> void:
	var ids: Array = _pending.keys()
	ids.sort()
	for raw in ids:
		var request_id := int(raw)
		var req := _pending[request_id] as WyrdAIRequest
		if req == null:
			continue
		var matches := req.owner.begins_with(owner) if prefixed else req.owner == owner
		if not matches:
			continue
		_pending.erase(request_id)
		_late_add(req)
		_trace_cancel(req, reason)
		if _provider != null:
			_provider.cancel(request_id)


func _late_add(req: WyrdAIRequest) -> void:
	_late.append(req)
	var cap := maxi(_inflight_cap(), 1)
	while _late.size() > cap:
		var old := _late[0]
		_late.remove_at(0)
		_trace_late(old, "cap")


func _take_late(request_id: int) -> WyrdAIRequest:
	for index in _late.size():
		var req := _late[index]
		if req != null and req.id == request_id:
			_late.remove_at(index)
			return req
	return null


func _forget_late(reason: String) -> void:
	for req in _late:
		_trace_late(req, reason)
	_late.clear()


func _mark_rejected(key: String) -> void:
	if key.is_empty():
		return
	if _rejected.has(key):
		_rejected.erase(key)
	_rejected[key] = true
	var cap := _cache_cap()
	if cap <= 0:
		_rejected.clear()
		return
	while _rejected.size() > cap:
		var oldest: Array = _rejected.keys()
		_rejected.erase(oldest[0])


func _send_summary(quest_id: String, packet: Dictionary) -> void:
	var cap := _inflight_cap()
	var sent := 0
	var capped := 0
	if cap > 0 and pending_count() < cap:
		var owner := "summary:%s" % quest_id
		close_owner(owner, &"superseded")
		_send(&"journal_summary", packet, StringName(owner), owner)
		sent = 1
	else:
		capped = 1
	_trace_prefetch("summary", quest_id, 1, sent, 0, 0, capped, 0)


func _summary_entities(text: String) -> Array:
	var rows: Array = []
	var names := _entity_names()
	var labels: Array = names.keys()
	labels.sort()
	for label in labels:
		var name := String(label)
		if not WyrdAIValidator.word_hit(text, name, false):
			continue
		var ids: Variant = names[label]
		if not (ids is Array):
			continue
		for id in ids:
			rows.append({"id": String(id), "name": name})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"])
	)
	return rows


func _entity_names() -> Dictionary:
	var names := {}
	var world := _world()
	if world == null:
		return names
	for id in world.candidates(WyrdEntityFilter.new()):
		var shown := world.display_name(StringName(str(id)))
		if shown.is_empty():
			continue
		if not names.has(shown):
			names[shown] = []
		(names[shown] as Array).append(String(id))
	return names


func _spoilers(packet: Dictionary) -> PackedStringArray:
	var found := {}
	if _runtime == null or _runtime.facts == null:
		return _sorted_forms(found)
	var listed: Dictionary = {}
	var raw_facts: Variant = packet.get("facts", {})
	if raw_facts is Dictionary:
		listed = raw_facts
	var secrecy := ""
	if _runtime.config() != null:
		secrecy = _runtime.config().secrecy_fact
	var world := _world()
	for key in _runtime.facts.world_keys():
		if listed.has(key) or key == secrecy:
			continue
		var world_value: Variant = _runtime.facts.get_in(StringName(key), &"world")
		var known_value: Variant = _runtime.facts.get_in(StringName(key), &"known/player")
		if known_value != null and _same_value(known_value, world_value):
			continue
		if not (world_value is String or world_value is StringName):
			continue
		var text := String(world_value)
		_add_form(found, text)
		_add_form(found, text.replace("_", " "))
		if world != null and world.exists(StringName(text)):
			_add_form(found, world.display_name(StringName(text)))
	_add_secret_roles(found)
	return _sorted_forms(found)


func _add_secret_roles(found: Dictionary) -> void:
	if _runtime == null or _runtime.content() == null or _runtime.roles == null:
		return
	var ids: Array = _runtime.content().roles.keys()
	ids.sort()
	for id in ids:
		var role := _runtime.content().roles[id] as WyrdRoleDef
		if role == null or role.visibility != "secret":
			continue
		var key := "role.%s.holder" % role.id
		if _runtime.roles.revealed(&"player", StringName(key)):
			continue
		_add_form(found, role.id)
		_add_form(found, role.id.replace("_", " "))


func _add_form(found: Dictionary, form: String) -> void:
	var text := form.strip_edges()
	if text.length() < 3 or found.has(text):
		return
	found[text] = true


func _sorted_forms(found: Dictionary) -> PackedStringArray:
	var names: Array = found.keys()
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append(String(name))
	return out


func _same_value(left: Variant, right: Variant) -> bool:
	if left == right:
		return true
	if (left is String or left is StringName) and (right is String or right is StringName):
		return String(left) == String(right)
	return false


func _world() -> WyrdWorldAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
