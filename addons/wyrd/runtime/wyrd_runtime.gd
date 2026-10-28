class_name WyrdRuntime
extends RefCounted

## One narrative runtime. Tests each keep their own instance.
##
## @experimental
## S2a loads a manifest by compiling its [code].wyrd[/code] sources, then keeps
## a fact store, a condition table, and a fixed-work scheduler. S2b adds the
## deed log, relationship axes, and role slots. S2c runs slice effects, quests,
## and scenes. S2d saves that state and can record a decision trace.
## Callables stay in the registries.

signal bark_ready(line: WyrdLineView)

const VERSION_PATH: String = "res://addons/wyrd/VERSION"
const _DEED_CALLS: PackedStringArray = ["deed_count", "deed_score", "affinity", "axis", "disposition", "reputation", "perceived", "slot_state"]
const _ROLE_CALLS: PackedStringArray = ["holder", "display_name", "filled", "known", "knows", "slot_state", "disposition"]
const _GROUPS_CHANGED: StringName = &"groups_changed"

var facts: WyrdFactStore
var events: WyrdEvents
var roles: WyrdRoles
var topics: WyrdTopics
var documents: WyrdDocuments
var deeds: WyrdDeedLog
var social: WyrdSocial
var rumors: WyrdRumor
var publish: WyrdPublish
var effects: WyrdEffects
var quests: WyrdQuestRunner
var dialogue: WyrdSceneRunner
var storylets: WyrdStoryletDeck
var sequences: WyrdSequences
var director: WyrdDirector
var generator: WyrdGenerator
var ai: WyrdAI
var trace: WyrdTrace
var debug: WyrdDebug
var coverage: WyrdCoverage

var _config: WyrdConfig
## Unknown secrecy names already reported. Not saved.
var _secrecy_warned: Dictionary = {}
var _deprecated_warned: Dictionary = {}
var _content: WyrdContent
var _queue: WyrdScheduler
## verb -> rows of template id and [WyrdDeedHookDef]. Not saved.
var _hooks_by_verb: Dictionary = {}
## Units of a game minute still waiting to complete [member WyrdConfig.scheduler_tick_minutes]. Not saved.
var _slice_carry: int = 0
var _ctx: WyrdConditionCtx
var _rpn: WyrdRpnEval
var _signatures: WyrdSignatures
var _adapters: Dictionary = {}
var _functions: Dictionary = {}
var _flags: PackedByteArray = PackedByteArray()
var _always: PackedInt32Array = PackedInt32Array()
var _trace: Array[Dictionary] = []
var _streams: Dictionary = {}
var _seed: int = 0
var _perception_key: String = ""
var _perception_value: Variant = null
var _minutes: int = 0
var _emit_seq: int = 0
var _collecting: bool = false
var _collected: Dictionary = {}
var _locals: Dictionary = {}
var _slot_traced: Dictionary = {}
## Quest ids. [method scope_instance] is set only when the top id contains [code]#[/code].
var _scope: Array[String] = []
var _provisional_scope: String = ""
var _provisional_casts: Dictionary = {}
var _provisional_params: Dictionary = {}
## End-of-tick creation enters the stage without evaluating waits. The next tick checks them.
var _defer_waits: bool = false
## Agent to precedence list. Not saved. Dropped by [method invalidate_groups].
var _group_cache: Dictionary = {}
var _group_order: Callable = Callable()
## Replaces the statement score. Not saved. The game seed is not an input.
var _credibility: Callable = Callable()
## Calls already on the stack. A direct game call records host_call only at 0.
var _host_depth: int = 0


func _init() -> void:
	facts = WyrdFactStore.new()
	events = WyrdEvents.new()
	roles = WyrdRoles.new()
	topics = WyrdTopics.new()
	topics.trace_of = Callable(self, &"trace_topic")
	documents = WyrdDocuments.new()
	documents.runtime = self
	storylets = WyrdStoryletDeck.new()
	storylets.on_coverage = Callable(self, &"_cover_draw")
	sequences = WyrdSequences.new()
	director = WyrdDirector.new()
	director.bind(self)
	deeds = WyrdDeedLog.new()
	social = WyrdSocial.new()
	_config = WyrdConfig.new()
	_queue = WyrdScheduler.new()
	_queue.trace_hook = Callable(self, &"_trace_scheduler")
	_queue.tracing_of = Callable(self, &"_tracing_on")
	generator = WyrdGenerator.new()
	generator.config_of = Callable(self, &"config")
	generator.trace_of = Callable(self, &"_trace_gen_offer")
	generator.bind(self)
	generator.generate_handler = Callable(self, &"_on_generate")
	_queue.generate_has_work = Callable(self, &"_generate_has_work")
	_queue.generate_unit = Callable(self, &"_generate_unit")
	_queue.generate_pending = Callable(self, &"_generate_pending")
	_queue.ai_prefetch_has_work = Callable(self, &"_ai_prefetch_has_work")
	_queue.ai_prefetch_unit = Callable(self, &"_ai_prefetch_unit")
	_queue.ai_prefetch_carry = Callable(self, &"_ai_prefetch_carry")
	_ctx = WyrdConditionCtx.new()
	_rpn = WyrdRpnEval.new()
	_signatures = WyrdSignatures.new()
	_ctx.bind(self)
	facts.on_keys = Callable(self, &"_mark_keys")
	facts.tracer = Callable(self, &"note")
	facts.on_belief = Callable(self, &"_trace_belief")
	facts.on_belief_touch = Callable(self, &"_clear_belief_cache")
	facts.belief_trace_of = Callable(self, &"_tracing_on")
	facts.on_knowledge = Callable(self, &"_trace_knowledge")
	deeds.on_perceived = Callable(self, &"_on_perceived")
	facts.on_resolved = Callable(self, &"_on_resolved")
	facts.clock = Callable(self, &"now_minutes")
	facts.resolver_of = Callable(self, &"_resolver")
	events.on_emit = Callable(self, &"_on_emit")
	events.on_batch = Callable(self, &"_on_batch")
	_rpn.fact_reader = Callable(facts, &"get_in")
	deeds.clock = Callable(self, &"now_minutes")
	deeds.config_of = Callable(self, &"config")
	deeds.spatial_of = Callable(self, &"_spatial")
	deeds.on_compact = Callable(self, &"_on_compact")
	social.deeds = deeds
	social.config_of = Callable(self, &"config")
	social.enqueue_cache = Callable(self, &"_enqueue_cache")
	social.on_cache = Callable(self, &"_trace_social_cache")
	social.tracing_of = Callable(self, &"_tracing_on")
	_queue.cache_handler = Callable(social, &"rebuild_cached")
	social.members_of = Callable(self, &"_members")
	facts.runtime = self
	deeds.runtime = self
	social.runtime = self
	roles.runtime = self
	topics.runtime = self
	social.on_reputation = Callable(self, &"_trace_reputation")
	rumors = WyrdRumor.new()
	rumors.social = social
	rumors.facts = facts
	rumors.deeds = deeds
	rumors.config_of = Callable(self, &"config")
	rumors.seed_of = Callable(self, &"game_seed")
	rumors.now_of = Callable(self, &"now_minutes")
	rumors.spatial_of = Callable(self, &"_spatial")
	rumors.score_of = Callable(self, &"credibility_score")
	rumors.threshold_of = Callable(self, &"credibility_threshold")
	rumors.trace_of = Callable(self, &"_trace_rumor")
	rumors.tracing_of = Callable(self, &"_tracing_on")
	rumors.enqueue_hop = Callable(self, &"_enqueue_rumor")
	rumors.on_reach = Callable(self, &"_on_rumor_reach")
	_queue.rumor_handler = Callable(rumors, &"hop")
	publish = WyrdPublish.new()
	publish.facts = facts
	publish.deeds = deeds
	publish.config_of = Callable(self, &"config")
	publish.now_of = Callable(self, &"now_minutes")
	publish.members_of = Callable(self, &"_members")
	publish.content_of = Callable(self, &"content")
	publish.eval_of = Callable(self, &"eval_bool")
	publish.trace_of = Callable(self, &"_trace_publish")
	publish.cursor_trace_of = Callable(self, &"_trace_publish_cursor")
	publish.enqueue_of = Callable(self, &"_enqueue_publish")
	_queue.publish_handler = Callable(publish, &"issue")
	roles.social = social
	roles.deeds = deeds
	roles.facts = facts
	roles.clock = Callable(self, &"now_minutes")
	roles.config_of = Callable(self, &"config")
	roles.content_of = Callable(self, &"content")
	roles.world_of = Callable(self, &"_world")
	roles.inventory_of = Callable(self, &"_inventory_adapter")
	roles.eval_with = Callable(self, &"eval_with_locals")
	roles.eval_value = Callable(self, &"eval_value_with_locals")
	roles.trace_of = Callable(self, &"_trace_role")
	deeds.deed_recorded.connect(_on_deed)
	roles.role_holder_changed.connect(_on_role)
	roles.role_vacant.connect(_on_role_vacant)
	social.on_changed = Callable(self, &"_on_social")
	social.trace_of = Callable(self, &"trace_baseline_adjust")
	effects = WyrdEffects.new()
	effects.bind(self)
	facts.provenance_of = Callable(effects, &"export_state")
	facts.on_choice_summary = Callable(self, &"trace_choice_summary")
	quests = WyrdQuestRunner.new()
	quests.bind(self)
	roles.stage_of = Callable(quests, &"stage")
	roles.seed_of = Callable(self, &"game_seed")
	roles.election_of = Callable(self, &"_election")
	dialogue = WyrdSceneRunner.new()
	dialogue.bind(self)
	effects.outcome_changed.connect(quests.note_outcome)
	dialogue.scene_ended.connect(quests.on_scene_ended)
	roles.role_holder_changed.connect(dialogue.note_role)
	trace = WyrdTrace.new()
	debug = WyrdDebug.new()
	debug.bind(self)
	coverage = WyrdCoverage.new()
	coverage.on_hit = Callable(self, &"trace_coverage")
	coverage.on_report = Callable(self, &"trace_coverage_report")
	ai = WyrdAI.new()
	ai.bind(self)
	register_adapter(WyrdAIProvider, WyrdNullAIProvider.new())


func get_version() -> String:
	return WyrdRuntime.read_version()


static func read_version() -> String:
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing version file at %s." % VERSION_PATH)
		return ""
	return file.get_as_text().strip_edges()


func config() -> WyrdConfig:
	return _config


func configure(next_config: WyrdConfig) -> void:
	if next_config == null:
		push_error("WyrdRuntime.configure: config is null")
		return
	_config = next_config


func register_adapter(base: Script, adapter: RefCounted) -> void:
	if base == null or adapter == null:
		push_error("WyrdRuntime.register_adapter: missing base or adapter")
		return
	var script := adapter.get_script() as Script
	if script == null or script.get_base_script() != base:
		push_error("WyrdRuntime.register_adapter: adapter is not a %s" % base.resource_path)
		return
	_adapters[base.resource_path] = adapter
	if base == WyrdAIProvider and ai != null:
		ai.set_provider(adapter as WyrdAIProvider)
	if base == WyrdWorldAdapter:
		invalidate_groups()
		if roles != null:
			roles.drop_cast_index()


