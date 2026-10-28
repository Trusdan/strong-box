extends GutTest

## The example project, headless: its scenes open, and a save then a load through the example's
## own nodes brings back the chest, the taken coin, the lever, the dropped crate and the coins.

const MAIN: PackedScene = preload("res://example/main.tscn")
const ROOT_PREFIX: String = "user://strongbox_example_test_"

var _root: String = ""
var _example: Node = null


func before_each() -> void:
	_root = "%s%d_%d" % [ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_example = MAIN.instantiate()
	_example.save_root = _root
	add_child_autofree(_example)
	assert_true(await wait_until(func() -> bool: return _example.is_started(), 5), "the example starts in a room")


func after_each() -> void:
	_delete_tree(_root)


func _delete_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_delete_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func test_example_scenes_open() -> void:
	assert_eq(_example.room().name, "Hub")
	for path: String in ["res://example/rooms/hub.tscn", "res://example/rooms/cellar.tscn", "res://example/items/crate.tscn"]:
		var scene: Node = (load(path) as PackedScene).instantiate()
		assert_not_null(scene, path)
		scene.free()


func test_save_then_load_round_trip_with_the_example_nodes() -> void:
	_example.drop_crate()
	var crate_at: Vector3 = (_example.room().get_node("Items").get_child(0) as Node3D).position
	await _example.go_to(_example.CELLAR)
	_example.open_chest()
	_example.take_coin()
	_example.pull_lever()
	await _example.go_to(_example.HUB)
	_example.rest_in_bed() # Saves to the quicksave slot.
	assert_true(_example.strongbox.slots.exists("quick"))

	# Change everything after the save.
	_example.room().get_node("Items").get_child(0).free()
	_example.coins = 99
	await _example.go_to(_example.CELLAR)
	_example.pull_lever()

	var loaded: StrongboxResult = await _example.load_slot("quick")
	assert_true(loaded.ok, str(loaded))
	assert_eq(_example.room().name, "Hub", "the bed is in the Hub")
	assert_eq(_example.coins, 1, "the coin taken before the save")
	var crates: Array[Node] = _example.room().get_node("Items").get_children()
	assert_eq(crates.size(), 1, "the dropped crate is back")
	assert_eq((crates[0] as Node3D).position, crate_at)
	await _example.go_to(_example.CELLAR)
	var cellar: Node = _example.room()
	assert_true(cellar.get_node("Chest").opened, "the chest stays open")
	assert_true(cellar.get_node("Lever").pulled, "the lever is as it was when saved")
	assert_true(cellar.get_node("Coin").is_queued_for_deletion(), "the coin stays taken")


func test_autosave_on_room_change_slot_list_and_guard() -> void:
	await _example.go_to(_example.CELLAR)
	assert_true(_example.strongbox.slots.exists("auto_0"), "changing room autosaves")
	var arrived: Array[bool] = [false]
	var start: Callable = func() -> void:
		await _example.go_to(_example.HUB)
		arrived[0] = true
	start.call() # Waits a frame in the middle of the room change.
	var refused: StrongboxResult = _example.strongbox.save("slot9")
	assert_eq(refused.code, StrongboxService.E_REFUSED, "no saving while travelling")
	# Wait for the whole room change, not just the new room: the guard is on until it ends.
	assert_true(await wait_until(func() -> bool: return arrived[0], 5), "the room change finishes")
	assert_true(_example.save_slot("slot1").ok)
	assert_true(_example.strongbox.slots.exists("slot1"))
	_example.delete_slot("slot1")
	assert_false(_example.strongbox.slots.exists("slot1"))


func test_the_example_migration_upgrades_a_version_1_save() -> void:
	var v1_body: Dictionary = {"world": {"scenes": {}, "globals": {"player": {"gold": 7}}, "next_spawn": 1}, "current_scene": _example.HUB}
	var text: String = StrongboxEnvelope.pack(v1_body, {}, 1).value
	assert_true(_example.strongbox.slots.write("old", text).ok)
	var loaded: StrongboxResult = await _example.load_slot("old")
	assert_true(loaded.ok, str(loaded))
	assert_eq(loaded.value["migrated"], [{"from": 1, "to": 2}])
	assert_eq(_example.coins, 7, "gold became coins")


func test_zz_test_folders_are_cleaned_up() -> void:
	var leftovers: Array[String] = []
	for dir: String in DirAccess.get_directories_at("user://"):
		if ("user://" + dir).begins_with(ROOT_PREFIX) and "user://" + dir != _root:
			leftovers.append(dir)
	assert_eq(leftovers, [] as Array[String])
