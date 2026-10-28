class_name WyrdConditionCtx
extends RefCounted

## Built-ins the slice evaluates. Callables live here and are never saved.
##
## @experimental
## [code]holder[/code], [code]deed_count[/code], [code]deed_score[/code],
## [code]knows[/code], and the social reads use the runtime. [code]chance[/code]
## draws [method WyrdRng.for_decision] on stream [code]chance[/code] with key
## [code]<record>:<site>[/code]. [code]knows[/code] reads a
## role reveal or [code]known/<agent>[/code]. [code]believes[/code] is truthy of
## the resolved belief. [code]belief[/code] returns that value. [code]held[/code]
## reads one group's bag. [code]conflicted[/code] is true when the agent's groups
## hold different values for one key. [code]perceived[/code] returns the latest
## witness mode for an agent and verb. [code]reputation[/code] is the mean disposition
## of a group's members toward the subject. [code]nearby[/code] counts adapter ids.
## [code]has[/code] is a positive [code]count[/code]. [code]owner_of(item)[/code]
## reads the inventory adapter and is empty when none is registered.
## [code]active_count(template)[/code]
## counts active generated instances of that template. An unknown id is 0 and
## logs nothing. A missing adapter returns 0 or false and does not call the
## unimplemented base. A compiled key argument loads the fact; the key is the
## latest load in this evaluation.

var record_id: String = ""
var site: String = ""

var _runtime: WyrdRuntime
var _belief_hot_ok: bool = false
var _belief_hot_agent: StringName = &""
var _belief_hot_key: StringName = &""
var _belief_hot_left: Variant = null
var _belief_hot_right: Variant = null
var _belief_hot: Dictionary = {}
var _belief_cache: Dictionary = {}
## True while a coarse reach row is stored. The runtime sets this from the rumor
## list, so an empty list can return the hot cache without asking the rumor table.
var _belief_reach: bool = false
var _builtins: Dictionary = {}


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime
	_builtins = {
		&"active_count": Callable(self, &"_active_count"),
		&"affinity": Callable(self, &"_affinity"),
		&"alive": Callable(self, &"_alive"),
		&"axis": Callable(self, &"_axis"),
		&"belief": Callable(self, &"_belief"),
		&"believes": Callable(self, &"_believes"),
		&"can_perceive": Callable(self, &"_can_perceive"),
		&"can_reach": Callable(self, &"_can_reach"),
		&"conflicted": Callable(self, &"_conflicted"),
		&"count": Callable(self, &"_count"),
		&"chance": Callable(self, &"_chance"),
		&"deed_count": Callable(self, &"_deed_count"),
		&"deed_score": Callable(self, &"_deed_score"),
		&"disposition": Callable(self, &"_disposition"),
		&"done": Callable(self, &"_done"),
		&"display_name": Callable(self, &"_display_name"),
		&"filled": Callable(self, &"_filled"),
		&"has": Callable(self, &"_has"),
		&"owner_of": Callable(self, &"_owner_of"),
		&"has_read": Callable(self, &"_has_read"),
		&"has_tag": Callable(self, &"_has_tag"),
		&"held": Callable(self, &"_held"),
		&"holder": Callable(self, &"_holder"),
		&"nearby": Callable(self, &"_nearby"),
		&"outcome": Callable(self, &"_outcome"),
		&"progress": Callable(self, &"_progress"),
		&"perceived": Callable(self, &"_perceived"),
		&"kind": Callable(self, &"_kind"),
		&"knows": Callable(self, &"_knows"),
		&"path_exists": Callable(self, &"_path_exists"),
		&"rel": Callable(self, &"_rel"),
		&"reputation": Callable(self, &"_reputation"),
		&"slot_state": Callable(self, &"_slot_state"),
	}


func funcs() -> Dictionary:
	var table := _builtins.duplicate()
	if _runtime != null:
		for name in _runtime.host_functions().keys():
			table[name] = _runtime.host_functions()[name]
	return table


