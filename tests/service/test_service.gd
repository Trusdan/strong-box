extends GutTest

## StrongboxService: the save and load flows, guards, busy refusals, backups, signals and playtime.
## A test scene_changer swaps the Hub and Cellar fixture rooms under a holder node.

const TEST_ROOT_PREFIX: String = "user://strongbox_service_test_"
const CELLAR_PATH: String = "res://tests/fixtures/cellar_room.tscn"
const HUB_PATH: String = "res://tests/fixtures/hub_room.tscn"
const ITEM: PackedScene = preload("res://tests/fixtures/spawn/dropped_item.tscn")
const ITEM_PATH: String = "res://tests/fixtures/spawn/dropped_item.tscn"
const DROP_AT: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(1.25, 0.0, -3.5))
const SCENES: Dictionary = {
	CELLAR_PATH: preload("res://tests/fixtures/cellar_room.tscn"),
	HUB_PATH: preload("res://tests/fixtures/hub_room.tscn"),
}

var _root: String = ""
var _service: StrongboxService = null
var _holder: Node = null
var _changes: int = 0
var _level: int = 1
var _events: Array[String] = []


func before_each() -> void:
	_root = "%s%d_%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_service = StrongboxService.new()
	_service.slots.store.root = _root
	_service.world.spawn_allow_prefixes = PackedStringArray(["res://tests/fixtures/spawn/"])
	_service.scene_changer = _change_scene
	_service.current_scene_provider = _current
	_service.register_provider(&"profile", func() -> Dictionary: return {"level": _level},
		func(data: Dictionary) -> void: _level = data.get("level", 1))
	add_child_autofree(_service)
	_service.set_process(false) # Playtime is tested by calling _process directly.
	_holder = Node.new()
	add_child_autofree(_holder)
	_changes = 0
	_level = 1
	_events = []
	for signal_name: String in ["save_started", "save_finished", "load_started", "load_finished", "load_failed"]:
		_service.connect(signal_name, func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: _events.append(signal_name))


func after_each() -> void:
	get_tree().paused = false
	_delete_tree(_root)


func _delete_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_delete_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _current() -> Node:
	return _holder.get_child(0) if _holder.get_child_count() > 0 else null


## The test scene_changer: frees the current room, adds the new one and waits a frame.
func _change_scene(scene_key: String) -> Node:
	_changes += 1
	var old: Node = _current()
	if old != null:
		old.free()
	var room: Node = (SCENES[scene_key] as PackedScene).instantiate()
	_holder.add_child(room)
	await get_tree().process_frame
	return room


## A normal transition in the game: stash the room being left, change, restore the new room.
func _go(scene_key: String) -> Node3D:
	if _current() != null:
		assert_true(_service.world.stash_scene(_current()).ok)
	var room: Node3D = await _change_scene(scene_key)
	assert_true(_service.world.restore_scene(room).ok)
	return room


func _chest() -> Node3D:
	return _current().get_node("Props/Chest01")


func _corrupt(file: String) -> void:
	var handle: FileAccess = FileAccess.open(_service.slots.store.resolve("slot1/" + file), FileAccess.WRITE)
	handle.store_string("{ not a save")
	handle.close()


func test_full_round_trip_matches_the_saved_moment() -> void:
	var hub: Node3D = await _go(HUB_PATH)
	var item: Node3D = ITEM.instantiate()
	item.item_name = "rope"
	hub.get_node("Items").add_child(item)
	item.transform = DROP_AT
	assert_true(_service.world.register_spawned(item, ITEM_PATH, hub).ok)
	var cellar: Node3D = await _go(CELLAR_PATH)
	_chest().opened = true
	_chest().gold = 4
	_service.world.registry.mark_gone(cellar.get_node("Coin"))
	cellar.get_node("Coin").free()
	_level = 3
	var saved: StrongboxResult = await _service.save("slot1", {"location": "Cellar"})
	assert_true(saved.ok, str(saved))

	# Change more after saving, in both rooms and in the globals.
	_chest().gold = 99
	cellar.get_node("Props/Lever").on = true
	_level = 7
	var hub_later: Node3D = await _go(HUB_PATH)
	hub_later.get_node("Items").get_child(0).free()
	# This room stashes itself when the load leaves it; the loaded state must win.
	var watcher: StrongboxSceneWatcher = StrongboxSceneWatcher.new()
	watcher.restore_on_ready = false
	hub_later.add_child(watcher)
	watcher.store = _service.world

	var loaded: StrongboxResult = await _service.load("slot1")
	assert_true(loaded.ok, str(loaded))
	assert_eq(loaded.value["source"], "main")
	assert_eq(_current().scene_file_path, CELLAR_PATH, "the current scene is Cellar")
	assert_eq([_chest().opened, _chest().gold], [true, 4])
	assert_eq(_current().get_node("Props/Lever").on, false)
	assert_true(_current().get_node("Coin").is_queued_for_deletion(), "the coin stays taken")
	assert_eq(_level, 3, "globals are restored")
	var hub_again: Node3D = await _go(HUB_PATH)
	var items: Array[Node] = hub_again.get_node("Items").get_children()
	assert_eq(items.size(), 1, "the dropped item is back in the Hub")
	assert_eq((items[0] as Node3D).transform, DROP_AT)


