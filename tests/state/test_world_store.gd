extends GutTest

## StrongboxWorldStore: rooms remember their state while unloaded, spawned items come back,
## the store survives a save round trip, spawn paths are allow-listed, and providers restore in order.

const CELLAR: PackedScene = preload("res://tests/fixtures/cellar_room.tscn")
const HUB: PackedScene = preload("res://tests/fixtures/hub_room.tscn")
const CELLAR_PATH: String = "res://tests/fixtures/cellar_room.tscn"
const HUB_PATH: String = "res://tests/fixtures/hub_room.tscn"
const ITEM: PackedScene = preload("res://tests/fixtures/spawn/dropped_item.tscn")
const ITEM_PATH: String = "res://tests/fixtures/spawn/dropped_item.tscn"
const SPAWN_FOLDER: String = "res://tests/fixtures/spawn/"
const DROP_AT: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(1.25, 0.0, -3.5))


func _store() -> StrongboxWorldStore:
	var store: StrongboxWorldStore = StrongboxWorldStore.new()
	store.spawn_allow_prefixes = PackedStringArray([SPAWN_FOLDER])
	return store


## Loads a fresh instance of a room and restores it, as a scene change would.
func _enter(scene: PackedScene, store: StrongboxWorldStore) -> Node3D:
	var room: Node3D = scene.instantiate()
	add_child(room)
	var restored: StrongboxResult = store.restore_scene(room)
	assert_true(restored.ok, str(restored))
	return room


## Stashes a room and unloads it.
func _leave(room: Node3D, store: StrongboxWorldStore) -> void:
	var stashed: StrongboxResult = store.stash_scene(room)
	assert_true(stashed.ok, str(stashed))
	room.free()


func _drop_item(hub: Node3D, store: StrongboxWorldStore) -> Node3D:
	var item: Node3D = ITEM.instantiate()
	item.item_name = "rope"
	item.count = 3
	item.add_to_group(StrongboxPersist.GROUP) # The registry must still leave it to the store.
	hub.get_node("Items").add_child(item)
	item.transform = DROP_AT
	var registered: StrongboxResult = store.register_spawned(item, ITEM_PATH, hub)
	assert_true(registered.ok, str(registered))
	return item


func test_opened_chest_stays_open_after_leaving_and_returning() -> void:
	var store: StrongboxWorldStore = _store()
	var cellar: Node3D = _enter(CELLAR, store)
	cellar.get_node("Props/Chest01").opened = true
	_leave(cellar, store)
	_leave(_enter(HUB, store), store)
	var again: Node3D = _enter(CELLAR, store)
	assert_eq(again.get_node("Props/Chest01").opened, true)
	assert_eq(store.scenes.keys().size(), 2, "one entry per room")
	again.free()


func test_taken_coin_stays_gone() -> void:
	var store: StrongboxWorldStore = _store()
	var cellar: Node3D = _enter(CELLAR, store)
	var coin: Node = cellar.get_node("Coin")
	store.registry.mark_gone(coin)
	coin.free()
	_leave(cellar, store)
	var again: Node3D = _enter(CELLAR, store)
	assert_true(again.get_node("Coin").is_queued_for_deletion(), "the coin in the fresh instance is freed")
	await get_tree().process_frame
	assert_null(again.get_node_or_null("Coin"))
	_leave(again, store)
	assert_eq(store.scenes[CELLAR_PATH]["gone"], ["Coin"] as Array[String], "still gone after a second visit")


func test_spawned_item_comes_back_with_transform_and_data() -> void:
	var store: StrongboxWorldStore = _store()
	var hub: Node3D = _enter(HUB, store)
	_drop_item(hub, store)
	assert_eq(store.registry.collect(hub).value["nodes"], {}, "the registry skips spawned nodes")
	_leave(hub, store)
	assert_eq(store.scenes[HUB_PATH]["spawned"][0]["id"], "spawn_1")

	var again: Node3D = HUB.instantiate()
	add_child(again)
	var restored: StrongboxResult = store.restore_scene(again)
	assert_eq(restored.value["spawned"], ["spawn_1"] as Array[String])
	var items: Array[Node] = again.get_node("Items").get_children()
	assert_eq(items.size(), 1)
	var item: Node3D = items[0]
	assert_eq(item.transform, DROP_AT)
	assert_eq([item.item_name, item.count], ["rope", 3])
	assert_true(store.restore_scene(again).ok)
	assert_eq(again.get_node("Items").get_child_count(), 1, "restoring twice does not duplicate it")

	item.free() # Picked up again: it is no longer part of the room.
	_leave(again, store)
	assert_eq(store.scenes[HUB_PATH]["spawned"], [] as Array[Dictionary])


