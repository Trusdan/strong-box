class_name WyrdConfig
extends Resource

## Host knobs for one runtime. Plain exported data. No callables.
##
## Field names beyond the design list: [member hour_bucket_minutes],
## [member half_life_verbs], [member half_life_minutes], [member disposition_default],
## [member hostile_threshold], [member axis_verbs], [member axis_names],
## [member axis_deltas], [member kind_scale_kinds], [member kind_scale_axes],
## [member kind_scale_values], [member scheduler_work_per_tick],
## [member scheduler_tick_minutes], [member scheduler_share_waits],
## [member scheduler_share_rumor], [member scheduler_share_publish],
## [member scheduler_share_cache], [member scheduler_share_generate],
## [member scheduler_share_ai_prefetch],
## [member scheduler_frame_warn_usec],
## [member rumor_coarse_minutes], [member publish_catchup_max],
## [member publish_slice_rows],
## [member credibility_threshold],
## [member compact_after],
## [member secrecy_tiers], [member secrecy_fact], [member pressure_tiers],
## [member generator_retries],
## [member trace_director],
## [member ai_banned_terms],
## [member ai_cache_max],
## [member ai_save_cache],
## and [member ai_max_inflight].
## S2a uses the hour bucket for [code]chance[/code] and the work cap for each tick.

## Minutes in one hour bucket. The default is 60.
@export var hour_bucket_minutes: int = 60
## Verbs that have a half-life. Parallel to half_life_minutes.
@export var half_life_verbs: PackedStringArray = PackedStringArray()
## Half-life of each verb, in game minutes. Parallel to half_life_verbs.
@export var half_life_minutes: PackedFloat64Array = PackedFloat64Array()
## Starting disposition before a formula runs. The default is 50.
@export var disposition_default: int = 50
## Disposition below this counts as hostile. The default is 20.
@export var hostile_threshold: int = 20
## Verb of each axis delta. Parallel to axis_names and axis_deltas.
@export var axis_verbs: PackedStringArray = PackedStringArray()
## Axis of each delta. Parallel to axis_verbs and axis_deltas.
@export var axis_names: PackedStringArray = PackedStringArray()
## Delta of each verb and axis. Parallel to axis_verbs and axis_names.
@export var axis_deltas: PackedFloat64Array = PackedFloat64Array()
## Parallel to [member kind_scale_axes] and [member kind_scale_values]. Not saved.
@export var kind_scale_kinds: PackedStringArray = PackedStringArray()
## Axis of each kind scale. Parallel to kind_scale_kinds and kind_scale_values.
@export var kind_scale_axes: PackedStringArray = PackedStringArray()
## Scale of each kind and axis. Parallel to kind_scale_kinds and kind_scale_axes.
@export var kind_scale_values: PackedFloat64Array = PackedFloat64Array()
## Work units one scheduler tick may run. The default is 64. The share weights split this.
@export var scheduler_work_per_tick: int = 64
## Game minutes in one scheduler tick. Slices of [code]Wyrd.tick[/code] add up
## until this many minutes have accumulated. Not saved.
@export var scheduler_tick_minutes: int = 1
## Weights for waits, rumor, publish, cache refresh, generate, and AI pre-fetch.
## They split [member scheduler_work_per_tick]. Not saved.
@export var scheduler_share_waits: int = 40
## Weight of the rumor queue. The default is 12. Not saved.
@export var scheduler_share_rumor: int = 12
## Weight of the publish queue. The default is 8. Not saved.
@export var scheduler_share_publish: int = 8
## Weight of the cache refresh queue. The default is 4. Not saved.
@export var scheduler_share_cache: int = 4
## Weight of the generate queue. The default is 0, so a generate unit runs
## only when earlier queues are idle and a handler is set. Not saved.
@export var scheduler_share_generate: int = 0
## Weight of the AI pre-fetch queue. The default is 0, so a unit runs only when
## the earlier queues are idle and AI is active. Not saved.
@export var scheduler_share_ai_prefetch: int = 0
## Debug builds log [code]wyrd scheduler queue=frame[/code] when one game tick's
## units take longer than this many microseconds. The default is 2000 (2 ms).
## [code]0[/code] disables it. The line does not change the work. Not saved.
@export var scheduler_frame_warn_usec: int = 2000
## Game minutes between coarse rumor rises. The default is 60, one game hour.
## [code]0[/code] or a negative value disables those rises. Not saved.
@export var rumor_coarse_minutes: int = 60
## Missed issues one visit may enqueue per document, oldest first.
## The default is 3. [code]0[/code] or a negative value enqueues none.
## Issues past the cap are numbered in the document fact and are not published later.
@export var publish_catchup_max: int = 3
## Candidate deed rows one publish unit reads while a frozen issue is open.
## The default is 128. The publish share still caps how many units run in a tick.
## Not saved.
@export var publish_slice_rows: int = 128
## Inclusive minimum score for a statement deed. Not saved.
@export var credibility_threshold: float = 0.5
## 0 leaves the log until the host calls [method WyrdDeedLog.compact]. Not saved.
@export var compact_after: int = 0
## Ordered secrecy names, lowest first. Not saved. An empty list locks every named tier.
@export var secrecy_tiers: PackedStringArray = PackedStringArray()
## Ordered pressure names, lowest first. Not saved. An empty list makes every named tier unknown.
@export var pressure_tiers: PackedStringArray = PackedStringArray()
## Extra candidate sets after a validator rejects a proposal. The default is 8.
## A negative value is read as 0. Not saved.
@export var generator_retries: int = 8
## World fact whose symbol is the unlocked secrecy name. Not saved.
@export var secrecy_fact: String = "player.clearance"
## When true, a director query logs one line per scope-and-speaker match. Not saved.
## Tracing must also be on. Load does not log those lines.
@export var trace_director: bool = false
## Case-insensitive whole words or phrases, checked by AI validation. Not saved.
@export var ai_banned_terms: PackedStringArray = PackedStringArray()
## How many validated results the AI cache keeps. The oldest inserted is evicted
## first. [code]0[/code] or less disables caching. Read on each insert and on load.
## Lowering it takes effect at the next insert or load, not immediately. Not saved.
@export var ai_cache_max: int = 256
## When true, [method WyrdRuntime.save_state] writes the optional [code]ai[/code]
## key if the cache is not empty. Not saved. Loading does not read this flag.
@export var ai_save_cache: bool = true
## The most requests Wyrd itself keeps open at once for prefetch.
## [code]0[/code] or less turns Wyrd's prefetch off. Requests the host sends
## through [method WyrdAI.request] count toward it but are never refused by it.
## Read at each prefetch. Not saved.
@export var ai_max_inflight: int = 4