func test_refusing_guard_blocks_the_save_and_writes_nothing() -> void:
	await _go(CELLAR_PATH)
	watch_signals(_service)
	_service.add_save_guard(&"cutscene", func() -> String: return "a cutscene is playing")
	_service.add_save_guard(&"menu", func() -> String: return "")
	assert_eq(_service.can_save(), {"ok": false, "reasons": ["a cutscene is playing"] as Array[String]})
	var refused: StrongboxResult = await _service.save("slot1")
	assert_eq(refused.code, StrongboxService.E_REFUSED)
	assert_string_contains(refused.message, "a cutscene is playing")
	assert_false(_service.slots.exists("slot1"), "nothing is written")
	assert_signal_not_emitted(_service, "save_started")
	_service.remove_save_guard(&"cutscene")
	assert_true((await _service.save("slot1")).ok)


func test_failed_save_leaves_the_world_store_unchanged() -> void:
	await _go(CELLAR_PATH)
	_chest().opened = true
	var before: Dictionary = _service.world.to_dict()
	var failed: StrongboxResult = await _service.save("Not A Slot!")
	assert_eq(failed.code, StrongboxSlots.E_BAD_SLOT)
	assert_eq(_service.world.to_dict(), before, "the stash and captured globals were rolled back")
	assert_eq(_events, ["save_started", "save_finished"] as Array[String])
	_holder.get_child(0).free()
	assert_eq((await _service.save("slot1")).code, StrongboxService.E_NO_SCENE)


func test_saving_or_loading_while_busy_is_refused() -> void:
	await _go(CELLAR_PATH)
	assert_true((await _service.save("slot1")).ok)
	var start_load: Callable = func() -> void: await _service.load("slot1")
	start_load.call() # Runs until the scene_changer waits for a frame.
	assert_eq((await _service.save("slot2")).code, StrongboxService.E_BUSY)
	assert_eq((await _service.load("slot1")).code, StrongboxService.E_BUSY)
	assert_eq(_service.new_game().code, StrongboxService.E_BUSY)
	assert_true(await wait_for_signal(_service.load_finished, 5), "the first load ends")
	await get_tree().process_frame # Leave the signal emission before going on.
	assert_true((await _service.save("slot2")).ok, "free again once the load ends")

	# A provider that tries to save from inside a save is refused too.
	var inner: Array[StrongboxResult] = []
	_service.register_provider(&"sneaky", func() -> Dictionary:
		inner.append(_service.save("slot3"))
		return {}, func(_data: Dictionary) -> void: pass)
	assert_true((await _service.save("slot2")).ok)
	assert_eq(inner[0].code, StrongboxService.E_BUSY)


func test_corrupted_save_falls_back_and_no_valid_save_leaves_the_game_untouched() -> void:
	await _go(CELLAR_PATH)
	_chest().gold = 1
	assert_true((await _service.save("slot1")).ok)
	_chest().gold = 2
	assert_true((await _service.save("slot1")).ok)
	_corrupt("save.json")
	var fallback: StrongboxResult = await _service.load("slot1")
	assert_true(fallback.ok, str(fallback))
	assert_eq(fallback.value["source"], "bak1", "the result says a backup was used")
	assert_eq(fallback.value["failures"].size(), 1)
	assert_eq(_chest().gold, 1, "the backup holds the earlier save")

	_corrupt("save.json.bak1")
	_chest().gold = 5
	var room: Node = _current()
	var world_before: Dictionary = _service.world.to_dict()
	var changes_before: int = _changes
	watch_signals(_service)
	var failed: StrongboxResult = await _service.load("slot1")
	assert_eq(failed.code, StrongboxFileStore.E_NO_VALID_SAVE)
	assert_signal_emitted_with_parameters(_service, "load_failed", ["slot1", failed.code, failed.message])
	assert_eq(_current(), room, "the same room is still loaded")
	assert_eq(_chest().gold, 5)
	assert_eq(_service.world.to_dict(), world_before)
	assert_eq(_changes, changes_before, "no scene change was asked for")


