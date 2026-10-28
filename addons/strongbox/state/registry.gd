class_name StrongboxRegistry
extends RefCounted

## Collects and applies the state of every saved node in a loaded scene, by stable id.
##
## @experimental
## [method collect] returns [code]{scene_key, nodes: {id: data}, gone: [ids]}[/code] for one
## scene. [method apply] restores that state into a fresh instance of the same scene. Nodes
## removed for good (a picked-up item, a destroyed door) are recorded with [method mark_gone]
## and freed again when the scene is applied. See [StrongboxPersist] for the opt-in contract.

## Two saved nodes in one scene have the same id.
const E_DUPLICATE_ID: StringName = &"E_DUPLICATE_ID"
## A saved node has no way to capture or restore its state, or returned a non-Dictionary.
const E_CAPTURE: StringName = &"E_CAPTURE"
## The scene root has no scene key (no scene file and no override).
const E_SCENE_KEY: StringName = &"E_SCENE_KEY"
## The data passed to [method apply] does not have the shape [method collect] returns,
## or belongs to another scene.
const E_BAD_DATA: StringName = &"E_BAD_DATA"

## The group that opts a node in. Change it to use a game's own group name.
var group: StringName = StrongboxPersist.GROUP
## Ids of nodes removed for good, per scene key: [code]{scene_key: {id: true}}[/code].
var _gone: Dictionary = {}


## Collects the state of every saved node under [param scene_root]. On success
## [member StrongboxResult.value] is [code]{"scene_key", "nodes", "gone"}[/code]. Each node's data
## is checked with [StrongboxCodec], so an unsaveable value fails here with the node id in the
## message. Nothing is collected if two nodes share an id.
## @experimental
func collect(scene_root: Node) -> StrongboxResult:
	var key: String = StrongboxPersist.scene_key_of(scene_root)
	if key == "":
		return StrongboxResult.failure(E_SCENE_KEY, "The scene root \"%s\" has no scene file and no %s metadata." % [scene_root.name, StrongboxPersist.META_SCENE_KEY])
	var found: StrongboxResult = _find_nodes(scene_root)
	if not found.ok:
		return found
	var by_id: Dictionary = found.value
	var gone: Dictionary = _gone.get(key, {})
	var nodes: Dictionary = {}
	for id: String in _sorted_keys(by_id):
		if gone.has(id):
			continue
		var captured: StrongboxResult = _capture(by_id[id], id)
		if not captured.ok:
			return captured
		var checked: StrongboxResult = StrongboxCodec.encode(captured.value, id)
		if not checked.ok:
			return checked
		nodes[id] = captured.value
	return StrongboxResult.success({"scene_key": key, "nodes": nodes, "gone": _sorted_keys(gone)})


## Restores [param data] (from [method collect]) into [param scene_root], by id. Ids in
## [code]gone[/code] are recorded and their nodes freed with [method Node.queue_free]. Ids with
## no matching node are reported, not fatal. On success [member StrongboxResult.value] is
## [code]{"restored": [ids], "missing": [ids], "freed": [ids]}[/code].
## @experimental
func apply(scene_root: Node, data: Dictionary) -> StrongboxResult:
	var key: String = StrongboxPersist.scene_key_of(scene_root)
	if key == "":
		return StrongboxResult.failure(E_SCENE_KEY, "The scene root \"%s\" has no scene file and no %s metadata." % [scene_root.name, StrongboxPersist.META_SCENE_KEY])
	if typeof(data.get("nodes")) != TYPE_DICTIONARY or typeof(data.get("gone")) != TYPE_ARRAY:
		return StrongboxResult.failure(E_BAD_DATA, "Scene data must have a \"nodes\" dictionary and a \"gone\" list.")
	if data.has("scene_key") and str(data["scene_key"]) != key:
		return StrongboxResult.failure(E_BAD_DATA, "The data is for scene \"%s\", not \"%s\"." % [data["scene_key"], key])
	var found: StrongboxResult = _find_nodes(scene_root)
	if not found.ok:
		return found
	var by_id: Dictionary = found.value
	var gone: Dictionary = _gone.get(key, {})
	var freed: Array[String] = []
	for id: Variant in data["gone"]:
		gone[str(id)] = true
	_gone[key] = gone
	for id: String in _sorted_keys(gone):
		if by_id.has(id):
			(by_id[id] as Node).queue_free()
			freed.append(id)
	var nodes: Dictionary = data["nodes"]
	var restored: Array[String] = []
	var missing: Array[String] = []
	for id: String in _sorted_keys(nodes):
		if gone.has(id):
			continue
		if not by_id.has(id):
			missing.append(id)
			continue
		var node_data: Variant = nodes[id]
		if typeof(node_data) != TYPE_DICTIONARY:
			return StrongboxResult.failure(E_BAD_DATA, "The data for node \"%s\" is not a dictionary." % id)
		var result: StrongboxResult = _restore(by_id[id], id, node_data)
		if not result.ok:
			return result
		restored.append(id)
	return StrongboxResult.success({"restored": restored, "missing": missing, "freed": freed})