func adapter(base: Script) -> RefCounted:
	if base == null or not _adapters.has(base.resource_path):
		return null
	return _adapters[base.resource_path] as RefCounted


func register_function(name: StringName, fn: Callable, arg_types: Array, return_type: StringName) -> bool:
	if not fn.is_valid():
		push_error("WyrdRuntime.register_function: \"%s\" has no callable" % String(name))
		return false
	if _functions.has(name) or _signatures.signature(name).size() > 0:
		var existing := _signatures.signature(name)
		if existing.is_empty() or not _signature_ok(existing, arg_types, return_type):
			push_error("WyrdRuntime.register_function: \"%s\" does not match its signature" % String(name))
			return false
		push_error("WyrdRuntime.register_function: \"%s\" is already registered" % String(name))
		return false
	var params: Array = []
	for i in arg_types.size():
		params.append({"name": StringName("arg%d" % i), "optional": false, "type": StringName(str(arg_types[i]))})
	if not _signatures.register(name, params, return_type):
		push_error("WyrdRuntime.register_function: \"%s\" was rejected" % String(name))
		return false
	_functions[name] = fn
	return true


## [param fn] receives [code](agent, groups)[/code] and returns the precedence list.
## The default list is [method WyrdWorldAdapter.groups_of]. Not saved.
func register_group_precedence(fn: Callable) -> void:
	_group_order = fn
	invalidate_groups()


## [param fn] receives [code](listener, speaker)[/code] and returns the score.
## It replaces [method credibility_score]. Not saved.
func register_credibility(fn: Callable) -> void:
	_credibility = fn


## Copies [param policy] into the rumor list. Not saved.
## The first policy whose verb list matches the deed is the one that spreads.
func register_rumor_policy(policy: WyrdRumorPolicy) -> void:
	if rumors == null:
		push_error("WyrdRuntime.register_rumor_policy: rumors are missing")
		return
	rumors.register(policy)


## Default is [code]disposition(listener, speaker) / 100[/code]. An override is used raw.
func credibility_score(listener: StringName, speaker: StringName) -> float:
	if _credibility.is_valid():
		return float(_credibility.call(listener, speaker))
	return float(social.disposition(listener, speaker)) / 100.0


func credibility_threshold() -> float:
	if _config == null:
		return 0.5
	return _config.credibility_threshold


## Drops cached cast candidate lists. An empty [param ids] means anything may
## have changed. This does not write a save or a trace line.
func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void:
	if roles != null:
		roles.invalidate_world(ids)


## Drops the membership cache and wakes conditions that read [code]group.membership[/code].
func invalidate_groups() -> void:
	_group_cache.clear()
	_clear_belief_cache()
	if social != null:
		social.invalidate_members()
	_mark_keys(PackedStringArray([&"group.membership"]))
	_mark_calls(PackedStringArray(["reputation"]))


## Cached precedence for [param agent]. An explicit belief still wins before this runs.
func group_precedence(agent: StringName) -> PackedStringArray:
	if _group_cache.has(agent):
		return _group_cache[agent] as PackedStringArray
	var listed := _adapter_groups(agent)
	var ordered := listed
	if _group_order.is_valid():
		ordered = _as_groups(_group_order.call(agent, listed))
	_group_cache[agent] = ordered
	return ordered


func host_functions() -> Dictionary:
	return _functions


func function_table() -> Dictionary:
	return _ctx.funcs()


func start_new_game(seed_value: int) -> void:
	var _host_gate := _host_enter()
	_seed = seed_value
	_minutes = 0
	_slice_carry = 0
	_trace.clear()
	_streams.clear()
	if trace != null:
		trace.events.clear()
	_secrecy_warned.clear()
	facts.clear_values()
	_group_cache.clear()
	_clear_belief_cache()
	deeds.clear()
	social.clear_state()
	if rumors != null:
		rumors.clear_flight()
	if publish != null:
		publish.clear()
	roles.clear()
	roles.drop_cast_index()
	if topics != null:
		topics.clear()
	if documents != null:
		documents.clear()
	_reset_event_memory()
	_arm_queue()
	_reset_play()
	roles.note_started()
	if generator != null:
		generator.clear()
	_clear_generation_scope()
	if storylets != null:
		storylets.set_seed(_seed)
	if ai != null:
		ai.drop_pending(&"new_game")
		ai.clear_cache()


func game_seed() -> int:
	return _seed


func play_minutes() -> int:
	return _minutes


func restore_clock(seed_value: int, minutes: int) -> void:
	_seed = seed_value
	_minutes = maxi(minutes, 0)
	if storylets != null:
		storylets.set_seed(_seed)


func rng_stream(name: StringName) -> WyrdRng:
	var key := String(name)
	if not _streams.has(key):
		var created := WyrdRng.new()
		created.seed_with(_seed, WyrdRng.stream_id(name))
		_streams[key] = created
	return _streams[key] as WyrdRng


func draw_u32(name: StringName) -> int:
	var _host_gate := _host_enter()
	var value := rng_stream(name).next_u32()
	trace_add("draw", {"op": "u32", "stream": String(name), "value": value})
	return value


func export_rng() -> Dictionary:
	var out := {}
	var names: Array = _streams.keys()
	names.sort()
	for stream_name in names:
		out[String(stream_name)] = (_streams[stream_name] as WyrdRng).to_state()
	return out


func import_rng(data: Dictionary) -> bool:
	var built := {}
	for stream_name in data.keys():
		if not (data[stream_name] is Dictionary):
			return false
		var restored := WyrdRng.from_state(data[stream_name])
		if restored == null:
			return false
		built[String(stream_name)] = restored
	install_rng(built)
	return true


func now_minutes() -> int:
	var now := _minutes
	var clock := adapter(WyrdTimeAdapter)
	if clock is WyrdTimeAdapter:
		now = maxi(now, (clock as WyrdTimeAdapter).now_minutes())
	return now


func _warn_deprecated(id: String, table: Dictionary = {}) -> void:
	var use: Dictionary = WyrdDeprecations.TABLE
	if not table.is_empty():
		use = table
	WyrdDeprecations.warn_once(id, _deprecated_warned, use)


func _warn_deprecated_keywords(diagnostics: WyrdDiagnostics) -> void:
	if diagnostics == null:
		return
	WyrdDeprecations.warn_keywords(diagnostics.items, _deprecated_warned)


func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	var _host_gate := _host_enter()
	var report := WyrdLoadReport.new()
	if roles != null:
		roles.drop_cast_index()
	_content = null
	_hooks_by_verb = {}
	if generator != null:
		generator.clear()
	_clear_generation_scope()
	if coverage != null:
		coverage.bind(null)
	if storylets != null:
		storylets.bind(null)
	if sequences != null:
		sequences.bind(null)
	_flags = PackedByteArray()
	_always = PackedInt32Array()
	_queue.clear()
	_reset_play()
	facts.bind_schema(null)
	deeds.clear()
	social.clear_state()
	if rumors != null:
		rumors.clear_flight()
	if publish != null:
		publish.clear()
	roles.bind_content(null)
	roles.clear()
	if topics != null:
		topics.clear()
	if documents != null:
		documents.clear()
	if manifest == null:
		report.diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "missing content manifest", "", 1, 1)
		_warn_deprecated_keywords(report.diagnostics)
		return report
	var files := PackedStringArray()
	for listed in manifest.files:
		files.append(_resolve(listed))
	if files.is_empty():
		report.diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "content manifest has no files", manifest.resource_path, 1, 1)
		_warn_deprecated_keywords(report.diagnostics)
		return report
	var commands: WyrdCommandSchema = null
	var skip_note := false
	var note := manifest.resource_path
	if not note.is_empty():
		var read := WyrdPack.read_commands(note.get_base_dir() + "/wyrd_commands.json", report.diagnostics)
		commands = read["schema"] as WyrdCommandSchema
		skip_note = bool(read["skip_note"])
	var pack := WyrdPack.compile(
		files,
		String(manifest.pack_id),
		manifest.language_version,
		commands,
		report.diagnostics,
		note,
		skip_note
	)
	if report.diagnostics.has_errors():
		_warn_deprecated_keywords(report.diagnostics)
		return report
	_content = WyrdContent.from_pack(pack)
	if coverage != null:
		coverage.bind(_content)
	if storylets != null:
		storylets.bind(_content)
		storylets.set_seed(_seed)
	if sequences != null:
		sequences.bind(self)
	report.ok = true
	report.manifest_hash = _content.manifest_hash
	_index_deed_hooks()
	facts.bind_schema(_content.schema)
	roles.bind_content(_content)
	_reset_event_memory()
	_arm_queue()
	_reset_play()
	_warn_deprecated_keywords(report.diagnostics)
	return report


func content() -> WyrdContent:
	return _content


func tick(game_minutes: float) -> void:
	var _host_gate := _host_enter()
	if is_nan(game_minutes) or is_inf(game_minutes) or game_minutes < 0.0:
		push_error("Wyrd.tick: game minutes must be >= 0")
		return
	var shown: Variant = game_minutes
	if game_minutes == floor(game_minutes) and game_minutes <= 2147483647.0:
		shown = int(game_minutes)
	trace_add("tick", {"minutes": shown})
	if game_minutes == 0.0:
		_game_tick(0)
		return
	var units := int(round(game_minutes * float(WyrdScheduler.SLICE_UNITS_PER_MINUTE)))
	if units <= 0:
		return
	_slice_carry += units
	var length := 1
	if _config != null:
		length = maxi(_config.scheduler_tick_minutes, 1)
	var span := length * WyrdScheduler.SLICE_UNITS_PER_MINUTE
	var whole := int(_slice_carry / span)
	_slice_carry = _slice_carry % span
	for _step in whole:
		_game_tick(length)


## Units still waiting for the next whole game tick.
## Saved as [code]flight.scheduler.slice[/code] when it is not zero.
func slice_remainder_units() -> int:
	return _slice_carry


func set_slice_remainder(units: int) -> void:
	_slice_carry = maxi(units, 0)


func scheduler() -> WyrdScheduler:
	return _queue


func _game_tick(advance: int) -> void:
	if advance > 0:
		_minutes += advance
	if _config != null and _config.compact_after > 0 and deeds.size() >= _config.compact_after:
		deeds.compact()
	facts.refresh_poll(now_minutes())
	facts.decay_evidence(now_minutes())
	if advance > 0:
		_mark_calls(_DEED_CALLS)
	if not _always.is_empty():
		_queue.mark(_always)
	if sequences != null:
		sequences.on_tick()
	_run_scheduler()
	if quests != null:
		quests.expire_due(now_minutes())
		quests.on_tick()
	if dialogue != null:
		dialogue.on_tick()
	_apply_generations()


