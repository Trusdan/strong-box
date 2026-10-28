## Facade over one runtime.
## Host calls, signals, and member objects are exposed here.
extends Node

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Facade over one [WyrdRuntime].
##
## The editor plugin does not register this script as an autoload.
## When it does, the autoload name is Wyrd, so this script has no class_name.
## [member facts], [member events], [member deeds], [member social], [member rumors], [member publish],
## [member roles], [member quests], [member dialogue], [member storylets],
## [member sequences], [member director], [member generator], [member ai], [member debug], and [member coverage] are the runtime's sub-objects. [member ai] is the AI hook and stays idle with the null provider. [member dialogue] is
## the scene runner. [member storylets] draws a line set. [member director]
## ranks one. [member topics] is the unlocked topic set. [member documents] opens a readable document.
## [signal bark_ready] repeats the runtime signal for a bark win.
## [signal topic_unlocked] and [signal topic_locked] repeat the topic store.
## [signal document_read] repeats a document open.
## [signal load_report_ready] repeats the runtime signal once per [method load_state].
## [signal scene_started] fires after a scene opens and before its first [signal line_ready].
## The other design-list signals are repeated here with the member object's arguments.

## Fires with the line when a bark wins.
signal bark_ready(line: WyrdLineView)
## Fires when a topic becomes unlocked.
signal topic_unlocked(topic: StringName)
## @experimental
signal topic_locked(topic: StringName)
## Fires when a document is opened.
signal document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool)
## Fires once at the end of a load, whether the load applied or was refused.
signal load_report_ready(report: WyrdLoadReport)
## Fires with the line the open scene is showing.
signal line_ready(line: WyrdLineView)
## Fires with the choices the open scene is showing.
signal choices_ready(choices: Array[WyrdChoiceView])
## Fires after a scene opens and before its first line.
signal scene_started(scene_id: String)
## Fires when a scene closes, with its status and reason.
signal scene_ended(scene_id: String, status: StringName, reason: StringName)
## Fires when a quest status changes.
signal quest_state_changed(quest_id: String, status: StringName)
## Fires when a quest enters a stage.
signal stage_changed(quest_id: String, stage_id: String)
## Fires when a quest outcome branch changes.
signal outcome_changed(quest_id: String, branch: StringName, value: StringName)
## Fires when a journal entry is written.
signal journal_entry_added(quest_id: String, entry_id: String, text: String)
## Fires when a role holder changes.
signal role_holder_changed(role_id: StringName, old_holder: StringName, new_holder: StringName)
## Fires when a role is left empty or abolished.
signal role_vacant(role_id: StringName)
## Fires when an election is waiting for a new holder.
signal election_needed(role_id: StringName, departed: StringName)
## Fires with the deed that was just stored.
signal deed_recorded(deed: Dictionary)
## Fires when a subscribed fact value changes.
signal fact_changed(key: StringName, old_value: Variant, new_value: Variant)
## Fires when a quest's required pack is missing.
signal content_unavailable(quest_id: String, pack_id: String)

## Fact store for this runtime.
var facts: WyrdFactStore
## Event entry for this runtime.
var events: WyrdEvents
## Deed log for this runtime.
var deeds: WyrdDeedLog
## @experimental
var social: WyrdSocial
## @experimental
var rumors: WyrdRumor
## @experimental
var publish: WyrdPublish
## Role bindings for this runtime.
var roles: WyrdRoles
## Unlocked topics for this runtime.
var topics: WyrdTopics
## Readable documents for this runtime.
var documents: WyrdDocuments
## Quest runner for this runtime.
var quests: WyrdQuestRunner
## Scene runner for this runtime.
var dialogue: WyrdSceneRunner
## @experimental
var storylets: WyrdStoryletDeck
## @experimental
var sequences: WyrdSequences
## @experimental
var director: WyrdDirector
## Story-pressure queue for this runtime.
var generator: WyrdGenerator
## AI hook for this runtime. It stays idle with the null provider.
var ai: WyrdAI
## @experimental
var trace: WyrdTrace
## @experimental
var debug: WyrdDebug
## @experimental
var coverage: WyrdCoverage