## Records that the saved [param node] was removed for good, so it stays gone in later
## collects and is freed when the scene is applied. Call it before freeing the node.
## [param scene_root] defaults to the node's [member Node.owner]. On success
## [member StrongboxResult.value] is the node's id.
## @experimental
func mark_gone(node: Node, scene_root: Node = null) -> StrongboxResult:
	var root: Node = scene_root if scene_root != null else node.owner
	if root == null:
		return StrongboxResult.failure(E_SCENE_KEY, "Cannot tell which scene \"%s\" belongs to; pass its scene root." % node.name)
	var key: String = StrongboxPersist.scene_key_of(root)
	if key == "":
		return StrongboxResult.failure(E_SCENE_KEY, "The scene root \"%s\" has no scene file and no %s metadata." % [root.name, StrongboxPersist.META_SCENE_KEY])
	var id: String = StrongboxPersist.id_of(node, root)
	var gone: Dictionary = _gone.get(key, {})
	gone[id] = true
	_gone[key] = gone
	return StrongboxResult.success(id)


## Returns the ids recorded as gone for [param scene_key], sorted.
## @experimental
func gone_ids(scene_key: String) -> Array[String]:
	return _sorted_keys(_gone.get(scene_key, {}))


## Records [param ids] as gone in the scene [param scene_key], as [method mark_gone] does for a
## node. Used to bring back tombstones from saved data.
## @experimental
func add_gone_ids(scene_key: String, ids: Array) -> void:
	var gone: Dictionary = _gone.get(scene_key, {})
	for id: Variant in ids:
		gone[str(id)] = true
	_gone[scene_key] = gone


## Forgets every recorded tombstone (for a new game).
## @experimental
func clear() -> void:
	_gone.clear()


## Finds every saved node under [param scene_root] and returns [code]{id: node}[/code], or
## [constant E_DUPLICATE_ID] naming both nodes when two share an id.
func _find_nodes(scene_root: Node) -> StrongboxResult:
	var by_id: Dictionary = {}
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta(StrongboxPersist.META_SPAWN_ID):
			continue # Saved by StrongboxWorldStore, with everything under it.
		for child: Node in node.get_children():
			stack.append(child)
		if node is StrongboxPersistComponent:
			continue
		if not node.is_in_group(group) and StrongboxPersist.component_of(node) == null:
			continue
		var id: String = StrongboxPersist.id_of(node, scene_root)
		if by_id.has(id):
			var other: Node = by_id[id]
			return StrongboxResult.failure(E_DUPLICATE_ID, "Two saved nodes have the id \"%s\": %s and %s." % [id, scene_root.get_path_to(other), scene_root.get_path_to(node)])
		by_id[id] = node
	return StrongboxResult.success(by_id)


func _capture(node: Node, id: String) -> StrongboxResult:
	if node.has_method(StrongboxPersist.CAPTURE_METHOD):
		var captured: Variant = node.call(StrongboxPersist.CAPTURE_METHOD)
		if typeof(captured) != TYPE_DICTIONARY:
			return StrongboxResult.failure(E_CAPTURE, "%s: persist_capture() must return a Dictionary." % id)
		return StrongboxResult.success(captured)
	var component: StrongboxPersistComponent = StrongboxPersist.component_of(node)
	if component == null or component.properties.is_empty():
		return StrongboxResult.failure(E_CAPTURE, "%s: implement persist_capture() and persist_restore(), or list properties on a StrongboxPersistComponent." % id)
	var data: Dictionary = {}
	for property: String in component.properties:
		if not property in node:
			return StrongboxResult.failure(E_CAPTURE, "%s: has no property \"%s\"." % [id, property])
		data[property] = node.get(property)
	return StrongboxResult.success(data)


func _restore(node: Node, id: String, data: Dictionary) -> StrongboxResult:
	if node.has_method(StrongboxPersist.RESTORE_METHOD):
		node.call(StrongboxPersist.RESTORE_METHOD, data)
		return StrongboxResult.success(id)
	var component: StrongboxPersistComponent = StrongboxPersist.component_of(node)
	if component == null or component.properties.is_empty():
		return StrongboxResult.failure(E_CAPTURE, "%s: implement persist_restore(), or list properties on a StrongboxPersistComponent." % id)
	for property: String in component.properties:
		if data.has(property) and property in node:
			node.set(property, data[property])
	return StrongboxResult.success(id)


func _sorted_keys(dict: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in dict:
		keys.append(str(key))
	keys.sort()
	return keys