func test_round_trip_through_a_save_with_a_fresh_store() -> void:
	var store: StrongboxWorldStore = _store()
	var cellar: Node3D = _enter(CELLAR, store)
	cellar.get_node("Props/Chest01").opened = true
	store.registry.mark_gone(cellar.get_node("Coin"))
	_leave(cellar, store)
	var hub: Node3D = _enter(HUB, store)
	_drop_item(hub, store)
	_leave(hub, store)
	store.globals = {"profile": {"name": "Tester"}}

	var text: String = StrongboxEnvelope.pack(store.to_dict(), {}).value
	var body: Dictionary = StrongboxEnvelope.unpack(text).value["body"]
	var fresh: StrongboxWorldStore = _store()
	var loaded: StrongboxResult = fresh.from_dict(body)
	assert_true(loaded.ok, str(loaded))
	assert_eq(fresh.to_dict(), store.to_dict(), "the data is unchanged by the save round trip")
	assert_eq(fresh.registry.gone_ids(CELLAR_PATH), ["Coin"] as Array[String])

	var cellar_again: Node3D = _enter(CELLAR, fresh)
	assert_eq(cellar_again.get_node("Props/Chest01").opened, true)
	assert_true(cellar_again.get_node("Coin").is_queued_for_deletion())
	cellar_again.free()
	var hub_again: Node3D = _enter(HUB, fresh)
	var item: Node3D = hub_again.get_node("Items").get_child(0)
	assert_eq(item.transform, DROP_AT)
	assert_eq(item.item_name, "rope")
	var next: Node3D = Node3D.new()
	hub_again.add_child(next)
	assert_eq(fresh.register_spawned(next, ITEM_PATH, hub_again).value, "spawn_2", "ids keep counting after a load")
	hub_again.free()


func test_spawn_paths_outside_the_allow_list_are_refused() -> void:
	var store: StrongboxWorldStore = _store()
	var hub: Node3D = _enter(HUB, store)
	var node: Node3D = Node3D.new()
	hub.add_child(node)
	for path: String in [CELLAR_PATH, "user://item.tscn", SPAWN_FOLDER + "../cellar_room.tscn", "res://tests/fixtures/spawnx/item.tscn"]:
		assert_eq(store.register_spawned(node, path, hub).code, StrongboxWorldStore.E_SPAWN_PATH, path)
	store.spawn_allow_prefixes = PackedStringArray(["res://tests/fixtures/spa"])
	assert_eq(store.register_spawned(node, ITEM_PATH, hub).code, StrongboxWorldStore.E_SPAWN_PATH, "a prefix is a whole folder")
	store.spawn_allow_prefixes = PackedStringArray(["user://"])
	assert_eq(store.register_spawned(node, "user://item.tscn", hub).code, StrongboxWorldStore.E_SPAWN_PATH, "only res:// folders count")
	hub.free()

	# A tampered save names a scene outside the allow-list: nothing is loaded or changed.
	var tampered: StrongboxWorldStore = _store()
	var record: Dictionary = {"id": "spawn_1", "parent": "Items", "scene_path": CELLAR_PATH, "transform": null, "data": {}}
	var data: Dictionary = {"scenes": {HUB_PATH: {"nodes": {}, "gone": [], "spawned": [record]}}, "globals": {}, "next_spawn": 2}
	assert_true(tampered.from_dict(data).ok)
	var room: Node3D = HUB.instantiate()
	add_child_autofree(room)
	assert_eq(tampered.restore_scene(room).code, StrongboxWorldStore.E_SPAWN_PATH)
	assert_eq(room.get_node("Items").get_child_count(), 0)


func test_allowed_spawn_that_no_longer_loads_is_skipped_and_reported() -> void:
	var store: StrongboxWorldStore = _store()
	var gone_path: String = SPAWN_FOLDER + "removed_item.tscn"
	var records: Array[Dictionary] = [
		{"id": "spawn_1", "parent": "Items", "scene_path": gone_path, "transform": null, "data": {}},
		{"id": "spawn_2", "parent": "Items", "scene_path": ITEM_PATH, "transform": DROP_AT, "data": {"item_name": "rope", "count": 1}},
	]
	assert_true(store.from_dict({"scenes": {HUB_PATH: {"nodes": {}, "gone": [], "spawned": records}}, "globals": {}, "next_spawn": 3}).ok)
	var hub: Node3D = HUB.instantiate()
	add_child(hub)
	var restored: StrongboxResult = store.restore_scene(hub)
	# Godot logs three errors for a missing resource: two name the file, one is its internal check.
	assert_engine_error("Cannot open file")
	assert_engine_error("Failed loading resource")
	assert_true(restored.ok, str(restored))
	assert_eq(restored.value["missing"], ["spawn_1 (%s)" % gone_path] as Array[String])
	assert_eq(restored.value["spawned"], ["spawn_2"] as Array[String], "the rest of the room still loads")
	_leave(hub, store)
	assert_eq(store.scenes[HUB_PATH]["spawned"].size(), 1, "the skipped record is dropped at the next stash")


