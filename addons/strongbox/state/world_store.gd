class_name StrongboxWorldStore
extends RefCounted

## Remembers the state of scenes that are not loaded, objects spawned at runtime, and global state.
##
## @experimental
## Call [method stash_scene] right before a scene is unloaded and [method restore_scene] after a
## new instance of it is ready (or add a [StrongboxSceneWatcher] to do both). Nodes spawned at
## runtime are recorded with [method register_spawned] and instanced again on restore, but only
## from [code]res://[/code] paths under [member spawn_allow_prefixes]. Global state (autoloads,
## a player profile) comes from providers added with [method register_provider].
## [method to_dict] and [method from_dict] turn the whole store into plain data for a save body.

## A spawn path is not under [member spawn_allow_prefixes].
const E_SPAWN_PATH: StringName = &"E_SPAWN_PATH"
## [method register_spawned] was given a node that is not inside the scene root.
const E_SPAWN: StringName = &"E_SPAWN"
## A provider is invalid, or its capture did not return a Dictionary.
const E_PROVIDER: StringName = &"E_PROVIDER"
## Data given to [method from_dict] or [method restore_globals] does not have the right shape.
const E_BAD_DATA: StringName = &"E_BAD_DATA"

## Saved state per scene key: [code]{scene_key: {"nodes": {}, "gone": [], "spawned": []}}[/code].
## Each spawned record is [code]{"id", "parent", "scene_path", "transform", "data"}[/code].
var scenes: Dictionary = {}
## Saved global state: [code]{provider_name: data}[/code]. Data for a provider that is not
## registered is kept and written back.
var globals: Dictionary = {}
## The [code]res://[/code] folders spawned scenes may be loaded from, for example
## [code]["res://items/"][/code]. Empty means nothing can be spawned. Set by the game.
var spawn_allow_prefixes: PackedStringArray = []
## Tombstones (nodes removed for good). Call [code]registry.mark_gone(node)[/code] on it.
var registry: StrongboxRegistry = StrongboxRegistry.new()

var _next_spawn: int = 1
## Live spawned nodes per scene key: [code]{scene_key: {spawn_id: {"node", "scene_path"}}}[/code].
var _live: Dictionary = {}
## [code]{name: {"capture": Callable, "restore": Callable, "priority": int}}[/code].
var _providers: Dictionary = {}


## Collects the state of [param scene_root] and replaces its stored entry, including the
## spawned nodes still under it. Call it right before the scene is unloaded.
## @experimental
func stash_scene(scene_root: Node) -> StrongboxResult:
	var collected: StrongboxResult = registry.collect(scene_root)
	if not collected.ok:
		return collected
	var key: String = collected.value["scene_key"]
	var spawned: Array[Dictionary] = []
	var live: Dictionary = _live.get(key, {})
	for id: String in _sorted(live):
		var node: Variant = live[id]["node"]
		if not is_instance_valid(node) or not scene_root.is_ancestor_of(node):
			live.erase(id) # Freed or taken out of the scene: no longer part of it.
			continue
		var record: StrongboxResult = _spawn_record(scene_root, node, id, live[id]["scene_path"])
		if not record.ok:
			return record
		spawned.append(record.value)
	scenes[key] = {"nodes": collected.value["nodes"], "gone": collected.value["gone"], "spawned": spawned}
	return StrongboxResult.success(key)


## Restores the stored entry into [param scene_root], a fresh instance that is ready. Spawned
## nodes are instanced again under their old parent. A scene with no entry is left as it is.
## On success [member StrongboxResult.value] is [code]{"restored", "missing", "freed",
## "spawned"}[/code], each a list of ids. Every spawn path is checked against the allow-list
## before anything changes. An allowed path that does not load as a scene is skipped and listed
## in [code]missing[/code] as [code]"<id> (<path>)"[/code].
## @experimental
func restore_scene(scene_root: Node) -> StrongboxResult:
	var key: String = StrongboxPersist.scene_key_of(scene_root)
	var entry: Dictionary = scenes.get(key, {})
	var empty: Array[String] = []
	if entry.is_empty():
		return StrongboxResult.success({"restored": empty, "missing": empty.duplicate(), "freed": empty.duplicate(), "spawned": empty.duplicate()})
	for record: Dictionary in entry["spawned"]:
		var allowed: StrongboxResult = _check_spawn_path(str(record["scene_path"]))
		if not allowed.ok:
			return allowed
	var applied: StrongboxResult = registry.apply(scene_root, entry)
	if not applied.ok:
		return applied
	var report: Dictionary = applied.value
	var spawned: Array[String] = []
	var live: Dictionary = _live.get(key, {})
	for record: Dictionary in entry["spawned"]:
		var id: String = record["id"]
		if live.has(id) and is_instance_valid(live[id]["node"]) and scene_root.is_ancestor_of(live[id]["node"]):
			continue # Already restored into this instance.
		var parent: Node = scene_root.get_node_or_null(NodePath(str(record["parent"])))
		if parent == null:
			report["missing"].append(id)
			continue
		var packed: PackedScene = load(record["scene_path"]) as PackedScene # strongbox: allow-load (res:// allow-list checked)
		if packed == null:
			# Allowed but gone (for example removed in a later game version): skip it and report
			# it, so the rest of the room still loads. It is dropped at the next stash.
			report["missing"].append("%s (%s)" % [id, record["scene_path"]])
			continue
		var node: Node = packed.instantiate()
		node.set_meta(StrongboxPersist.META_SPAWN_ID, id)
		parent.add_child(node)
		_set_transform(node, record.get("transform"))
		var restored: StrongboxResult = registry._restore(node, id, record["data"])
		if not restored.ok:
			return restored
		live[id] = {"node": node, "scene_path": str(record["scene_path"])}
		spawned.append(id)
	_live[key] = live
	report["spawned"] = spawned
	return StrongboxResult.success(report)