var _runtime: WyrdRuntime


func _init() -> void:
	_runtime = _Runtime.new()
	facts = _runtime.facts
	events = _runtime.events
	deeds = _runtime.deeds
	social = _runtime.social
	rumors = _runtime.rumors
	publish = _runtime.publish
	roles = _runtime.roles
	topics = _runtime.topics
	documents = _runtime.documents
	quests = _runtime.quests
	dialogue = _runtime.dialogue
	storylets = _runtime.storylets
	sequences = _runtime.sequences
	director = _runtime.director
	generator = _runtime.generator
	ai = _runtime.ai
	trace = _runtime.trace
	debug = _runtime.debug
	coverage = _runtime.coverage
	_runtime.bark_ready.connect(_relay_bark)
	_runtime.load_report_ready.connect(_relay_load_report)
	if topics != null:
		topics.topic_unlocked.connect(_relay_topic_unlocked)
		topics.topic_locked.connect(_relay_topic_locked)
	if documents != null:
		documents.document_read.connect(_relay_document_read)
	if dialogue != null:
		dialogue.line_ready.connect(_relay_line_ready)
		dialogue.choices_ready.connect(_relay_choices_ready)
		dialogue.scene_started.connect(_relay_scene_started)
		dialogue.scene_ended.connect(_relay_scene_ended)
	if quests != null:
		quests.quest_state_changed.connect(_relay_quest_state_changed)
		quests.stage_changed.connect(_relay_stage_changed)
		quests.journal_entry_added.connect(_relay_journal_entry_added)
		quests.content_unavailable.connect(_relay_content_unavailable)
	if roles != null:
		roles.role_holder_changed.connect(_relay_role_holder_changed)
		roles.role_vacant.connect(_relay_role_vacant)
		roles.election_needed.connect(_relay_election_needed)
	if deeds != null:
		deeds.deed_recorded.connect(_relay_deed_recorded)
	if facts != null:
		facts.fact_changed.connect(_relay_fact_changed)
	if _runtime.effects != null:
		_runtime.effects.outcome_changed.connect(_relay_outcome_changed)


func _relay_bark(line: WyrdLineView) -> void:
	bark_ready.emit(line)


func _relay_load_report(report: WyrdLoadReport) -> void:
	load_report_ready.emit(report)


func _relay_topic_unlocked(topic: StringName) -> void:
	topic_unlocked.emit(topic)


func _relay_topic_locked(topic: StringName) -> void:
	topic_locked.emit(topic)


func _relay_document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool) -> void:
	document_read.emit(doc_id, copy_id, reader, first_time)


func _relay_line_ready(line: WyrdLineView) -> void:
	line_ready.emit(line)


func _relay_choices_ready(choices: Array[WyrdChoiceView]) -> void:
	choices_ready.emit(choices)


func _relay_scene_started(scene_id: String) -> void:
	scene_started.emit(scene_id)


func _relay_scene_ended(scene_id: String, status: StringName, reason: StringName) -> void:
	scene_ended.emit(scene_id, status, reason)


func _relay_quest_state_changed(quest_id: String, status: StringName) -> void:
	quest_state_changed.emit(quest_id, status)


func _relay_stage_changed(quest_id: String, stage_id: String) -> void:
	stage_changed.emit(quest_id, stage_id)


func _relay_outcome_changed(quest_id: String, branch: StringName, value: StringName) -> void:
	outcome_changed.emit(quest_id, branch, value)


func _relay_journal_entry_added(quest_id: String, entry_id: String, text: String) -> void:
	journal_entry_added.emit(quest_id, entry_id, text)


