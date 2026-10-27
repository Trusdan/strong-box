extends GutTest

## StrongboxRegistry: opt-in, stable ids, collect/apply, tombstones and refusals.

const ROOM: PackedScene = preload("res://tests/fixtures/cellar_room.tscn")
const ROOM_KEY: String = "res://tests/fixtures/cellar_room.tscn"
const ALL_IDS: Array[String] = ["Coin", "Props/Chest01", "Props/Lever", "cellar_door", "shelf_main"]


func _room() -> Node3D:
	var room: Node3D = ROOM.instantiate()
	add_child_autofree(room)
	return room


func _ids(collected: StrongboxResult) -> Array[String]:
	var ids: Array[String] = []
	for id: String in collected.value["nodes"]:
		ids.append(id)
	ids.sort()
	return ids


func _add_saved_node(room: Node, node_name: String, script_source: String) -> Node3D:
	var script: GDScript = GDScript.new()
	script.source_code = script_source
	script.reload()
	var node: Node3D = Node3D.new()
	node.name = node_name
	node.set_script(script)
	node.add_to_group(StrongboxPersist.GROUP)
	room.get_node("Props").add_child(node)
	return node


func test_group_and_component_opt_in() -> void:
	var collected: StrongboxResult = StrongboxRegistry.new().collect(_room())
	assert_true(collected.ok, str(collected))
	assert_eq(collected.value["scene_key"], ROOM_KEY)
	assert_eq(_ids(collected), ALL_IDS, "group nodes, component nodes, meta ids and component ids; Decor is ignored")
	assert_eq(collected.value["gone"], [] as Array[String])


func test_property_whitelist_saves_and_restores_only_listed_properties() -> void:
	var room: Node3D = _room()
	var lever: Node3D = room.get_node("Props/Lever")
	lever.on = true
	lever.angle = 0.5
	lever.label = "changed"
	var registry: StrongboxRegistry = StrongboxRegistry.new()
	var collected: StrongboxResult = registry.collect(room)
	assert_eq(collected.value["nodes"]["Props/Lever"], {"on": true, "angle": 0.5})
	var fresh: Node3D = _room()
	assert_true(registry.apply(fresh, collected.value).ok)
	var fresh_lever: Node3D = fresh.get_node("Props/Lever")
	assert_eq(fresh_lever.on, true)
	assert_eq(fresh_lever.angle, 0.5)
	assert_eq(fresh_lever.label, "not saved", "unlisted properties are never restored")
	var tampered: Dictionary = {"nodes": {"Props/Lever": {"on": false, "label": "injected"}}, "gone": []}
	assert_true(registry.apply(fresh, tampered).ok)
	assert_eq(fresh_lever.on, false)
	assert_eq(fresh_lever.label, "not saved", "an unlisted key in the data is ignored")


func test_ids_are_stable_across_instances() -> void:
	var first: Array[String] = _ids(StrongboxRegistry.new().collect(_room()))
	var second: Array[String] = _ids(StrongboxRegistry.new().collect(_room()))
	assert_eq(first, second)
	assert_eq(first, ALL_IDS)


func test_duplicate_ids_are_refused_with_both_paths() -> void:
	var room: Node3D = _room()
	var decor: Node3D = room.get_node("Decor")
	decor.set_meta(StrongboxPersist.META_ID, "Coin")
	decor.add_to_group(StrongboxPersist.GROUP)
	var collected: StrongboxResult = StrongboxRegistry.new().collect(room)
	assert_eq(collected.code, StrongboxRegistry.E_DUPLICATE_ID)
	assert_string_contains(collected.message, "Coin")
	assert_string_contains(collected.message, "Decor")
	assert_null(collected.value, "nothing is collected")