## Records [param node], instanced at runtime from [param scene_path], so it is saved with its
## scene and instanced again on restore. [param scene_root] defaults to the current scene.
## On success [member StrongboxResult.value] is the generated id ([code]spawn_<n>[/code]).
## @experimental
func register_spawned(node: Node, scene_path: String, scene_root: Node = null) -> StrongboxResult:
	var allowed: StrongboxResult = _check_spawn_path(scene_path)
	if not allowed.ok:
		return allowed
	var root: Node = scene_root
	if root == null and node.is_inside_tree():
		root = node.get_tree().current_scene
	if root == null or not root.is_ancestor_of(node):
		return StrongboxResult.failure(E_SPAWN, "\"%s\" is not inside the scene root." % node.name)
	var key: String = StrongboxPersist.scene_key_of(root)
	if key == "":
		return StrongboxResult.failure(StrongboxRegistry.E_SCENE_KEY, "The scene root \"%s\" has no scene key." % root.name)
	var id: String = "spawn_%d" % _next_spawn
	_next_spawn += 1
	node.set_meta(StrongboxPersist.META_SPAWN_ID, id)
	var live: Dictionary = _live.get(key, {})
	live[id] = {"node": node, "scene_path": scene_path}
	_live[key] = live
	return StrongboxResult.success(id)


## Adds a global provider. [param capture] takes no arguments and returns a Dictionary;
## [param restore] takes that Dictionary and may return a [StrongboxResult] (see
## [method restore_globals]). Providers restore in ascending [param priority].
## @experimental
func register_provider(provider_name: StringName, capture: Callable, restore: Callable, priority: int = 0) -> StrongboxResult:
	if provider_name == &"" or not capture.is_valid() or not restore.is_valid():
		return StrongboxResult.failure(E_PROVIDER, "A provider needs a name and two valid Callables.")
	_providers[str(provider_name)] = {"capture": capture, "restore": restore, "priority": priority}
	return StrongboxResult.success(str(provider_name))


## Removes a provider. Its saved data stays in [member globals].
## @experimental
func unregister_provider(provider_name: StringName) -> void:
	_providers.erase(str(provider_name))


## Calls every provider's capture and stores the results in [member globals], keeping data for
## providers that are not registered. On success [member StrongboxResult.value] is [member globals].
## @experimental
func capture_globals() -> StrongboxResult:
	var captured: Dictionary = globals.duplicate(true)
	for provider_name: String in _provider_order():
		var data: Variant = (_providers[provider_name]["capture"] as Callable).call()
		if typeof(data) != TYPE_DICTIONARY:
			return StrongboxResult.failure(E_PROVIDER, "Provider \"%s\": capture must return a Dictionary." % provider_name)
		var checked: StrongboxResult = StrongboxCodec.encode(data, provider_name)
		if not checked.ok:
			return checked
		captured[provider_name] = data
	globals = captured
	return StrongboxResult.success(globals)


## Stores [param data] in [member globals] and gives each provider its part, in ascending
## priority (then by name). A provider with no data gets [code]{}[/code].
## [br][br]
## A restore may return a [StrongboxResult]. A failed one stops here: later providers are not
## called, and that result is returned with its code and value, the message prefixed with the
## provider's name. It is not logged again; the provider logs its own error. On success
## [member StrongboxResult.value] is [code]{"order": [names], "results": {name: value}}[/code]:
## the providers in the order they were called, and the value of each successful
## [StrongboxResult] a restore returned. A restore that returns nothing has no entry.
## @experimental
func restore_globals(data: Dictionary) -> StrongboxResult:
	for provider_name: Variant in data:
		if typeof(data[provider_name]) != TYPE_DICTIONARY:
			return StrongboxResult.failure(E_BAD_DATA, "Global data for \"%s\" is not a dictionary." % provider_name)
	globals = data.duplicate(true)
	var order: Array[String] = _provider_order()
	var results: Dictionary = {}
	for provider_name: String in order:
		var part: Dictionary = globals.get(provider_name, {})
		var returned: Variant = (_providers[provider_name]["restore"] as Callable).call(part.duplicate(true))
		if returned is StrongboxResult:
			var outcome: StrongboxResult = returned
			if not outcome.ok:
				var failed: StrongboxResult = StrongboxResult.failure(outcome.code, "Provider \"%s\": %s" % [provider_name, outcome.message])
				failed.value = outcome.value
				return failed
			results[provider_name] = outcome.value
	return StrongboxResult.success({"order": order, "results": results})