func _relay_role_holder_changed(role_id: StringName, old_holder: StringName, new_holder: StringName) -> void:
	role_holder_changed.emit(role_id, old_holder, new_holder)


func _relay_role_vacant(role_id: StringName) -> void:
	role_vacant.emit(role_id)


func _relay_election_needed(role_id: StringName, departed: StringName) -> void:
	election_needed.emit(role_id, departed)


func _relay_deed_recorded(deed: Dictionary) -> void:
	deed_recorded.emit(deed)


func _relay_fact_changed(key: StringName, old_value: Variant, new_value: Variant) -> void:
	fact_changed.emit(key, old_value, new_value)


func _relay_content_unavailable(quest_id: String, pack_id: String) -> void:
	content_unavailable.emit(quest_id, pack_id)


## Returns the addon version string.
func get_version() -> String:
	return _runtime.get_version()


## Installs one config on the runtime. A null config is refused.
func configure(config: WyrdConfig) -> void:
	_runtime.configure(config)


## Registers a host adapter whose script extends the given base.
func register_adapter(base: Script, adapter: RefCounted) -> void:
	_runtime.register_adapter(base, adapter)


## Registers a content callable. Returns false when the callable is missing or the name is already used.
func register_function(name: StringName, fn: Callable, arg_types: Array, return_type: StringName) -> bool:
	return _runtime.register_function(name, fn, arg_types, return_type)


## Forwards to [method WyrdSocial.register_formula]. The default disposition is 50 plus affinity over 2.
func register_disposition_formula(fn: Callable) -> void:
	social.register_formula(fn)


## @experimental
func register_group_precedence(fn: Callable) -> void:
	_runtime.register_group_precedence(fn)


## @experimental
func register_credibility(fn: Callable) -> void:
	_runtime.register_credibility(fn)


## @experimental
func register_rumor_policy(policy: WyrdRumorPolicy) -> void:
	_runtime.register_rumor_policy(policy)


## Returns deeds a current member of a group witnessed at or after a minute. An empty filter keeps every verb.
func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array:
	return _runtime.deeds_known_to(group, since, filter)


## Drops the membership cache and wakes conditions that read group membership.
func invalidate_groups() -> void:
	_runtime.invalidate_groups()


## Drops cached cast lists. An empty [param ids] means anything may have changed.
func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void:
	_runtime.invalidate_world(ids)


## Clears play state and starts a game from a seed.
func start_new_game(seed_value: int) -> void:
	_runtime.start_new_game(seed_value)


## Compiles a content manifest and returns the load report.
func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	return _runtime.load_content(manifest)


## Advances the runtime by the given number of game minutes.
func tick(game_minutes: float) -> void:
	_runtime.tick(game_minutes)


## @experimental
func now_minutes() -> int:
	return _runtime.now_minutes()


## True when no scene is open.
func can_save() -> bool:
	return _runtime.can_save()


## Returns the save dictionary. Refuses, and returns an empty dictionary, while a scene is open.
func save_state() -> Dictionary:
	return _runtime.save_state()


## Applies a save dictionary and returns the load report. Refuses while a scene is open.
func load_state(data: Dictionary) -> WyrdLoadReport:
	return _runtime.load_state(data)


## @experimental
func rng_stream(name: StringName) -> WyrdRng:
	return _runtime.rng_stream(name)


## @experimental
func draw_u32(name: StringName) -> int:
	return _runtime.draw_u32(name)


## @experimental
func content() -> WyrdContent:
	return _runtime.content()


## @experimental
func condition_count() -> int:
	return _runtime.condition_count()


## @experimental
func condition_flags() -> PackedByteArray:
	return _runtime.condition_flags()


## @experimental
func eval_condition(index: int) -> bool:
	return _runtime.eval_condition(index)


## @experimental
func last_rechecks() -> int:
	return _runtime.last_rechecks()


## @experimental
func trace_log() -> Array[Dictionary]:
	return _runtime.trace_log()