func test_newer_schema_or_invalid_globals_are_refused_before_any_live_change() -> void:
	await _go(CELLAR_PATH)
	_service.migrations.current_version = 2
	_level = 5
	assert_true((await _service.save("slot1")).ok)
	_service.migrations.current_version = 1
	_level = 6
	var changes_before: int = _changes
	var newer: StrongboxResult = await _service.load("slot1")
	assert_eq(newer.code, StrongboxMigrations.E_SCHEMA_TOO_NEW)
	assert_eq([_changes, _level], [changes_before, 6], "nothing live changed")

	_service.migrations.current_version = 2
	_service.register_provider(&"profile", func() -> Dictionary: return {"level": _level},
		func(data: Dictionary) -> void: _level = data["level"], 0,
		func(data: Dictionary) -> String: return "" if data.get("level", 0) < 5 else "level too high")
	var invalid: StrongboxResult = await _service.load("slot1")
	assert_eq(invalid.code, StrongboxService.E_INVALID_GLOBALS)
	assert_string_contains(invalid.message, "profile: level too high")
	assert_eq([_changes, _level], [changes_before, 6])

	# A tampered save naming a spawn scene outside the allow-list is refused before any change.
	var record: Dictionary = {"id": "spawn_1", "parent": "Items", "scene_path": CELLAR_PATH, "transform": null, "data": {}}
	var world_data: Dictionary = {"scenes": {HUB_PATH: {"nodes": {}, "gone": [], "spawned": [record]}}, "globals": {}, "next_spawn": 2}
	var text: String = StrongboxEnvelope.pack({"world": world_data, "current_scene": HUB_PATH}, {}, 2).value
	assert_true(_service.slots.write("slot2", text).ok)
	assert_eq((await _service.load("slot2")).code, StrongboxWorldStore.E_SPAWN_PATH)
	assert_eq(_changes, changes_before)


func test_signals_fire_in_order() -> void:
	await _go(CELLAR_PATH)
	watch_signals(_service)
	var saved: StrongboxResult = await _service.save("slot1")
	var loaded: StrongboxResult = await _service.load("slot1")
	assert_signal_emitted_with_parameters(_service, "save_started", ["slot1"])
	assert_signal_emitted_with_parameters(_service, "save_finished", ["slot1", saved])
	assert_signal_emitted_with_parameters(_service, "load_finished", ["slot1", loaded])
	assert_signal_not_emitted(_service, "load_failed")
	await _service.load("slot9")
	assert_eq(_events, ["save_started", "save_finished", "load_started", "load_finished", "load_started", "load_failed"] as Array[String])


func test_playtime_counts_unpaused_time_and_survives_save_and_load() -> void:
	await _go(CELLAR_PATH)
	_service._process(0.5)
	get_tree().paused = true
	_service._process(1.0)
	get_tree().paused = false
	assert_eq(_service.playtime_s, 0.5, "paused time is not counted")
	_service.playtime_s = 42.25
	assert_true((await _service.save("slot1")).ok)
	assert_eq(_service.slots.list()[0]["playtime_s"], 42.25, "saved in the header")
	_service.playtime_s = 100.0
	assert_true((await _service.load("slot1")).ok)
	assert_eq(_service.playtime_s, 42.25)
	_service.new_game()
	assert_eq([_service.playtime_s, _service.world.to_dict()["scenes"]], [0.0, {}])


func test_every_service_code_has_a_message() -> void:
	for code: StringName in [StrongboxService.E_BUSY, StrongboxService.E_REFUSED, StrongboxService.E_NO_SCENE,
			StrongboxService.E_BAD_BODY, StrongboxService.E_INVALID_GLOBALS, StrongboxService.E_SCENE_CHANGE,
			StrongboxFileStore.E_NO_VALID_SAVE, StrongboxMigrations.E_SCHEMA_TOO_NEW, StrongboxSlots.E_NO_SLOT]:
		assert_ne(StrongboxService.message_for(code), "", str(code))
	assert_eq(StrongboxService.message_for(&"E_NOT_A_CODE"), "")


func test_zz_test_folders_are_cleaned_up() -> void:
	var leftovers: Array[String] = []
	for dir: String in DirAccess.get_directories_at("user://"):
		if ("user://" + dir).begins_with(TEST_ROOT_PREFIX) and "user://" + dir != _root:
			leftovers.append(dir)
	assert_eq(leftovers, [] as Array[String])