## Returns the whole store as plain, codec-safe data for a save body. Stash the current scene
## and call [method capture_globals] first so they are included.
## @experimental
func to_dict() -> Dictionary:
	return {"scenes": scenes.duplicate(true), "globals": globals.duplicate(true), "next_spawn": _next_spawn}


## Replaces the store's contents with [param data] from [method to_dict]. Nothing changes if
## the data has the wrong shape. Providers stay registered.
## @experimental
func from_dict(data: Dictionary) -> StrongboxResult:
	var bad: String = _shape_error(data)
	if bad != "":
		return StrongboxResult.failure(E_BAD_DATA, bad)
	clear()
	scenes = data["scenes"].duplicate(true)
	globals = data["globals"].duplicate(true)
	_next_spawn = int(data["next_spawn"])
	for key: String in scenes:
		registry.add_gone_ids(key, scenes[key]["gone"])
	return StrongboxResult.success(null)


## Forgets every scene, spawned node, tombstone and global (for a new game). Providers and
## [member spawn_allow_prefixes] stay.
## @experimental
func clear() -> void:
	scenes.clear()
	globals.clear()
	registry.clear()
	_live.clear()
	_next_spawn = 1


func _spawn_record(scene_root: Node, node: Node, id: String, scene_path: String) -> StrongboxResult:
	var captured: StrongboxResult = registry._capture(node, id)
	if not captured.ok:
		return captured
	var record: Dictionary = {
		"id": id,
		"parent": str(scene_root.get_path_to(node.get_parent())),
		"scene_path": scene_path,
		"transform": _get_transform(node),
		"data": captured.value,
	}
	var checked: StrongboxResult = StrongboxCodec.encode(record, id)
	if not checked.ok:
		return checked
	return StrongboxResult.success(record)


## Only plain res:// paths under an allowed folder, with no "..", may be loaded.
func _check_spawn_path(scene_path: String) -> StrongboxResult:
	if scene_path.begins_with("res://") and not scene_path.contains("..") and not scene_path.contains("\\"):
		for prefix: String in spawn_allow_prefixes:
			var folder: String = prefix if prefix.ends_with("/") else prefix + "/"
			if folder.begins_with("res://") and scene_path.begins_with(folder):
				return StrongboxResult.success(scene_path)
	return StrongboxResult.failure(E_SPAWN_PATH, "The spawn path \"%s\" is not under an allowed res:// folder." % scene_path)


func _get_transform(node: Node) -> Variant:
	if node is Node3D:
		return (node as Node3D).transform
	if node is Node2D:
		return (node as Node2D).transform
	return null


func _set_transform(node: Node, value: Variant) -> void:
	if node is Node3D and value is Transform3D:
		(node as Node3D).transform = value
	elif node is Node2D and value is Transform2D:
		(node as Node2D).transform = value


func _provider_order() -> Array[String]:
	var order: Array[String] = _sorted(_providers)
	order.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = _providers[a]["priority"]
		var pb: int = _providers[b]["priority"]
		return pa < pb or (pa == pb and a < b))
	return order


func _shape_error(data: Dictionary) -> String:
	if typeof(data.get("scenes")) != TYPE_DICTIONARY or typeof(data.get("globals")) != TYPE_DICTIONARY:
		return "World data needs \"scenes\" and \"globals\" dictionaries."
	if typeof(data.get("next_spawn")) != TYPE_INT or int(data["next_spawn"]) < 1:
		return "World data needs a positive \"next_spawn\" int."
	for key: Variant in data["scenes"]:
		var entry: Variant = data["scenes"][key]
		if typeof(key) != TYPE_STRING or typeof(entry) != TYPE_DICTIONARY:
			return "Scene entries must be dictionaries keyed by scene key."
		if typeof(entry.get("nodes")) != TYPE_DICTIONARY or typeof(entry.get("gone")) != TYPE_ARRAY or typeof(entry.get("spawned")) != TYPE_ARRAY:
			return "Scene \"%s\" needs \"nodes\", \"gone\" and \"spawned\"." % key
		for record: Variant in entry["spawned"]:
			if typeof(record) != TYPE_DICTIONARY or typeof(record.get("id")) != TYPE_STRING or typeof(record.get("parent")) != TYPE_STRING \
					or typeof(record.get("scene_path")) != TYPE_STRING or typeof(record.get("data")) != TYPE_DICTIONARY:
				return "Scene \"%s\" has a bad spawned record." % key
	for provider_name: Variant in data["globals"]:
		if typeof(data["globals"][provider_name]) != TYPE_DICTIONARY:
			return "Global data for \"%s\" is not a dictionary." % provider_name
	return ""


func _sorted(dict: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in dict:
		keys.append(str(key))
	keys.sort()
	return keys