func test_providers_restore_by_priority_with_missing_and_unknown_data() -> void:
	var store: StrongboxWorldStore = _store()
	var calls: Array[String] = []
	var received: Dictionary = {}
	for entry: Array in [["quests", 10], ["profile", -5], ["clock", 0]]:
		var provider_name: String = entry[0]
		var restore: Callable = func(data: Dictionary) -> void:
			calls.append(provider_name)
			received[provider_name] = data
		store.register_provider(StringName(provider_name), func() -> Dictionary: return {"from": provider_name}, restore, entry[1])
	var restored: StrongboxResult = store.restore_globals({"profile": {"level": 2}, "quests": {"done": 1}, "old_system": {"x": 1}})
	assert_true(restored.ok, str(restored))
	assert_eq(calls, ["profile", "clock", "quests"] as Array[String], "ascending priority")
	assert_eq(received["clock"], {}, "a provider with no data gets {}")
	assert_eq(received["profile"], {"level": 2})

	store.unregister_provider(&"quests")
	var captured: StrongboxResult = store.capture_globals()
	assert_eq(captured.value, {"profile": {"from": "profile"}, "clock": {"from": "clock"}, "quests": {"done": 1}, "old_system": {"x": 1}},
		"unknown and unregistered data is kept")
	assert_eq(store.to_dict()["globals"]["old_system"], {"x": 1})

	store.register_provider(&"broken", func() -> Variant: return [1], func(_data: Dictionary) -> void: pass)
	assert_eq(store.capture_globals().code, StrongboxWorldStore.E_PROVIDER)
	assert_eq(store.register_provider(&"bad", Callable(), Callable()).code, StrongboxWorldStore.E_PROVIDER)
	assert_eq(store.restore_globals({"profile": 5}).code, StrongboxWorldStore.E_BAD_DATA)


func test_a_failed_provider_restore_stops_and_successful_values_pass_through() -> void:
	var store: StrongboxWorldStore = _store()
	assert_eq(store.restore_globals({}).value, {"order": [] as Array[String], "results": {}}, "no providers")
	var calls: Array[String] = []
	store.register_provider(&"clock", func() -> Dictionary: return {},
		func(_data: Dictionary) -> void: calls.append("clock"), -1)
	store.register_provider(&"profile", func() -> Dictionary: return {},
		func(data: Dictionary) -> StrongboxResult:
			calls.append("profile")
			return StrongboxResult.success({"level": data.get("level", 0)}))
	var restored: StrongboxResult = store.restore_globals({"profile": {"level": 4}})
	assert_true(restored.ok, str(restored))
	assert_eq(restored.value["results"], {"profile": {"level": 4}}, "a void restore has no entry")

	store.register_provider(&"story", func() -> Dictionary: return {},
		func(_data: Dictionary) -> StrongboxResult:
			calls.append("story")
			var refused: StrongboxResult = StrongboxResult.failure(&"E_STORY", "stage 9 is unknown")
			refused.value = {"codes": ["E_STAGE"]}
			return refused, 5)
	store.register_provider(&"zz_late", func() -> Dictionary: return {},
		func(_data: Dictionary) -> void: calls.append("zz_late"), 10)
	calls.clear()
	var failed: StrongboxResult = store.restore_globals({})
	assert_eq(failed.code, &"E_STORY", "the provider's own code")
	assert_eq(failed.message, "Provider \"story\": stage 9 is unknown")
	assert_eq(failed.value, {"codes": ["E_STAGE"]})
	assert_eq(calls, ["clock", "profile", "story"] as Array[String], "later providers are not called")


func test_scene_watcher_restores_on_ready_and_stashes_on_exit() -> void:
	var store: StrongboxWorldStore = _store()
	var cellar: Node3D = _with_watcher(CELLAR.instantiate(), store)
	add_child(cellar)
	cellar.get_node("Props/Chest01").opened = true
	cellar.queue_free()
	await get_tree().process_frame
	assert_eq(store.scenes[CELLAR_PATH]["nodes"]["Props/Chest01"]["opened"], true, "stashed on exit")

	var again: Node3D = _with_watcher(CELLAR.instantiate(), store)
	add_child_autofree(again)
	assert_eq(again.get_node("Props/Chest01").opened, true, "restored when ready")


func test_from_dict_refuses_bad_data_and_clear_resets() -> void:
	var store: StrongboxWorldStore = _store()
	store.globals = {"profile": {"a": 1}}
	for bad: Dictionary in [{}, {"scenes": [], "globals": {}, "next_spawn": 1}, {"scenes": {}, "globals": {}, "next_spawn": 0},
			{"scenes": {"k": {"nodes": {}, "gone": []}}, "globals": {}, "next_spawn": 1},
			{"scenes": {"k": {"nodes": {}, "gone": [], "spawned": [{"id": 1}]}}, "globals": {}, "next_spawn": 1},
			{"scenes": {}, "globals": {"profile": 3}, "next_spawn": 1}]:
		assert_eq(store.from_dict(bad).code, StrongboxWorldStore.E_BAD_DATA, str(bad))
	assert_eq(store.globals, {"profile": {"a": 1}}, "a refused load changes nothing")
	store.clear()
	assert_eq(store.to_dict(), {"scenes": {}, "globals": {}, "next_spawn": 1})


func _with_watcher(room: Node3D, store: StrongboxWorldStore) -> Node3D:
	var watcher: StrongboxSceneWatcher = StrongboxSceneWatcher.new()
	watcher.store = store
	room.add_child(watcher)
	return room