func _run_scheduler() -> void:
	if social != null:
		social.sync_cache()
	var budget := 0
	var weights := PackedInt32Array([0, 0, 0, 0])
	var threshold := 0
	if _config != null:
		budget = maxi(_config.scheduler_work_per_tick, 0)
		weights = PackedInt32Array([
			_config.scheduler_share_waits,
			_config.scheduler_share_rumor,
			_config.scheduler_share_publish,
			_config.scheduler_share_cache,
			_config.scheduler_share_generate,
			_config.scheduler_share_ai_prefetch,
		])
		threshold = _config.scheduler_frame_warn_usec
	if rumors != null:
		rumors.enqueue_due()
	if publish != null:
		publish.enqueue_due()
	if ai != null:
		ai.tick_prefetch(now_minutes(), _queue)
	var debug := OS.is_debug_build()
	var started := 0
	if debug:
		started = Time.get_ticks_usec()
	var report := _queue.run(budget, weights, Callable(self, &"_recheck"))
	if not debug or threshold <= 0 or int(report.get("total", 0)) <= 0:
		return
	var elapsed := Time.get_ticks_usec() - started
	if elapsed <= threshold:
		return
	var carry := 0
	var left: Variant = report.get("carry", PackedInt32Array())
	if left is PackedInt32Array:
		for count in left as PackedInt32Array:
			carry += int(count)
	carry += int(report.get("generate_carry", 0))
	carry += int(report.get("ai_prefetch_carry", 0))
	_trace_scheduler({
		"carry": carry,
		"key": "frame",
		"queue": "frame",
		"threshold": threshold, "timing": true,
		"units": int(report.get("total", 0)),
		"us": elapsed,
	})


func condition_count() -> int:
	if _content == null:
		return 0
	return _content.conditions.size()


func condition_flags() -> PackedByteArray:
	return _flags.duplicate()


func eval_condition(index: int) -> bool:
	return _eval_at(index)


func content_schema() -> WyrdFactSchema:
	if _content == null:
		return null
	return _content.schema


func eval_value(cond: WyrdCompiledCondition) -> Variant:
	if cond == null:
		return null
	var index := -1
	if _content != null:
		index = _content.index_of(cond)
	if index >= 0:
		_ctx.record_id = _content.records[index]
		_ctx.site = _content.sites[index]
		var instance := scope_instance()
		if instance != "" and _record_is_template(_ctx.record_id, instance):
			_ctx.record_id = instance
	else:
		_ctx.record_id = ""
		_ctx.site = ""
	return _rpn.eval(cond, _locals, _ctx.funcs())


func eval_bool(cond: WyrdCompiledCondition) -> bool:
	return eval_value(cond) == true


## Storylet [code]when[/code] is not in the tick queue, so [code]chance[/code] would
## otherwise roll on an empty record. The site is [code]when[/code].
func eval_storylet(cond: WyrdCompiledCondition, storylet_id: String) -> bool:
	if cond == null:
		return true
	push_scope("")
	var saved_id := _ctx.record_id
	var saved_site := _ctx.site
	_ctx.record_id = storylet_id
	_ctx.site = "when"
	var result: Variant = _rpn.eval(cond, {}, _ctx.funcs())
	_ctx.record_id = saved_id
	_ctx.site = saved_site
	pop_scope()
	return result == true


func eval_with_locals(cond: WyrdCompiledCondition, locals: Dictionary) -> bool:
	var saved := _locals.duplicate()
	_locals = locals.duplicate()
	var ok := eval_bool(cond)
	_locals = saved
	return ok


func eval_value_with_locals(cond: WyrdCompiledCondition, locals: Dictionary) -> Variant:
	var saved := _locals.duplicate()
	_locals = locals.duplicate()
	var value: Variant = eval_value(cond)
	_locals = saved
	return value


## Pushes a quest id. An empty id hides any instance scope above it.
func push_scope(quest_id: String) -> void:
	_scope.append(quest_id)


func pop_scope() -> void:
	if _scope.is_empty():
		return
	_scope.remove_at(_scope.size() - 1)


## The top id when it is [code]<template>#<n>[/code]. Empty for a hand-written quest or an empty push.
func scope_instance() -> String:
	if _scope.is_empty():
		return ""
	var top := _scope[_scope.size() - 1]
	if top.contains("#"):
		return top
	return ""


func defer_instance_waits() -> bool:
	return _defer_waits


## Provisional casts for a proposal that has not been created yet.
func begin_provisional(instance_id: String) -> void:
	_provisional_scope = instance_id
	_provisional_casts = {}
	_provisional_params = {}


func provisional_cast(slot_name: String, entity: StringName) -> void:
	_provisional_casts[slot_name] = entity


func provisional_param(param_name: String, entity: StringName) -> void:
	_provisional_params[param_name] = entity


func end_provisional() -> void:
	_provisional_scope = ""
	_provisional_casts = {}
	_provisional_params = {}


## The instance cast or param, or null when [param name] is not one of this template's.
func scoped_holder(name: StringName) -> Variant:
	var scope := scope_instance()
	if scope == "" or _content == null:
		return null
	var quest := _content.quest_def(scope)
	if quest == null:
		return null
	var text := String(name)
	if _declares_slot(quest, text):
		if _provisional_scope == scope and _provisional_casts.has(text):
			return _provisional_casts[text]
		if roles == null:
			return &""
		return roles.slot_holder(scope, name)
	if quest is WyrdTemplateDef and _declares_param(quest as WyrdTemplateDef, text):
		if _provisional_scope == scope and _provisional_params.has(text):
			return _provisional_params[text]
		if quests == null:
			return &""
		return quests.param_entity(scope, text)
	return null


## Slot state for a template slot, or [code]default[/code]/[code]empty[/code] for a bound param.
## Null when the name is neither on this template.
func scoped_slot_state(name: StringName) -> Variant:
	var scope := scope_instance()
	if scope == "" or _content == null:
		return null
	var quest := _content.quest_def(scope)
	if quest == null:
		return null
	var text := String(name)
	if _declares_slot(quest, text):
		if roles == null:
			return &""
		return roles.slot_state(name, scope)
	if quest is WyrdTemplateDef and _declares_param(quest as WyrdTemplateDef, text):
		var entity: StringName = &""
		var held: Variant = scoped_holder(name)
		if held != null:
			entity = StringName(str(held))
		return &"default" if entity != &"" else &"empty"
	return null


func trace_gen_line(kind: String, fields: Dictionary, line: String) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add(kind, fields)
	print(line)


func _declares_slot(quest: WyrdQuestDef, name: String) -> bool:
	if quest == null:
		return false
	for slot in quest.slots:
		if slot.name == name:
			return true
	return false


func _declares_param(template: WyrdTemplateDef, name: String) -> bool:
	if template == null:
		return false
	for param in template.params:
		if param.name == name:
			return true
	return false


func _record_is_template(record: String, instance: String) -> bool:
	var mark := instance.find("#")
	if mark <= 0:
		return false
	var template_id := instance.substr(0, mark)
	if record == template_id:
		return true
	return record.begins_with(template_id + ".")


func _clear_generation_scope() -> void:
	_scope.clear()
	end_provisional()
	_defer_waits = false


func _apply_generations() -> void:
	if generator == null:
		return
	_defer_waits = true
	var batch: Array = generator.pending_creations()
	for item in batch:
		if item is WyrdProposal:
			generator.accept(item)
	generator.finish_reservations()
	_defer_waits = false


func _on_generate(entry: Dictionary) -> void:
	if generator == null:
		return
	generator.fulfill(entry)


func _trace_role(kind: String, fields: Dictionary) -> void:
	if kind == "slot_state":
		_trace_slot(fields)
		return
	if kind == "succession":
		_trace_succession(fields)
		return
	if kind == "cast":
		_trace_cast(fields)
		return
	if kind == "role_assign" or kind == "role_vacate":
		_trace_role_change(kind, fields)
		return
	trace_add(kind, fields)
	if trace == null or not trace.enabled:
		return
	var flag := "true" if bool(fields.get("ok", false)) else "false"
	print("wyrd %s role=%s entity=%s ok=%s" % [kind, str(fields.get("role", "")), str(fields.get("entity", "")), flag])