func _has_read(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or args[1] == null or _runtime == null or _runtime.documents == null:
		return false
	return _runtime.documents.has_read(StringName(str(args[0])), StringName(str(args[1])))


func _holder(args: Array) -> Variant:
	if args.is_empty() or args[0] == null or _runtime == null:
		return null
	var name := StringName(str(args[0]))
	var scoped: Variant = _runtime.scoped_holder(name)
	var found: StringName = _runtime.roles.holder(name)
	if scoped != null:
		found = StringName(str(scoped))
	if found == &"":
		return null
	return found


func _display_name(args: Array) -> Variant:
	if args.is_empty() or args[0] == null:
		return null
	var id := StringName(str(args[0]))
	if id == &"":
		return null
	var world := _world()
	if world == null:
		return null
	var shown := world.display_name(id)
	if shown.is_empty():
		return null
	return StringName(shown)


func _nearby(args: Array) -> int:
	if args.size() < 3 or args[0] == null:
		return 0
	var spatial := _spatial()
	if spatial == null:
		return 0
	var tag := &""
	if args[2] != null:
		tag = StringName(str(args[2]))
	var radius := 0.0
	if args[1] != null:
		radius = float(args[1])
	return spatial.nearby(StringName(str(args[0])), radius, WyrdEntityFilter.new(tag, &"")).size()


func _can_perceive(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or args[1] == null:
		return false
	var spatial := _spatial()
	if spatial == null:
		return false
	return spatial.can_perceive(StringName(str(args[0])), StringName(str(args[1])))


func _can_reach(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or args[1] == null:
		return false
	var spatial := _spatial()
	if spatial == null:
		return false
	return spatial.can_reach(StringName(str(args[0])), StringName(str(args[1])))


func _has(args: Array) -> bool:
	return _count(args) > 0


func _count(args: Array) -> int:
	if args.size() < 2 or args[0] == null or args[1] == null:
		return 0
	var inventory := _inventory()
	if inventory == null:
		return 0
	return inventory.count(StringName(str(args[0])), StringName(str(args[1])))


func _owner_of(args: Array) -> StringName:
	if args.is_empty() or args[0] == null:
		return &""
	var inventory := _inventory()
	if inventory == null:
		return &""
	return inventory.owner_of(StringName(str(args[0])))


func _kind(args: Array) -> StringName:
	if args.is_empty() or args[0] == null:
		return &""
	var world := _world()
	if world == null:
		return &""
	return world.kind(StringName(str(args[0])))


func _has_tag(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or args[1] == null:
		return false
	var world := _world()
	if world == null:
		return false
	var want := String(args[1])
	for tag in world.tags(StringName(str(args[0]))):
		if String(tag) == want:
			return true
	return false


func _alive(args: Array) -> bool:
	if args.is_empty() or args[0] == null:
		return false
	var world := _world()
	if world == null:
		return false
	return world.is_alive(StringName(str(args[0])))


func _deed_count(args: Array) -> int:
	return int(_deeds(args, false))


func _deed_score(args: Array) -> float:
	return float(_deeds(args, true))


func _known(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or _runtime == null:
		return false
	var agent := StringName(str(args[0]))
	var key := _known_key(args[1])
	if key == &"":
		return false
	if _runtime.roles.revealed(agent, key):
		return true
	return _runtime.facts.get_in(key, StringName("known/%s" % String(agent))) != null


func _active_count(args: Array) -> int:
	if args.is_empty() or args[0] == null or _runtime == null or _runtime.quests == null:
		return 0
	return _runtime.quests.active_count(str(args[0]))


func _affinity(args: Array) -> float:
	if not _pair(args):
		return 0.0
	return _runtime.social.affinity(StringName(str(args[0])), StringName(str(args[1])))


func _axis(args: Array) -> float:
	if args.size() < 3 or not _pair(args) or args[2] == null:
		return 0.0
	return _runtime.social.axis(StringName(str(args[0])), StringName(str(args[1])), StringName(str(args[2])))


func _disposition(args: Array) -> int:
	if not _pair(args):
		return 0
	return _runtime.social.disposition(StringName(str(args[0])), StringName(str(args[1])))


func _path_exists(args: Array) -> bool:
	if args.size() < 4 or not _pair(args) or _runtime == null:
		return false
	var hops := 0
	if args[3] != null:
		hops = int(args[3])
	return _runtime.social.path_exists(StringName(str(args[0])), StringName(str(args[1])), _tags(args[2]), hops)


func _rel(args: Array) -> bool:
	if args.size() < 3 or not _pair(args) or args[2] == null:
		return false
	return _runtime.social.has_kind(StringName(str(args[0])), StringName(str(args[1])), StringName(str(args[2])))


func _reputation(args: Array) -> float:
	if args.size() < 2 or args[0] == null or args[1] == null or _runtime == null:
		return 0.0
	return _runtime.social.reputation(StringName(str(args[0])), StringName(str(args[1])))


func _filled(args: Array) -> bool:
	return _holder(args) != null


func _progress(args: Array) -> int:
	if args.is_empty() or args[0] == null or _runtime == null or _runtime.sequences == null:
		return 0
	return _runtime.sequences.progress(str(args[0]))


func _done(args: Array) -> bool:
	if args.is_empty() or args[0] == null or _runtime == null or _runtime.sequences == null:
		return false
	return _runtime.sequences.done(str(args[0]))


func _outcome(args: Array) -> Variant:
	if args.size() < 2 or args[0] == null or args[1] == null or _runtime == null or _runtime.quests == null:
		return null
	var value := _runtime.quests.outcome(str(args[0]), str(args[1]))
	if value.is_empty():
		return null
	return StringName(value)


func _slot_state(args: Array) -> Variant:
	if args.is_empty() or args[0] == null or _runtime == null:
		return null
	var name := StringName(str(args[0]))
	var scoped: Variant = _runtime.scoped_slot_state(name)
	var state: StringName = _runtime.roles.slot_state(name)
	if scoped != null:
		state = StringName(str(scoped))
	if state == &"":
		return null
	return state


func _deeds(args: Array, score: bool) -> Variant:
	if _runtime == null or args.is_empty() or args[0] == null:
		return 0.0 if score else 0
	var tags := PackedStringArray()
	if args.size() > 5:
		tags = _tags(args[5])
	var within: Variant = args[4] if args.size() > 4 else null
	var place: Variant = args[3] if args.size() > 3 else null
	var target: Variant = args[2] if args.size() > 2 else null
	var verb: Variant = args[1] if args.size() > 1 else null
	var actor := StringName(str(args[0]))
	if score:
		return _runtime.deeds.score_matching(actor, verb, target, place, within, tags)
	return _runtime.deeds.count_matching(actor, verb, target, place, within, tags)


func _tags(value: Variant) -> PackedStringArray:
	var rows := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for item in value:
			if item != null:
				rows.append(String(item))
	return rows


func _known_key(value: Variant) -> StringName:
	if (value is String or value is StringName) and String(value).contains("."):
		return StringName(str(value))
	if _runtime != null and not _runtime.loaded_fact_key().is_empty():
		return StringName(_runtime.loaded_fact_key())
	if value is String or value is StringName:
		return StringName(str(value))
	return &""


func _pair(args: Array) -> bool:
	return _runtime != null and args.size() >= 2 and args[0] != null and args[1] != null


func _chance(args: Array) -> bool:
	if _runtime == null or args.is_empty() or not (args[0] is float or typeof(args[0]) == TYPE_INT):
		return false
	var p := float(args[0])
	if p >= 1.0:
		return true
	if p <= 0.0:
		return false
	var bucket := 0
	var size := _runtime.config().hour_bucket_minutes
	if size > 0:
		bucket = int(_runtime.now_minutes() / float(size))
	var key := StringName("%s:%s" % [record_id, site])
	var rng := WyrdRng.for_decision(_runtime.game_seed(), &"chance", key, bucket)
	var hit := rng.randf() < p
	_runtime.trace_add("roll", {"key": String(key), "pass": hit, "stream": "chance"})
	return hit


func _knows(args: Array) -> bool:
	return _known(args)


func _perceived(args: Array) -> Variant:
	if args.size() < 2 or args[0] == null or args[1] == null or _runtime == null or _runtime.deeds == null:
		return null
	var mode := _runtime.deeds.mode_of(StringName(str(args[0])), StringName(str(args[1])))
	if mode == &"":
		return null
	return mode


func _belief(args: Array) -> Variant:
	return _resolve_belief(args)["value"]


func _believes(args: Array) -> bool:
	return _truthy(_belief(args))


## True when two member groups hold different present values. The agent's own
## belief, [code]known/[/code], and [code]world[/code] are not positions. Absence
## is not a position. Explicit false is.
func _conflicted(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or _runtime == null:
		return false
	var agent := StringName(str(args[0]))
	var key := _known_key(args[1])
	if key == &"":
		_runtime.trace_conflict(agent, key, false, "none", null, "")
		return false
	var winner_group := ""
	var winner: Variant = null
	var against := PackedStringArray()
	for group in _runtime.group_precedence(agent):
		var held: Variant = _runtime.facts.get_in(key, StringName("held/%s" % String(group)))
		if held == null:
			continue
		if winner_group.is_empty():
			winner_group = String(group)
			winner = held
			continue
		if not _same_value(winner, held):
			against.append(String(group))
	var hit := not against.is_empty()
	var source := "none" if winner_group.is_empty() else "group %s" % winner_group
	_runtime.trace_conflict(agent, key, hit, source, winner if not winner_group.is_empty() else null, ",".join(against))
	return hit


func _same_value(left: Variant, right: Variant) -> bool:
	var left_text := left is String or left is StringName
	var right_text := right is String or right is StringName
	if left_text and right_text:
		return String(left) == String(right)
	var left_num := left is int or left is float
	var right_num := right is int or right is float
	if left_num and right_num:
		if left is float or right is float:
			return is_equal_approx(float(left), float(right))
		return left == right
	if typeof(left) != typeof(right):
		return false
	return left == right


func _held(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or _runtime == null:
		return false
	var key := _known_key(args[1])
	if key == &"":
		return false
	var group := StringName(str(args[0]))
	return _truthy(_runtime.facts.get_in(key, StringName("held/%s" % String(group))))


func set_belief_reach(present: bool) -> void:
	_belief_reach = present


func clear_belief_cache() -> void:
	_belief_hot_ok = false
	_belief_hot_agent = &""
	_belief_hot_key = &""
	_belief_hot_left = null
	_belief_hot_right = null
	_belief_hot = {}
	_belief_cache.clear()


## Own [code]believed/[/code], then [code]held/[/code] of each group in precedence
## order. A present value, including explicit false, stops the walk. Null is no
## opinion. [code]known/[/code] and [code]world[/code] are not read.
## Repeated lookups are cached while tracing is off. A belief write or
## [method WyrdRuntime.invalidate_groups] drops the cache. An empty reach list
## returns that hot cache before the agent and key are built. A reach row still
## draws before the cache, so a later rise can write.
func _resolve_belief(args: Array) -> Dictionary:
	if args.size() < 2 or args[0] == null or _runtime == null:
		return {"source": "none", "value": null}
	var traced := _runtime.trace != null and _runtime.trace.enabled
	if not _belief_reach and not traced and _belief_hot_ok and _belief_hot_left == args[0] and _belief_hot_right == args[1]:
		return _belief_hot
	var agent := StringName(str(args[0]))
	var key := _known_key(args[1])
	if _belief_reach and _runtime.rumors != null:
		_runtime.rumors.materialize(agent, key)
	if not traced and _belief_hot_ok and _belief_hot_left == args[0] and _belief_hot_right == args[1]:
		return _belief_hot
	if not traced and _belief_hot_ok and _belief_hot_agent == agent and _belief_hot_key == key:
		_belief_hot_left = args[0]
		_belief_hot_right = args[1]
		return _belief_hot
	var token := ""
	if not traced:
		token = "%s\t%s" % [String(agent), String(key)]
	if not traced and _belief_cache.has(token):
		_belief_hot_ok = true
		_belief_hot_agent = agent
		_belief_hot_key = key
		_belief_hot_left = args[0]
		_belief_hot_right = args[1]
		_belief_hot = _belief_cache[token]
		return _belief_hot
	var resolved := _walk_belief(agent, key)
	if not traced:
		_belief_cache[token] = resolved
		_belief_hot_ok = true
		_belief_hot_agent = agent
		_belief_hot_key = key
		_belief_hot_left = args[0]
		_belief_hot_right = args[1]
		_belief_hot = resolved
	return resolved


func _walk_belief(agent: StringName, key: StringName) -> Dictionary:
	if key == &"":
		_runtime.trace_belief_lookup(agent, key, null, "none")
		return {"source": "none", "value": null}
	var own: Variant = _runtime.facts.get_in(key, StringName("believed/%s" % String(agent)))
	if own != null:
		_runtime.trace_belief_lookup(agent, key, own, "own")
		return {"source": "own", "value": own}
	for group in _runtime.group_precedence(agent):
		var held: Variant = _runtime.facts.get_in(key, StringName("held/%s" % String(group)))
		if held == null:
			continue
		var source := "group %s" % String(group)
		_runtime.trace_belief_lookup(agent, key, held, source)
		return {"source": source, "value": held}
	_runtime.trace_belief_lookup(agent, key, null, "none")
	return {"source": "none", "value": null}


func _truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return value != 0.0
	if value is String or value is StringName:
		return not String(value).is_empty()
	return true


func _world() -> WyrdWorldAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null


func _spatial() -> WyrdSpatialAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdSpatialAdapter)
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _inventory() -> WyrdInventoryAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdInventoryAdapter)
	if found is WyrdInventoryAdapter:
		return found as WyrdInventoryAdapter
	return null