## Minutes of half-life for one verb, or 0 when that verb is not listed.
func half_life_for(verb: StringName) -> float:
	var count := mini(half_life_verbs.size(), half_life_minutes.size())
	for i in count:
		if StringName(half_life_verbs[i]) == verb:
			return half_life_minutes[i]
	return 0.0


## Sets the delta for one verb and axis. Appends a row when none matches.
func set_axis_delta(verb: StringName, axis_name: StringName, delta: float) -> void:
	var count := mini(axis_verbs.size(), mini(axis_names.size(), axis_deltas.size()))
	for i in count:
		if StringName(axis_verbs[i]) == verb and StringName(axis_names[i]) == axis_name:
			axis_deltas[i] = delta
			return
	axis_verbs.append(String(verb))
	axis_names.append(String(axis_name))
	axis_deltas.append(delta)


## Replaces the factor for one kind and axis. [code]1.0[/code] leaves that kind's deeds unscaled.
func set_kind_scale(kind: StringName, axis_name: StringName, scale: float) -> void:
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_kinds[i]) == kind and StringName(kind_scale_axes[i]) == axis_name:
			kind_scale_values[i] = scale
			return
	kind_scale_kinds.append(String(kind))
	kind_scale_axes.append(String(axis_name))
	kind_scale_values.append(scale)


## [code]1.0[/code] when this kind and axis have no factor.
func kind_scale(kind: StringName, axis_name: StringName) -> float:
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_kinds[i]) == kind and StringName(kind_scale_axes[i]) == axis_name:
			return kind_scale_values[i]
	return 1.0


## Rows of [code]kind[/code] and [code]scale[/code] for one axis.
func scales_for(axis_name: StringName) -> Array:
	var rows: Array = []
	var count := mini(kind_scale_kinds.size(), mini(kind_scale_axes.size(), kind_scale_values.size()))
	for i in count:
		if StringName(kind_scale_axes[i]) != axis_name:
			continue
		rows.append({"kind": StringName(kind_scale_kinds[i]), "scale": float(kind_scale_values[i])})
	return rows


## Sum of the stored deltas for one verb and axis.
func axis_delta(verb: StringName, axis_name: StringName) -> float:
	var total := 0.0
	var count := mini(axis_verbs.size(), mini(axis_names.size(), axis_deltas.size()))
	for i in count:
		if StringName(axis_verbs[i]) == verb and StringName(axis_names[i]) == axis_name:
			total += axis_deltas[i]
	return total