func _trace_slot(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var key := "%s\t%s" % [str(fields.get("quest", "")), str(fields.get("slot", ""))]
	var token := "%s\t%s" % [str(fields.get("state", "")), str(fields.get("reason", ""))]
	if str(_slot_traced.get(key, "")) == token:
		return
	_slot_traced[key] = token
	trace_add("slot_state", fields)
	if str(fields.get("kind", "")) != "":
		print(
			"wyrd slot_state quest=%s kind=%s slot=%s state=%s reason=%s"
			% [
				str(fields.get("quest", "")),
				str(fields.get("kind", "")),
				str(fields.get("slot", "")),
				str(fields.get("state", "")),
				str(fields.get("reason", "")),
			]
		)
		return
	print(
		"wyrd slot_state quest=%s role=%s slot=%s state=%s reason=%s"
		% [
			str(fields.get("quest", "")),
			str(fields.get("role", "")),
			str(fields.get("slot", "")),
			str(fields.get("state", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_cast(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("cast", fields)
	if str(fields.get("kind", "")) != "":
		print(
			"wyrd cast quest=%s slot=%s kind=%s entity=%s reason=%s"
			% [
				str(fields.get("quest", "")),
				str(fields.get("slot", "")),
				str(fields.get("kind", "")),
				str(fields.get("entity", "")),
				str(fields.get("reason", "")),
			]
		)
		return
	print(
		"wyrd cast quest=%s role=%s slot=%s entity=%s reason=%s"
		% [
			str(fields.get("quest", "")),
			str(fields.get("role", "")),
			str(fields.get("slot", "")),
			str(fields.get("entity", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_succession(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("succession", fields)
	print(
		"wyrd succession role=%s strategy=%s from=%s to=%s reason=%s"
		% [
			str(fields.get("role", "")),
			str(fields.get("strategy", "")),
			str(fields.get("from", "")),
			str(fields.get("to", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_belief(fields: Dictionary) -> void:
	_clear_belief_cache()
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var op := str(fields.get("op", ""))
	var perspective := "held" if op == "declare" or op == "retract" else "believed"
	var shown := "" if fields.get("value") == null else str(fields.get("value"))
	var row := {
		"key": str(fields.get("key", "")),
		"op": op,
		"perspective": perspective,
		"value": shown,
		"who": str(fields.get("who", "")),
	}
	trace_add("belief", row)
	print(
		"wyrd belief op=%s perspective=%s who=%s key=%s value=%s"
		% [row["op"], row["perspective"], row["who"], row["key"], row["value"]]
	)


func _trace_knowledge(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var shown := "" if fields.get("value") == null else str(fields.get("value"))
	var row := {
		"key": str(fields.get("key", "")),
		"op": str(fields.get("op", "")),
		"perspective": "known",
		"value": shown,
		"who": str(fields.get("who", "")),
	}
	trace_add("knowledge", row)
	print(
		"wyrd knowledge op=%s perspective=%s who=%s key=%s value=%s"
		% [row["op"], row["perspective"], row["who"], row["key"], row["value"]]
	)


## Remembers the fact a deed is about to reveal, so each perception line can name it.
func perception_claim(key: String, value: Variant) -> void:
	_perception_key = key
	_perception_value = value


func clear_perception_claim() -> void:
	_perception_key = ""
	_perception_value = null


## One line per listener, including a rejection. [param who] is the listener.
func trace_credibility(
	listener: StringName,
	speaker: StringName,
	verb: StringName,
	key: String,
	value: Variant,
	score: float,
	accepted: bool
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"accepted": "true" if accepted else "false",
		"key": key,
		"listener": String(listener),
		"score": _score_text(score),
		"speaker": String(speaker),
		"value": shown,
		"verb": String(verb),
		"who": String(listener),
	}
	if not _trace_allows(fields):
		return
	trace_add("credibility", fields)
	print(
		"wyrd credibility listener=%s speaker=%s verb=%s key=%s value=%s score=%s accepted=%s"
		% [
			fields["listener"],
			fields["speaker"],
			fields["verb"],
			fields["key"],
			fields["value"],
			fields["score"],
			fields["accepted"],
		]
	)


func _on_compact(info: Dictionary) -> void:
	if int(info.get("before", 0)) != int(info.get("after", 0)):
		_mark_calls(_DEED_CALLS)
	if effects != null:
		var compacted: Dictionary = effects.compact_provenance()
		_trace_choice_compact(compacted)
	if trace == null or not trace.enabled:
		return
	var fields := {
		"after": int(info.get("after", 0)),
		"before": int(info.get("before", 0)),
		"dropped": int(info.get("dropped", 0)),
		"merged": int(info.get("merged", 0)),
	}
	if not _trace_allows(fields):
		return
	trace_add("compact", fields)
	print(
		"wyrd compact before=%s after=%s merged=%s dropped=%s"
		% [str(fields["before"]), str(fields["after"]), str(fields["merged"]), str(fields["dropped"])]
	)


func _enqueue_cache(token: String) -> void:
	_queue.push("cache_refresh", token)


func _enqueue_rumor(token: String) -> void:
	_queue.push("rumor", token)


func _enqueue_publish(token: String) -> void:
	_queue.push("publish", token)


## Deed rows any current member of [param group] witnessed at or after [param since].
## [param filter] empty keeps every verb. See [method WyrdPublish.deeds_known_to].
func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array:
	if publish == null:
		return []
	return publish.deeds_known_to(group, since, filter)


func _tracing_on() -> bool:
	return trace != null and trace.enabled


func _trace_publish_cursor(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("publish_cursor", fields)
	print(
		"wyrd publish cursor document=%s issue=%s phase=%s rows=%d budget=%d"
		% [
			str(fields.get("document", "")),
			str(fields.get("issue", "")),
			str(fields.get("phase", "")),
			int(fields.get("rows", 0)),
			int(fields.get("budget", 0)),
		]
	)


func _trace_publish(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("publish", fields)
	print(
		"wyrd publish document=%s issue=%s deeds=%d"
		% [str(fields.get("document", "")), str(fields.get("issue", "")), int(fields.get("deeds", 0))]
	)


func _trace_rumor(kind: String, fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if kind == "rumor_adopt":
		fields["score"] = _score_text(float(fields.get("score", 0.0)))
	if kind == "rumor_materialize":
		fields["chance"] = _score_text(float(fields.get("chance", 0.0)))
	if not _trace_allows(fields):
		return
	trace_add(kind, fields)
	if kind == "rumor_hop":
		print(
			"wyrd rumor hop deed=%s policy=%s from=%s to=%s hop=%d key=%s taken=%s reason=%s"
			% [
				str(fields.get("deed", "")),
				str(fields.get("path", "")),
				str(fields.get("from", "")),
				str(fields.get("to", "")),
				int(fields.get("hop", 0)),
				str(fields.get("key", "")),
				str(fields.get("taken", "")),
				str(fields.get("reason", "")),
			]
		)
	elif kind == "rumor_adopt":
		print(
			"wyrd rumor adopt listener=%s speaker=%s policy=%s key=%s score=%s accepted=%s"
			% [
				str(fields.get("listener", "")),
				str(fields.get("speaker", "")),
				str(fields.get("path", "")),
				str(fields.get("key", "")),
				str(fields.get("score", "")),
				str(fields.get("accepted", "")),
			]
		)
	elif kind == "rumor_reach":
		print(
			"wyrd rumor reach deed=%s place=%s policy=%s level=%d key=%s"
			% [
				str(fields.get("deed", "")),
				str(fields.get("place", "")),
				str(fields.get("path", "")),
				int(fields.get("level", 0)),
				str(fields.get("key", "")),
			]
		)
	elif kind == "rumor_mutate":
		print(
			"wyrd rumor mutate listener=%s speaker=%s policy=%s field=%s hop=%d kept=%s result=%s value=%s"
			% [
				str(fields.get("listener", "")),
				str(fields.get("speaker", "")),
				str(fields.get("path", "")),
				str(fields.get("field", "")),
				int(fields.get("hop", 0)),
				str(fields.get("kept", "")),
				str(fields.get("result", "")),
				str(fields.get("value", "")),
			]
		)
	elif kind == "rumor_materialize":
		print(
			"wyrd rumor materialize listener=%s place=%s policy=%s key=%s level=%d chance=%s accepted=%s"
			% [
				str(fields.get("listener", "")),
				str(fields.get("place", "")),
				str(fields.get("path", "")),
				str(fields.get("key", "")),
				int(fields.get("level", 0)),
				str(fields.get("chance", "")),
				str(fields.get("accepted", "")),
			]
		)


func _trace_social_cache(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("social_cache", fields)
	print(
		"wyrd social cache event=%s kind=%s who=%s key=%s bucket=%d entries=%d"
		% [
			str(fields.get("event", "")),
			str(fields.get("cache", "")),
			str(fields.get("who", "")),
			str(fields.get("key", "")),
			int(fields.get("bucket", 0)),
			int(fields.get("entries", 0)),
		]
	)


func _trace_reputation(subject: StringName, group: StringName, value: float, members: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"group": String(group),
		"key": String(group),
		"members": members,
		"subject": String(subject),
		"value": value,
		"who": String(subject),
	}
	if not _trace_allows(fields):
		return
	trace_add("reputation", fields)
	print(
		"wyrd reputation subject=%s group=%s value=%s members=%s"
		% [fields["subject"], fields["group"], str(fields["value"]), str(fields["members"])]
	)


func trace_belief_lookup(agent: StringName, key: StringName, value: Variant, source: String) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"agent": String(agent),
		"key": String(key),
		"source": source,
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("belief_lookup", fields)
	print(
		"wyrd belief_lookup agent=%s key=%s value=%s source=%s"
		% [fields["agent"], fields["key"], fields["value"], fields["source"]]
	)


func trace_conflict(
	agent: StringName,
	key: StringName,
	hit: bool,
	source: String,
	value: Variant,
	against: String
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"against": against,
		"agent": String(agent),
		"conflicted": "true" if hit else "false",
		"key": String(key),
		"source": source,
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("conflict", fields)
	print(
		"wyrd conflict agent=%s key=%s conflicted=%s source=%s value=%s against=%s"
		% [fields["agent"], fields["key"], fields["conflicted"], fields["source"], fields["value"], fields["against"]]
	)


func _score_text(score: float) -> String:
	return "%.4f" % score


func _trace_allows(fields: Dictionary) -> bool:
	if trace == null or trace.prefix.is_empty():
		return true
	var prefix := trace.prefix
	for name in ["quest", "role", "slot", "who", "key", "scope", "speaker", "path", "instance", "template"]:
		var value := str(fields.get(name, ""))
		if value == prefix or value.begins_with(prefix):
			return true
	return false


func condition_dirty(index: int) -> bool:
	if index < 0:
		return false
	return _queue.is_dirty(index)


func condition_flag(index: int) -> int:
	if index < 0 or index >= _flags.size():
		return 0
	return int(_flags[index])


func locals_empty() -> bool:
	return _locals.is_empty()


func can_save() -> bool:
	return dialogue == null or dialogue.can_save()


func save_state() -> Dictionary:
	if not can_save():
		push_error("Wyrd.save_state: a scene is open")
		return {}
	return WyrdSave.capture(self)


func load_state(data: Dictionary) -> WyrdLoadReport:
	var _host_gate := _host_enter()
	var report: WyrdLoadReport
	if not can_save():
		push_error("Wyrd.load_state: a scene is open")
		report = WyrdLoadReport.new()
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_OPEN, "a scene is open", "", 1, 1)
		report.add_row("refused", "scene", "", "", 0, "E_SAVE_OPEN")
	else:
		var prepared := WyrdSave.check(self, data)
		report = prepared["report"]
		if prepared.has("doc"):
			# A refusal returns before these drops, so the runtime is unchanged.
			_drop_load_caches()
			WyrdSave.import_checked(self, prepared["doc"], prepared["streams"], report)
			_reset_event_memory()
			_clear_belief_cache()
	report.sort_rows()
	load_report_ready.emit(report)
	return report


func last_rechecks() -> int:
	return _queue.last_rechecks()


func watch_condition(index: int) -> void:
	_queue.watch(index)


func unwatch_condition(index: int) -> void:
	_queue.unwatch(index)


func note(row: Dictionary) -> void:
	_trace.append(row)


func _trace_scheduler(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("scheduler", fields)
	var queue := str(fields.get("queue", ""))
	if queue == "frame":
		print(
			"wyrd scheduler queue=frame units=%d carry=%d us=%d threshold=%d"
			% [
				int(fields.get("units", 0)),
				int(fields.get("carry", 0)),
				int(fields.get("us", 0)),
				int(fields.get("threshold", 0)),
			]
		)
		return
	print(
		"wyrd scheduler queue=%s units=%d carry=%d"
		% [queue, int(fields.get("units", 0)), int(fields.get("carry", 0))]
	)


func trace_add(kind: String, fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	trace.add(kind, fields)


## One line for an inspector read. Logged only when tracing is on.
func trace_debug_snapshot(fields: Dictionary, line: String) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("debug_snapshot", fields)
	print(line)


func trace_why_not(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("why_not", fields)
	print(WyrdDirector.format_why_not(fields))


## One line when [method WyrdQuestRunner.start] runs.
## [param reason] is [code]started[/code], [code]active[/code], [code]completed[/code],
## [code]failed[/code], [code]abandoned[/code], or [code]unavailable[/code].
func trace_quest_start(quest_id: String, ok: bool, reason: String) -> void:
	_trace_quest_line({
		"ok": "true" if ok else "false",
		"quest": quest_id,
		"reason": reason,
	}, "quest_start", "wyrd quest_start quest=%s ok=%s reason=%s" % [quest_id, "true" if ok else "false", reason])


## One line when [method WyrdQuestRunner.advance] accepts or refuses a move.
## [param reason] is [code]moved[/code], [code]not_active[/code], [code]same_stage[/code],
## [code]host_step[/code], or [code]scene_open[/code].
func trace_quest_advance(quest_id: String, from_stage: String, to_stage: String, ok: bool, reason: String) -> void:
	var flag := "true" if ok else "false"
	_trace_quest_line({
		"from": from_stage,
		"ok": flag,
		"quest": quest_id,
		"reason": reason,
		"to": to_stage,
	}, "quest_advance", "wyrd quest_advance quest=%s from=%s to=%s ok=%s reason=%s" % [quest_id, from_stage, to_stage, flag, reason])


## One line when [method WyrdQuestRunner.create_instance] creates or refuses an instance.
## [param ok] is stored as [code]true[/code] or [code]false[/code]. [param n] is the
## new counter, or 0 when nothing was created. Load does not call it.
func trace_ai_provider(provider_id: String, state: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {"id": provider_id, "state": state}
	if not _trace_allows(fields):
		return
	trace_add("ai_provider", fields)
	print("wyrd ai_provider id=%s state=%s" % [provider_id, state])


func trace_ai_request(request_id: int, kind: String, path: String, state: String, reason: String, key: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"id": request_id,
		"key": key,
		"kind": kind,
		"path": path,
		"reason": reason,
		"state": state,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_request", fields)
	var shown_path := path if not path.is_empty() else "-"
	print(
		"wyrd ai_request id=%d kind=%s path=%s state=%s reason=%s key=%s"
		% [request_id, kind, shown_path, state, reason, key]
	)


func trace_ai_result(request_id: int, kind: String, path: String, ok: bool, rule: String, key: String) -> void:
	if trace == null or not trace.enabled:
		return
	var flag := "true" if ok else "false"
	var fields := {
		"id": request_id,
		"key": key,
		"kind": kind,
		"ok": flag,
		"path": path,
		"rule": rule,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_result", fields)
	print("wyrd ai_result id=%d kind=%s ok=%s rule=%s key=%s" % [request_id, kind, flag, rule, key])


func trace_ai_cancel(request_id: int, kind: String, path: String, reason: String, key: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"id": request_id,
		"key": key,
		"kind": kind,
		"path": path,
		"reason": reason,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_cancel", fields)
	print("wyrd ai_cancel id=%d kind=%s reason=%s key=%s" % [request_id, kind, reason, key])


func trace_ai_packet_drop(path: String, fact: String, reason: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {"fact": fact, "path": path, "reason": reason}
	if not _trace_allows(fields):
		return
	trace_add("ai_packet_drop", fields)
	print("wyrd ai_packet_drop path=%s fact=%s reason=%s" % [path, fact, reason])


func trace_ai_validate(request_id: int, kind: String, path: String, ok: bool, rule: String, key: String) -> void:
	if trace == null or not trace.enabled:
		return
	var flag := "true" if ok else "false"
	var fields := {
		"id": request_id,
		"key": key,
		"kind": kind,
		"ok": flag,
		"path": path,
		"rule": rule,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_validate", fields)
	var shown := path if not path.is_empty() else "-"
	print("wyrd ai_validate id=%d kind=%s path=%s ok=%s rule=%s key=%s" % [request_id, kind, shown, flag, rule, key])


func trace_ai_cache(op: String, key: String, count: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {"count": count, "key": key, "op": op}
	if not _trace_allows(fields):
		return
	trace_add("ai_cache", fields)
	print("wyrd ai_cache op=%s key=%s count=%d" % [op, key, count])


func trace_ai_prefetch(source: String, path: String, lines: int, sent: int, cached: int, already: int, capped: int, skipped: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"cached": cached,
		"capped": capped,
		"lines": lines,
		"locale": skipped,
		"open": already,
		"path": path,
		"sent": sent,
		"source": source,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_prefetch", fields)
	print(
		"wyrd ai_prefetch source=%s path=%s lines=%d sent=%d cached=%d open=%d capped=%d locale=%d"
		% [source, path, lines, sent, cached, already, capped, skipped]
	)


func trace_ai_use(path: String, source: String, reason: String, key: String, kind: String = "bark_paraphrase") -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"key": key,
		"kind": kind,
		"path": path,
		"reason": reason,
		"source": source,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_use", fields)
	print("wyrd ai_use path=%s kind=%s source=%s reason=%s key=%s" % [path, kind, source, reason, key])


func trace_ai_late(request_id: int, path: String, reason: String, key: String) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := path if not path.is_empty() else "-"
	var fields := {
		"id": request_id,
		"key": key,
		"op": "forget",
		"path": path,
		"reason": reason,
	}
	if not _trace_allows(fields):
		return
	trace_add("ai_late", fields)
	print("wyrd ai_late op=forget id=%d path=%s reason=%s key=%s" % [request_id, shown, reason, key])


func trace_ai_sweep(op: String, count: int, reason: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {"count": count, "op": op, "reason": reason}
	if not _trace_allows(fields):
		return
	trace_add("ai_sweep", fields)
	print("wyrd ai_sweep op=%s count=%d reason=%s" % [op, count, reason])


func trace_ai_classifier(state: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {"state": state}
	if not _trace_allows(fields):
		return
	trace_add("ai_classifier", fields)
	print("wyrd ai_classifier state=%s" % state)


func _trace_gen_offer(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("gen_offer", fields)
	print(
		"wyrd gen_offer source=%s key=%s tier=%s origin=%s template=%s queued=%s replaced=%s"
		% [
			str(fields.get("source", "")),
			str(fields.get("key", "")),
			str(fields.get("tier", "")),
			str(fields.get("origin", "")),
			str(fields.get("template", "")),
			str(fields.get("queued", "")),
			str(fields.get("replaced", "")),
		]
	)


func _generate_has_work() -> bool:
	return generator != null and generator.generate_handler.is_valid() and generator.pending_count() > 0


func _generate_pending() -> int:
	if generator == null or not generator.generate_handler.is_valid():
		return 0
	return generator.pending_count()


func _generate_unit() -> void:
	if generator == null or not generator.generate_handler.is_valid():
		return
	var entry := generator.take_next()
	if entry.is_empty():
		return
	generator.generate_handler.call(entry)


func _ai_prefetch_has_work() -> bool:
	return ai != null and ai.prefetch_has_work()


func _ai_prefetch_unit() -> void:
	if ai != null:
		ai.prefetch_unit()


func _ai_prefetch_carry() -> int:
	if ai == null:
		return 0
	return ai.prefetch_carry()


func _index_deed_hooks() -> void:
	_hooks_by_verb = {}
	if _content == null:
		return
	var ids: Array = _content.templates.keys()
	ids.sort()
	for id in ids:
		var template: Variant = _content.templates[id]
		if not (template is WyrdTemplateDef):
			continue
		for hook in (template as WyrdTemplateDef).deed_hooks:
			if hook.verb.is_empty():
				continue
			if not _hooks_by_verb.has(hook.verb):
				_hooks_by_verb[hook.verb] = []
			(_hooks_by_verb[hook.verb] as Array).append({"hook": hook, "template": String(id)})


func _offer_from_deed(deed: Dictionary) -> void:
	if generator == null or _hooks_by_verb.is_empty():
		return
	var verb := String(deed.get("verb", ""))
	if verb.is_empty() or not _hooks_by_verb.has(verb):
		return
	for row in _hooks_by_verb[verb]:
		var hook: WyrdDeedHookDef = row["hook"]
		if hook.where_cond != null:
			var locals := {
				"deed.actor": deed.get("actor", &""),
				"deed.magnitude": float(deed.get("magnitude", 0.0)),
				"deed.place": deed.get("place", &""),
				"deed.target": deed.get("target", &""),
			}
			push_scope("")
			var matched := eval_with_locals(hook.where_cond, locals)
			pop_scope()
			if not matched:
				continue
		generator.queue_deed(str(row["template"]), str(int(deed.get("id", 0))), {
			"actor": deed.get("actor", &""),
			"deed": int(deed.get("id", 0)),
			"place": deed.get("place", &""),
			"target": deed.get("target", &""),
			"verb": deed.get("verb", &""),
		})


func trace_gen_create(template: String, instance: String, n: int, ok: bool, reason: String) -> void:
	var flag := "true" if ok else "false"
	_trace_quest_line({
		"instance": instance,
		"n": n,
		"ok": flag,
		"reason": reason,
		"template": template,
	}, "gen_create", "wyrd gen_create template=%s instance=%s n=%s ok=%s reason=%s" % [template, instance, n, flag, reason])


## One line for every status change in [method WyrdQuestRunner._set_status]. Load does not call it.
func trace_quest_status(quest_id: String, from_status: String, to_status: String) -> void:
	_trace_quest_line({
		"from": from_status,
		"quest": quest_id,
		"to": to_status,
	}, "quest_status", "wyrd quest_status quest=%s from=%s to=%s" % [quest_id, from_status, to_status])


func _trace_role_change(kind: String, fields: Dictionary) -> void:
	var line := "wyrd %s role=%s from=%s to=%s ok=%s reason=%s" % [
		kind,
		str(fields.get("role", "")),
		str(fields.get("from", "")),
		str(fields.get("to", "")),
		str(fields.get("ok", "")),
		str(fields.get("reason", "")),
	]
	_trace_quest_line(fields, kind, line)


## One line for [method WyrdSocial.adjust_baseline]. [code]who[/code] is [param a].
## Load does not call it.
## One line for [method WyrdTopics.unlock] or [method WyrdTopics.lock].
## [param kind] is [code]topic_unlock[/code] or [code]topic_lock[/code].
func trace_topic(kind: String, fields: Dictionary) -> void:
	var topic := str(fields.get("topic", ""))
	var ok := str(fields.get("ok", ""))
	var reason := str(fields.get("reason", ""))
	var line := ""
	if kind == "topic_unlock":
		line = "wyrd topic_unlock topic=%s ok=%s reason=%s" % [topic, ok, reason]
	elif kind == "topic_lock":
		line = "wyrd topic_lock topic=%s ok=%s reason=%s" % [topic, ok, reason]
	else:
		return
	_trace_quest_line(fields, kind, line)


## One line for [method WyrdSceneRunner.ask_topic]. Load does not call it.
func trace_topic_ask(npc: String, topic: String, storylet_id: String, ok: bool, reason: String) -> void:
	var flag := "true" if ok else "false"
	_trace_quest_line({
		"key": topic,
		"ok": flag,
		"reason": reason,
		"scope": storylet_id,
		"speaker": npc,
	}, "topic_ask", "wyrd topic_ask npc=%s topic=%s storylet=%s ok=%s reason=%s" % [npc, topic, storylet_id, flag, reason])


## One line for [method WyrdSceneRunner.open]. Logged only when tracing is on.
func trace_topic_open(npc: String, count: int) -> void:
	_trace_quest_line({
		"speaker": npc,
	}, "topic_open", "wyrd topic_open npc=%s topics=%d" % [npc, count])


## One line for a choice skill check. [code]key[/code] is the skill and [code]path[/code] is the scene id.
## Logged only when tracing is on. Load does not call it. Replay skips the row.
func trace_skill_check(scene_id: String, choice_id: String, skill: String, roll: float, ok: bool, reason: String) -> void:
	var flag := "true" if ok else "false"
	var shown := reason if not reason.is_empty() else "-"
	_trace_quest_line({
		"choice": choice_id,
		"key": skill,
		"ok": flag,
		"path": scene_id,
		"reason": shown,
		"roll": _score_text(roll),
		"scene": scene_id,
		"skill": skill,
	}, "skill_check", "wyrd skill_check scene=%s choice=%s skill=%s roll=%s ok=%s reason=%s" % [
		scene_id, choice_id, skill, _score_text(roll), flag, shown,
	])


## One line for a storylet or scene-line effect. [param source] is [code]storylet[/code] or [code]scene[/code].
func trace_effect_run(source: String, id: String, kind: String) -> void:
	_trace_quest_line({
		"effect": kind,
		"id": id,
		"scope": id,
		"source": source,
	}, "effect_run", "wyrd effect_run source=%s id=%s kind=%s" % [source, id, kind])


func trace_baseline_adjust(fields: Dictionary) -> void:
	var line := "wyrd baseline_adjust a=%s b=%s axis=%s from=%s to=%s ok=%s reason=%s" % [
		str(fields.get("a", "")),
		str(fields.get("b", "")),
		str(fields.get("axis", "")),
		str(fields.get("from", "")),
		str(fields.get("to", "")),
		str(fields.get("ok", "")),
		str(fields.get("reason", "")),
	]
	_trace_quest_line(fields, "baseline_adjust", line)


func _trace_quest_line(fields: Dictionary, kind: String, line: String) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add(kind, fields)
	print(line)


## One line when a region's active stage changes. [param path] is the region id,
## or parent ids joined by [code]/[/code]. Empty [param from_stage] is the first leaf.
func trace_region(quest_id: String, path: String, from_stage: String, to_stage: String) -> void:
	if trace == null or not trace.enabled or from_stage == to_stage:
		return
	var fields := {
		"from": from_stage,
		"path": path,
		"quest": quest_id,
		"to": to_stage,
	}
	if not _trace_allows(fields):
		return
	trace_add("region", fields)
	print("wyrd region quest=%s path=%s from=%s to=%s" % [quest_id, path, from_stage, to_stage])


## One line when a holder-variant line is shown.
## [param line_id] is the name-free line. [param chosen_id] is the variant, or the same line.
func trace_voice(line_id: String, holder_id: String, chosen_id: String) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"chosen": chosen_id,
		"holder": holder_id,
		"key": line_id,
		"who": holder_id,
	}
	if not _trace_allows(fields):
		return
	trace_add("voice", fields)
	print("wyrd voice line=%s holder=%s chosen=%s" % [line_id, holder_id, chosen_id])


## Picks a holder variant at display time. The choice is not saved.
## A line with no [code]{holder|variants}[/code] span is rendered as written.
func resolve_line(line_def: WyrdLineDef) -> Dictionary:
	var chosen := line_def
	var holder_id := ""
	if line_def != null and not line_def.variant_slot.is_empty():
		if roles != null:
			var slot_name := StringName(line_def.variant_slot)
			var scoped: Variant = scoped_holder(slot_name)
			var found: StringName = scoped if scoped != null else roles.holder(slot_name)
			if found != &"":
				holder_id = String(found)
		if not holder_id.is_empty():
			for item in line_def.variants:
				var variant := item as WyrdLineDef
				if variant != null and variant.holder == holder_id:
					chosen = variant
					break
		trace_voice(line_def.line_id, holder_id, chosen.line_id if chosen != null else "")
	var text := ""
	var tags := PackedStringArray()
	var id := ""
	if chosen != null:
		id = chosen.line_id
		tags = chosen.tags
		if dialogue != null:
			text = dialogue.render_prose(chosen.prose, chosen.line_id)
	return {"holder": holder_id, "id": id, "tags": tags, "text": text}


## One line when a sequence counts a step, finishes, resets, or expires.
## [param reason] is [code]step[/code], [code]done[/code], [code]reset[/code], or [code]expire[/code].
func trace_sequence(sequence_id: String, count: int, done: bool, reason: String) -> void:
	if trace == null or not trace.enabled:
		return
	var flag := "true" if done else "false"
	var fields := {
		"count": count,
		"done": flag,
		"id": sequence_id,
		"key": sequence_id,
		"reason": reason,
	}
	if not _trace_allows(fields):
		return
	trace_add("sequence", fields)
	print("wyrd sequence id=%s count=%s done=%s reason=%s" % [sequence_id, str(count), flag, reason])


## True when [param name] is empty or its place in [member WyrdConfig.secrecy_tiers]
## is at or below the unlocked fact. A name missing from that list is locked.
## The same unknown name is reported once until the next new game.
func secrecy_allows(name: String) -> bool:
	if name.is_empty():
		return true
	var index := _tier_index(name)
	if index < 0:
		if not _secrecy_warned.has(name):
			_secrecy_warned[name] = true
			push_error("Wyrd.secrecy: unknown tier \"%s\"" % name)
		return false
	return index <= _unlocked_index()


## The world fact named by [member WyrdConfig.secrecy_fact], or empty when it is unset.
func secrecy_unlocked_name() -> String:
	if _config == null or _config.secrecy_fact.is_empty() or facts == null:
		return ""
	var value: Variant = facts.get_in(StringName(_config.secrecy_fact))
	if value == null:
		return ""
	return str(value)


func _tier_index(name: String) -> int:
	if _config == null or name.is_empty():
		return -1
	for i in _config.secrecy_tiers.size():
		if _config.secrecy_tiers[i] == name:
			return i
	return -1


func _unlocked_index() -> int:
	return _tier_index(secrecy_unlocked_name())


## One line when a storylet or a line is dropped for secrecy.
## [param line_id] is empty when the whole storylet is dropped.
func trace_secrecy(storylet_id: String, line_id: String, tier: String, unlocked: String, scope: String = "", speaker: String = "") -> void:
	if trace == null or not trace.enabled:
		return
	var shown_line := line_id if not line_id.is_empty() else "-"
	var shown_story := storylet_id if not storylet_id.is_empty() else "-"
	var shown_tier := tier if not tier.is_empty() else "-"
	var shown_unlock := unlocked if not unlocked.is_empty() else "-"
	var fields := {
		"key": storylet_id if not storylet_id.is_empty() else line_id,
		"line": shown_line,
		"path": line_id,
		"scope": scope,
		"speaker": speaker,
		"storylet": shown_story,
		"tier": shown_tier,
		"unlocked": shown_unlock,
	}
	if not _trace_allows(fields):
		return
	trace_add("secrecy", fields)
	print("wyrd secrecy storylet=%s line=%s tier=%s unlocked=%s" % [shown_story, shown_line, shown_tier, shown_unlock])


## When the chosen holder line is above the unlock, the name-free line is used instead.
func apply_variant_secrecy(parent: WyrdLineDef, shown: Dictionary) -> Dictionary:
	var chosen_id := str(shown.get("id", ""))
	if parent == null or chosen_id.is_empty() or chosen_id == parent.line_id:
		return shown
	for item in parent.variants:
		var variant := item as WyrdLineDef
		if variant == null or variant.line_id != chosen_id:
			continue
		if variant.secrecy.is_empty() or secrecy_allows(variant.secrecy):
			return shown
		trace_secrecy("", variant.line_id, variant.secrecy, secrecy_unlocked_name(), "", parent.speaker)
		var text := ""
		if dialogue != null:
			text = dialogue.render_prose(parent.prose, parent.line_id)
		return {"holder": "", "id": parent.line_id, "tags": parent.tags, "text": text}
	return shown


## One line per scope-and-speaker match when [member WyrdConfig.trace_director] is set.
## Logged only while tracing is on. [code]path[/code] is the storylet id.
## [code]key[/code] is the scope id. Load does not log one.
func trace_director_candidate(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if _config == null or not _config.trace_director:
		return
	if not _trace_allows(fields):
		return
	trace_add("director_candidate", fields)
	print(WyrdDirector.format_candidate(fields))


## One line per index read. Logged only while tracing is on.
## [code]ids[/code] is the count the index returned, before secrecy, when, and cooldown.
## [code]key[/code] is the scope id, empty for a bark. Load does not log one.
## Replay skips it. A null index does not log one.
## One line per deed-index read from a snapshot section. Logged only while tracing is on.
## [code]scope[/code] is [code]deeds[/code], [code]social[/code], or [code]precedence[/code].
## [code]key[/code] is the caller prefix. [code]ids[/code] is the row count for deeds and
## social, or the agent-name count for precedence. Load does not log one.
## Replay skips it. A lookup that is off does not log one.
func trace_deed_index(scope_name: String, prefix: String, count: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"ids": count,
		"key": prefix,
		"scope": scope_name,
	}
	if not _trace_allows(fields):
		return
	trace_add("deed_index", fields)
	var shown := prefix
	if shown.is_empty():
		shown = "-"
	print("wyrd deed_index scope=%s key=%s ids=%d" % [scope_name, shown, count])


func trace_storylet_index(scope_text: String, scope_id: String, speaker: String, count: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"ids": count,
		"key": scope_id,
		"scope": scope_text,
		"speaker": speaker,
	}
	if not _trace_allows(fields):
		return
	trace_add("storylet_index", fields)
	var spoken := speaker
	if spoken.is_empty():
		spoken = "-"
	print("wyrd storylet_index scope=%s speaker=%s ids=%d" % [scope_text, spoken, count])


func trace_director(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("director", fields)
	var winner := str(fields.get("winner", ""))
	if winner.is_empty():
		winner = "-"
	var speaker := str(fields.get("speaker", ""))
	if speaker.is_empty():
		speaker = "-"
	print(
		"wyrd director scope=%s speaker=%s candidates=%s winner=%s score=%s"
		% [
			str(fields.get("scope", "")),
			speaker,
			str(fields.get("candidates", 0)),
			winner,
			str(fields.get("score", "-")),
		]
	)


func _on_resolved(key: String, value: Variant) -> void:
	trace_add("resolver", {"key": key, "value": value})


func trace_log() -> Array[Dictionary]:
	return _trace.duplicate()


## True when the loaded schema marks [param key] [code]recap[/code].
func fact_marked_recap(key: String) -> bool:
	if _content == null or _content.schema == null:
		return false
	var fact := _content.schema.lookup(key.split("."))
	return fact != null and fact.recap


## True when compaction should keep provenance for [param key].
## A missing schema keeps every row, so compaction does not guess.
func fact_is_recap(key: String) -> bool:
	if _content == null or _content.schema == null:
		return true
	return fact_marked_recap(key)


## One line for a choice-summary read. Logged only when tracing is on.
func _cover_draw(storylet_id: String, line_id: String) -> void:
	if coverage == null:
		return
	coverage.hit("storylet", storylet_id)
	if not line_id.is_empty():
		coverage.hit("line", line_id)


## One line for a coverage hit. Logged only when tracing is on.
func trace_coverage(kind: String, id: String, total: int, path: String, line_no: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"count": total,
		"hit": kind,
		"key": id,
		"line": line_no,
		"path": path,
	}
	if not _trace_allows(fields):
		return
	trace_add("coverage", fields)
	var shown := path if not path.is_empty() else "-"
	print("wyrd coverage kind=%s id=%s count=%d path=%s line=%d" % [kind, id, total, shown, line_no])


## One line for a never-hit report. Logged only when tracing is on.
func trace_coverage_report(missed: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"key": "",
		"missed": missed,
		"path": "",
	}
	if not _trace_allows(fields):
		return
	trace_add("coverage_report", fields)
	print("wyrd coverage report missed=%d" % missed)


func trace_choice_summary(fields: Dictionary, line: String) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("choice_summary", fields)
	print(line)


func _trace_choice_compact(compacted: Dictionary) -> void:
	var dropped := int(compacted.get("dropped", 0))
	if trace == null or not trace.enabled or dropped <= 0:
		return
	var names: Array = compacted.get("keys", [])
	var path := ",".join(names) if not names.is_empty() else "-"
	var fields := {
		"dropped": dropped,
		"kept": int(compacted.get("kept", 0)),
		"key": "",
		"path": path,
	}
	if not _trace_allows(fields):
		return
	trace_add("choice_compact", fields)
	print("wyrd choice_summary compact kept=%d dropped=%d" % [int(fields["kept"]), dropped])


func _reset_play() -> void:
	_slot_traced.clear()
	if storylets != null:
		storylets.clear()
	if sequences != null:
		sequences.clear()
	if effects != null:
		effects.clear()
	if dialogue != null:
		dialogue.force_close()
	if quests != null:
		quests.reset()


func _recheck(index: int) -> void:
	var value := _eval_at(index)
	if index >= 0 and index < _flags.size():
		_flags[index] = 1 if value else 0
	if value and quests != null:
		quests.note_ready(index)


func _eval_at(index: int) -> bool:
	if _content == null or index < 0 or index >= _content.conditions.size():
		return false
	_ctx.record_id = _content.records[index]
	_ctx.site = _content.sites[index]
	var result: Variant = _rpn.eval(_content.conditions[index], {}, _ctx.funcs())
	return result == true


func _arm_queue() -> void:
	_queue.clear()
	_always = PackedInt32Array()
	if _content == null:
		_flags = PackedByteArray()
		return
	_flags = PackedByteArray()
	_flags.resize(_content.conditions.size())
	_content.index_calls(_tracked_calls())
	for i in _content.conditions.size():
		_queue.watch(i)
		if _reads_per_query(_content.conditions[i]):
			_always.append(i)


func _reads_per_query(cond: WyrdCompiledCondition) -> bool:
	if cond == null or _content == null or _content.schema == null:
		return false
	for read in cond.reads:
		var fact := _content.schema.lookup(String(read).split("."))
		if fact != null and fact.invalidate == &"per_query":
			return true
	return false


func bind_locals(values: Dictionary) -> void:
	_locals = values.duplicate()


func clear_locals() -> void:
	_locals.clear()


func debug_dump() -> String:
	var lines := PackedStringArray()
	if events != null:
		lines.append(events.debug_dump())
	lines.append("dirty %d" % _queue.dirty_count())
	if _content != null and _content.schema != null:
		for fact in _content.schema.entries:
			if fact.origin != &"resolved":
				continue
			var view := facts.cache_view(fact.key)
			lines.append("cache %s %s %s" % [fact.key, str(view.get("mode", "")), str(view.get("event", ""))])
	return "\n".join(lines)


func _mark_keys(keys: PackedStringArray) -> void:
	if _content == null or _content.deps == null or keys.is_empty():
		return
	var names: Array[StringName] = []
	for key in keys:
		names.append(StringName(key))
	var hits := _content.deps.affected(names)
	_queue.mark(hits)
	if _collecting:
		for index in hits:
			_collected[int(index)] = true


func _on_batch(opening: bool) -> void:
	var _host_gate := _host_enter()
	if opening:
		_collecting = true
		_collected.clear()
		trace_add("batch_begin", {"time": now_minutes()})
		return
	var ran := _flush_collected()
	trace_add("batch_end", {"rechecks": _as_ints(ran), "time": now_minutes()})
	if quests != null:
		quests.on_tick()
	_collecting = false
	_collected.clear()


func _on_emit(event_name: StringName, payload: Dictionary) -> void:
	var _host_gate := _host_enter()
	var problem := _payload_problem(event_name, payload)
	var shown := _payload_strings(payload)
	if problem != "":
		push_error("Wyrd.events.emit: %s" % problem)
		trace_add("emit_rejected", {
			"name": String(event_name),
			"payload": shown,
			"reason": problem,
			"time": now_minutes(),
		})
		return
	var normalized := _normalize_payload(event_name, payload)
	_emit_seq += 1
	var emit_id := _emit_seq
	var owned := not _collecting
	if owned:
		_collecting = true
		_collected.clear()
	if event_name == _GROUPS_CHANGED:
		invalidate_groups()
	var keys := facts.invalidate_event(event_name)
	if events != null:
		events.last_keys = keys
		events.remember({
			"id": emit_id,
			"keys": _key_list(keys),
			"name": String(event_name),
			"payload": _payload_strings(normalized),
			"time": now_minutes(),
		})
	_apply_event_act(event_name, payload, normalized)
	if sequences != null:
		sequences.on_emit(event_name, normalized)
	if quests != null:
		quests.on_world_event(emit_id, event_name, normalized)
	_wake_spatial(event_name)
	var in_batch := events != null and events.batching()
	if in_batch or not owned:
		trace_add("emit", {
			"id": emit_id,
			"keys": keys,
			"name": String(event_name),
			"payload": normalized,
			"rechecks": [],
			"time": now_minutes(),
		})
		return
	var ran := _flush_collected()
	trace_add("emit", {
		"id": emit_id,
		"keys": keys,
		"name": String(event_name),
		"payload": normalized,
		"rechecks": _as_ints(ran),
		"time": now_minutes(),
	})
	if quests != null:
		quests.on_tick()
	_collecting = false
	_collected.clear()


## Writes [code]leaves[/code] evidence and one witness layer per mode.
## [code]saw[/code] learns the fact. [code]heard[/code] and [code]inferred[/code] believe it.
func _apply_event_act(event_name: StringName, payload: Dictionary, normalized: Dictionary) -> void:
	if _content == null or not _content.events.has(String(event_name)):
		return
	var event := _content.events[String(event_name)] as WyrdEventDef
	if event == null:
		return
	var key := event.leaves_key
	var value: Variant = null
	if not key.is_empty():
		value = event.leaves_value
		if event.leaves_kind == &"symbol":
			value = StringName(str(value))
		if not facts.set_in(StringName(key), value, &"world"):
			return
		value = facts.get_in(StringName(key), &"world")
		var until := -1
		if event.decays_minutes > 0:
			until = now_minutes() + event.decays_minutes
		facts.note_evidence(
			key,
			value,
			_event_place(normalized),
			until,
			event.name,
			_event_actor(normalized),
			_event_target(normalized)
		)
		_trace_evidence(event.name, key, value, until)
	if not _has_witnesses(payload):
		return
	for pair in _event_witnesses(payload, normalized):
		var who := pair["id"] as StringName
		var mode := pair["mode"] as StringName
		if key.is_empty():
			_trace_event_witness(who, mode, event.name, "", null)
			continue
		_write_event_witness(who, mode, event.name, key, value)


## A later spatial perceive of evidence still at [param place].
## The world fact and its deadline stay. [code]saw[/code] learns it. [code]heard[/code]
## and [code]inferred[/code] believe it.
func notice_evidence(observer: StringName, place: StringName) -> void:
	var spatial := adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
	for row in facts.evidence_rows():
		if String(row.get("place", "")) != String(place):
			continue
		var mode := &"saw"
		if spatial != null:
			mode = spatial.perceive(
				observer,
				StringName(str(row.get("actor", ""))),
				StringName(str(row.get("target", ""))),
				place
			)
		var mode_name := String(mode)
		if mode_name.is_empty():
			continue
		if not _witness_mode_ok(mode_name, "Wyrd.notice_evidence"):
			continue
		_write_event_witness(
			observer,
			StringName(mode_name),
			String(row.get("event", "")),
			String(row.get("key", "")),
			row.get("value")
		)


func _write_event_witness(
	who: StringName,
	mode: StringName,
	event_name: String,
	key: String,
	value: Variant
) -> void:
	var layer := "known" if String(mode) == "saw" else "believed"
	facts.set_in(StringName(key), value, StringName("%s/%s" % [layer, String(who)]))
	_trace_event_witness(who, mode, event_name, key, value)


func _event_witnesses(payload: Dictionary, normalized: Dictionary) -> Array:
	var spec: Variant = _witness_spec(payload)
	if spec is String or spec is StringName:
		if String(spec) == "auto":
			return _auto_witnesses(normalized)
		push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
		return []
	if spec is Array:
		var out: Array = []
		for item in spec:
			if not (item is Dictionary):
				push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
				continue
			var row: Dictionary = item
			var id_text := ""
			if row.has("id"):
				id_text = String(row["id"])
			elif row.has(&"id"):
				id_text = String(row[&"id"])
			var mode: Variant = null
			if row.has("mode"):
				mode = row["mode"]
			elif row.has(&"mode"):
				mode = row[&"mode"]
			if id_text.is_empty() or mode == null:
				push_error("Wyrd.events.emit: a witness needs id and mode")
				continue
			var mode_name := String(mode)
			if mode_name.is_empty():
				continue
			if not _witness_mode_ok(mode_name, "Wyrd.events.emit"):
				continue
			out.append({"id": StringName(id_text), "mode": StringName(mode_name)})
		return out
	push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
	return []


func _auto_witnesses(normalized: Dictionary) -> Array:
	var spatial := adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
	if spatial == null:
		return []
	var actor := StringName(_event_actor(normalized))
	var target := StringName(_event_target(normalized))
	var place := StringName(_event_place(normalized))
	var out: Array = []
	for observer in spatial.witnesses_of(actor, target, place):
		var mode := spatial.perceive(StringName(String(observer)), actor, target, place)
		var mode_name := String(mode)
		if mode_name.is_empty():
			continue
		if not _witness_mode_ok(mode_name, "Wyrd.events.emit"):
			continue
		out.append({"id": StringName(String(observer)), "mode": StringName(mode_name)})
	return out


func _witness_mode_ok(mode_name: String, site: String) -> bool:
	if mode_name == "saw" or mode_name == "heard" or mode_name == "inferred":
		return true
	push_error("%s: unknown witness mode \"%s\"" % [site, mode_name])
	return false


func _has_witnesses(payload: Dictionary) -> bool:
	return payload.has("witnesses") or payload.has(&"witnesses")


func _witness_spec(payload: Dictionary) -> Variant:
	if payload.has("witnesses"):
		return payload["witnesses"]
	return payload[&"witnesses"]


func _event_actor(payload: Dictionary) -> String:
	if payload.has("actor"):
		return String(payload["actor"])
	return ""


func _event_target(payload: Dictionary) -> String:
	if payload.has("target"):
		return String(payload["target"])
	if payload.has("object"):
		return String(payload["object"])
	return ""


func _event_place(payload: Dictionary) -> String:
	if payload.has("place"):
		return String(payload["place"])
	return _event_target(payload)


func _trace_event_witness(
	agent: StringName,
	mode: StringName,
	event_name: String,
	key: String,
	value: Variant
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := ""
	if value != null:
		shown = str(value)
	var fields := {
		"agent": String(agent),
		"event": event_name,
		"key": key,
		"mode": String(mode),
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("event_witness", fields)
	print(
		"wyrd event_witness agent=%s mode=%s event=%s key=%s value=%s"
		% [fields["agent"], fields["mode"], fields["event"], fields["key"], fields["value"]]
	)


func _trace_evidence(event_name: String, key: String, value: Variant, until: int) -> void:
	if trace == null or not trace.enabled:
		return
	var until_text := ""
	if until >= 0:
		until_text = str(until)
	var fields := {
		"event": event_name,
		"key": key,
		"until": until_text,
		"value": str(value),
		"who": "",
	}
	if not _trace_allows(fields):
		return
	trace_add("evidence", fields)
	print(
		"wyrd evidence event=%s key=%s value=%s until=%s"
		% [fields["event"], fields["key"], fields["value"], fields["until"]]
	)


func _flush_collected() -> PackedInt32Array:
	var indexes := PackedInt32Array()
	var pending: Array = _collected.keys()
	pending.sort()
	for key in pending:
		indexes.append(int(key))
	_collected.clear()
	var ran := _queue.recheck_some(indexes, Callable(self, &"_recheck"))
	if events != null:
		events.last_flush = ran.size()
		events.last_wave = 1
	return ran


func _reset_event_memory() -> void:
	_emit_seq = 0
	_collecting = false
	_collected.clear()
	_locals.clear()
	if events != null:
		events.reset_session()
	if quests != null:
		quests.clear_event_fires()


func _payload_problem(event_name: StringName, payload: Dictionary) -> String:
	if _content == null or not _content.events.has(String(event_name)):
		return "unknown event \"%s\"" % String(event_name)
	var event := _content.events[String(event_name)] as WyrdEventDef
	if event == null:
		return "unknown event \"%s\"" % String(event_name)
	var incoming := _payload_strings(payload)
	incoming.erase("witnesses")
	var declared := {}
	for field in event.fields:
		declared[str(field.get("name", ""))] = str(field.get("type", ""))
	var names: Array = incoming.keys()
	names.sort()
	for name in names:
		if not declared.has(String(name)):
			return "unknown field \"%s\"" % String(name)
		if not _field_ok(String(declared[String(name)]), incoming[name]):
			return "field \"%s\" is not %s" % [String(name), String(declared[String(name)])]
	var required: Array = declared.keys()
	required.sort()
	for name in required:
		if not incoming.has(String(name)):
			return "missing field \"%s\"" % String(name)
	return ""


func _normalize_payload(event_name: StringName, payload: Dictionary) -> Dictionary:
	var event := _content.events[String(event_name)] as WyrdEventDef
	var incoming := _payload_strings(payload)
	var out := {}
	if event == null:
		return out
	for field in event.fields:
		var name := str(field.get("name", ""))
		out[name] = _coerce_field(str(field.get("type", "")), incoming.get(name))
	return out


func _payload_strings(payload: Dictionary) -> Dictionary:
	var out := {}
	for key in payload.keys():
		out[String(key)] = payload[key]
	return out


func _field_ok(type_name: String, value: Variant) -> bool:
	match type_name:
		"bool":
			return value is bool
		"int":
			return typeof(value) == TYPE_INT
		"float":
			return value is float or typeof(value) == TYPE_INT
		"symbol":
			return value is String or value is StringName
		_:
			return false


func _coerce_field(type_name: String, value: Variant) -> Variant:
	if type_name == "symbol":
		return StringName(str(value))
	if type_name == "float" and typeof(value) == TYPE_INT:
		return float(value)
	return value


func _as_ints(values: PackedInt32Array) -> Array:
	var rows: Array = []
	for value in values:
		rows.append(int(value))
	return rows


func _key_list(keys: PackedStringArray) -> Array:
	var rows: Array = []
	for key in keys:
		rows.append(String(key))
	return rows


func loaded_fact_key() -> String:
	return _rpn.last_fact_key


func _on_deed(deed: Dictionary) -> void:
	_mark_calls(_DEED_CALLS)
	if rumors != null and not _perception_key.is_empty():
		rumors.note_deed(deed, _perception_key, _perception_value)
	_offer_from_deed(deed)


func _on_perceived(agent: StringName, mode: StringName, verb: StringName) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := ""
	if not _perception_key.is_empty() and _perception_value != null:
		shown = str(_perception_value)
	var fields := {
		"agent": String(agent),
		"key": _perception_key,
		"mode": String(mode),
		"value": shown,
		"verb": String(verb),
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("perception", fields)
	print(
		"wyrd perception agent=%s mode=%s verb=%s key=%s value=%s"
		% [fields["agent"], fields["mode"], fields["verb"], fields["key"], fields["value"]]
	)


func _on_role(_role: StringName, _old_holder: StringName, _new_holder: StringName) -> void:
	_mark_calls(_ROLE_CALLS)
	if _queue != null:
		_queue.marked = true


func _on_role_vacant(_role: StringName) -> void:
	_mark_calls(_ROLE_CALLS)
	if _queue != null:
		_queue.marked = true


func _on_social() -> void:
	_mark_calls(_DEED_CALLS)
	_mark_calls(PackedStringArray(["path_exists"]))


func _members(group: StringName) -> PackedStringArray:
	var world := adapter(WyrdWorldAdapter)
	if world is WyrdWorldAdapter:
		return (world as WyrdWorldAdapter).members(group)
	return PackedStringArray()


func _adapter_groups(agent: StringName) -> PackedStringArray:
	var world := adapter(WyrdWorldAdapter)
	if world is WyrdWorldAdapter:
		return (world as WyrdWorldAdapter).groups_of(agent)
	return PackedStringArray()


func _as_groups(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var rows := PackedStringArray()
	if value is Array:
		for item in value:
			if item != null:
				rows.append(String(item))
	return rows


func _mark_calls(names: PackedStringArray) -> void:
	if _content == null or names.is_empty():
		return
	var hits := _content.indexes_for_calls(names)
	if not hits.is_empty():
		_queue.mark(hits)


func note_has_read() -> void:
	_mark_calls(PackedStringArray(["has_read"]))
	if _content == null or not _collecting:
		return
	var hits := _content.indexes_for_calls(PackedStringArray(["has_read"]))
	for index in hits:
		_collected[int(index)] = true


func note_sequence_change() -> void:
	if _content == null:
		return
	var hits := _content.indexes_for_calls(PackedStringArray(["done", "progress"]))
	if hits.is_empty():
		return
	_queue.mark(hits)
	if _collecting:
		for index in hits:
			_collected[int(index)] = true


func note_instance_change() -> void:
	if _content == null:
		return
	var hits := _content.indexes_for_calls(PackedStringArray(["active_count"]))
	if hits.is_empty():
		return
	_queue.mark(hits)
	if _collecting:
		for index in hits:
			_collected[int(index)] = true


func _tracked_calls() -> PackedStringArray:
	var names := _DEED_CALLS.duplicate()
	for name in _ROLE_CALLS:
		if not names.has(name):
			names.append(name)
	if not names.has("progress"):
		names.append("progress")
	if not names.has("done"):
		names.append("done")
	if not names.has("path_exists"):
		names.append("path_exists")
	if not names.has("has_read"):
		names.append("has_read")
	if not names.has("active_count"):
		names.append("active_count")
	return names


func _clear_belief_cache() -> void:
	if _ctx != null:
		_ctx.clear_belief_cache()


func _on_rumor_reach(present: bool) -> void:
	if _ctx != null:
		_ctx.set_belief_reach(present)


## Speaker a bark will show: the holder of [code]story.speaker[/code] when one
## is assigned, otherwise [code]story.speaker[/code].
func bark_entity(story: WyrdStoryletDef) -> String:
	if story == null:
		return ""
	var entity := story.speaker
	if roles != null:
		var held := roles.holder(StringName(story.speaker))
		if held != &"":
			entity = String(held)
	return entity


func present_bark(story: WyrdStoryletDef, drawn: Dictionary) -> void:
	if story == null:
		return
	bark_ready.emit(_story_line_view(story, drawn, bark_entity(story)))


## A topic answer spoken by [param npc]. Does not emit [signal bark_ready].
func present_topic_line(story: WyrdStoryletDef, drawn: Dictionary, npc: String) -> WyrdLineView:
	return _story_line_view(story, drawn, npc)


func _story_line_view(story: WyrdStoryletDef, drawn: Dictionary, entity: String) -> WyrdLineView:
	var view := WyrdLineView.new()
	var line_id := str(drawn.get("line_id", ""))
	view.id = line_id
	view.speaker = StringName(entity)
	var shown := ""
	var world := _world()
	if world != null and view.speaker != &"":
		shown = world.display_name(view.speaker)
	view.display_name = shown if not shown.is_empty() else entity
	if roles != null:
		view.roles = roles.roles_of(view.speaker)
	var line_def: WyrdLineDef = null
	if _content != null and not line_id.is_empty():
		line_def = _content.lines.get(line_id) as WyrdLineDef
	if line_def != null:
		var picked := apply_variant_secrecy(line_def, resolve_line(line_def))
		view.id = str(picked["id"])
		view.tags = (picked["tags"] as PackedStringArray).duplicate()
		view.text = str(picked["text"])
		if dialogue != null:
			view.audio = dialogue.audio_for(view.id)
	if coverage != null and not view.id.is_empty() and view.id != line_id:
		coverage.hit("line", view.id)
	if ai != null:
		ai.present(view, view.id)
	return view


func _wake_spatial(event_name: StringName) -> void:
	if _content == null:
		return
	var hits := _content.spatial_waits(event_name)
	if hits.is_empty():
		return
	_queue.mark(hits)
	if not _collecting:
		return
	for index in hits:
		_collected[int(index)] = true


func _spatial() -> WyrdSpatialAdapter:
	var found := adapter(WyrdSpatialAdapter)
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _election() -> WyrdElectionAdapter:
	var found := adapter(WyrdElectionAdapter)
	if found is WyrdElectionAdapter:
		return found as WyrdElectionAdapter
	return null


func _world() -> WyrdWorldAdapter:
	var found := adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null


func _inventory_adapter() -> WyrdInventoryAdapter:
	var found := adapter(WyrdInventoryAdapter)
	if found is WyrdInventoryAdapter:
		return found as WyrdInventoryAdapter
	return null


func _resolver(head: String) -> Object:
	match head:
		"world":
			return adapter(WyrdWorldAdapter)
		"time":
			return adapter(WyrdTimeAdapter)
		"inventory":
			return adapter(WyrdInventoryAdapter)
		"spatial":
			return adapter(WyrdSpatialAdapter)
		"action":
			return adapter(WyrdActionAdapter)
		_:
			return null


func _signature_ok(sig: Dictionary, arg_types: Array, return_type: StringName) -> bool:
	if StringName(sig["return"]) != return_type:
		return false
	var params: Array = sig["params"]
	if arg_types.size() != params.size():
		return false
	for i in arg_types.size():
		var param: Dictionary = params[i]
		if StringName(str(arg_types[i])) != param["type"]:
			return false
	return true


## Fires once at the end of [method load_state], whether the load applied or was refused.
## [method load_content] does not emit it.
signal load_report_ready(report: WyrdLoadReport)


## Swaps in streams already built by the load check. Does not parse or refuse.
func install_rng(streams: Dictionary) -> void:
	var next := {}
	for stream_name in streams.keys():
		next[String(stream_name)] = streams[stream_name]
	_streams = next


func _drop_load_caches() -> void:
	if roles != null:
		roles.drop_cast_index()
	if generator != null:
		generator.clear()
	_clear_generation_scope()
	if ai != null:
		ai.drop_pending(&"load")
	_clear_belief_cache()


class _HostDepth extends RefCounted:
	var runtime: WyrdRuntime

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and runtime != null:
			runtime._host_depth -= 1
			runtime = null


func _host_enter() -> RefCounted:
	if trace == null or not trace.enabled:
		return null
	var gate := _HostDepth.new()
	gate.runtime = self
	_host_depth += 1
	return gate


## True only for the direct game call, and only while a row can be logged.
func _host_logs() -> bool:
	return _host_depth == 1


## Records one direct game call. Nested work is already above depth 0.
func _host_mark(call_name: String, args: Array) -> void:
	if _host_depth != 1:
		return
	trace_add("host_call", {"args": args, "call": call_name})


func _resolve(path: String) -> String:
	var text := path.replace("\\", "/")
	if text.begins_with("res://") or text.begins_with("user://") or text.begins_with("/"):
		return text
	return "res://" + text.trim_prefix("./")