func test_collect_then_apply_to_fresh_instance_restores_state_and_frees_tombstones() -> void:
	var room: Node3D = _room()
	var chest: Node3D = room.get_node("Props/Chest01")
	chest.opened = true
	chest.gold = 5
	room.get_node("Shelf").position = Vector3(1.5, 0.0, -2.25)
	room.get_node("Door").visible = false
	var registry: StrongboxRegistry = StrongboxRegistry.new()
	var coin: Node = room.get_node("Coin")
	assert_eq(registry.mark_gone(coin).value, "Coin", "the coin is picked up for good")
	coin.queue_free()
	var collected: StrongboxResult = registry.collect(room)
	assert_eq(collected.value["gone"], ["Coin"] as Array[String])
	assert_false(collected.value["nodes"].has("Coin"))

	# A new registry, as after loading a save in a new session.
	var fresh: Node3D = _room()
	var applied: StrongboxResult = StrongboxRegistry.new().apply(fresh, collected.value)
	assert_true(applied.ok, str(applied))
	assert_eq(applied.value["freed"], ["Coin"] as Array[String])
	assert_true(fresh.get_node("Coin").is_queued_for_deletion(), "the tombstoned coin is freed")
	assert_eq(fresh.get_node("Props/Chest01").opened, true)
	assert_eq(fresh.get_node("Props/Chest01").gold, 5)
	assert_eq(fresh.get_node("Shelf").position, Vector3(1.5, 0.0, -2.25))
	assert_eq(fresh.get_node("Door").visible, false)
	assert_eq(applied.value["missing"], [] as Array[String])


func test_capture_returning_an_object_fails_with_the_node_id() -> void:
	var room: Node3D = _room()
	_add_saved_node(room, "Broken", "extends Node3D\nfunc persist_capture() -> Dictionary:\n\treturn {\"weapon\": RefCounted.new()}\n")
	var collected: StrongboxResult = StrongboxRegistry.new().collect(room)
	assert_eq(collected.code, StrongboxCodec.E_UNSUPPORTED_TYPE)
	assert_string_contains(collected.message, "Props/Broken.weapon")


func test_opted_in_node_without_capture_is_refused() -> void:
	var room: Node3D = _room()
	_add_saved_node(room, "Plain", "extends Node3D\n")
	var collected: StrongboxResult = StrongboxRegistry.new().collect(room)
	assert_eq(collected.code, StrongboxRegistry.E_CAPTURE)
	assert_string_contains(collected.message, "Props/Plain")


func test_ids_without_a_node_are_reported_not_fatal() -> void:
	var data: Dictionary = {
		"scene_key": ROOM_KEY,
		"nodes": {"Props/Chest01": {"opened": true, "gold": 2}, "Props/Vanished": {"x": 1}},
		"gone": [],
	}
	var room: Node3D = _room()
	var applied: StrongboxResult = StrongboxRegistry.new().apply(room, data)
	assert_true(applied.ok)
	assert_eq(applied.value["missing"], ["Props/Vanished"] as Array[String])
	assert_eq(applied.value["restored"], ["Props/Chest01"] as Array[String])
	assert_eq(room.get_node("Props/Chest01").gold, 2)


func test_scene_keys_and_bad_data() -> void:
	var registry: StrongboxRegistry = StrongboxRegistry.new()
	var room: Node3D = _room()
	room.set_meta(StrongboxPersist.META_SCENE_KEY, "hub_override")
	assert_eq(registry.collect(room).value["scene_key"], "hub_override")
	var loose: Node3D = Node3D.new()
	add_child_autofree(loose)
	assert_eq(registry.collect(loose).code, StrongboxRegistry.E_SCENE_KEY)
	var other_scene: Dictionary = {"scene_key": "res://somewhere_else.tscn", "nodes": {}, "gone": []}
	assert_eq(registry.apply(_room(), other_scene).code, StrongboxRegistry.E_BAD_DATA)
	assert_eq(registry.apply(_room(), {"nodes": []}).code, StrongboxRegistry.E_BAD_DATA)
	assert_eq(registry.apply(_room(), {"nodes": {"Props/Chest01": 5}, "gone": []}).code, StrongboxRegistry.E_BAD_DATA)


func test_tombstones_persist_in_the_registry_until_cleared() -> void:
	var registry: StrongboxRegistry = StrongboxRegistry.new()
	var room: Node3D = _room()
	registry.mark_gone(room.get_node("Coin"))
	assert_eq(registry.gone_ids(ROOM_KEY), ["Coin"] as Array[String])
	var again: StrongboxResult = registry.collect(_room())
	assert_eq(again.value["gone"], ["Coin"] as Array[String], "a coin still in a fresh instance is not collected once gone")
	assert_false(again.value["nodes"].has("Coin"))
	registry.clear()
	assert_eq(registry.gone_ids(ROOM_KEY), [] as Array[String])
