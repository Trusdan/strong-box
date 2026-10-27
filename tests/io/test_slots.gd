extends GutTest

## StrongboxSlots: slots, metadata, autosave ring, listing, deletion and thumbnails.

const TEST_ROOT_PREFIX: String = "user://strongbox_slots_test_"
const FIXED_TIME: int = 1767225600

var _root: String = ""
var _slots: StrongboxSlots = null


func before_each() -> void:
	_root = "%s%d_%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_slots = StrongboxSlots.new()
	_slots.store.root = _root


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


## A save text whose body records [param n], saved at [param saved_unix].
func _save(n: int, saved_unix: int = FIXED_TIME) -> String:
	return StrongboxEnvelope.pack({"n": n, "room": "Cellar"}, {"location": "Cellar"}, 2, "0.1.0", n * 10.0, saved_unix).value


func _n_in(slot_id: String) -> int:
	return _slots.read(slot_id).value["save"]["body"]["n"]


func _ids(entries: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(entry["slot_id"])
	return ids


func _write_raw(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_manual_quick_and_autosave_ring() -> void:
	for slot_id: String in ["manual_a", "manual_b", "manual_c"]:
		assert_true(_slots.write(slot_id, _save(1)).ok)
	assert_true(_slots.write(StrongboxSlots.QUICK_ID, _save(2)).ok)
	var used: Array[String] = []
	for n: int in range(10, 15): # five autosaves in the same second; the write order decides
		var slot_id: String = _slots.next_autosave_id()
		used.append(slot_id)
		assert_true(_slots.write(slot_id, _save(n)).ok)
	assert_eq(used, ["auto_0", "auto_1", "auto_2", "auto_0", "auto_1"] as Array[String])
	var auto_folders: Array[String] = []
	for dir: String in DirAccess.get_directories_at(_root):
		if dir.begins_with(StrongboxSlots.AUTO_PREFIX):
			auto_folders.append(dir)
	auto_folders.sort()
	assert_eq(auto_folders, ["auto_0", "auto_1", "auto_2"] as Array[String], "exactly three autosave folders")
	assert_eq(_n_in("auto_0"), 13, "the oldest autosave was overwritten")
	assert_eq(_n_in("auto_1"), 14)
	assert_eq(_n_in("auto_2"), 12)
	assert_eq(_slots.next_autosave_id(), "auto_2", "the next autosave replaces the oldest")
	assert_eq(_slots.list().size(), 7)


func test_kinds_metadata_and_labels() -> void:
	assert_true(_slots.write("manual_a", _save(1, FIXED_TIME + 5)).ok)
	var written: StrongboxResult = _slots.write("quick", _save(2), {"location": "Hub", "note": &"quick"})
	assert_true(written.ok)
	assert_true(_slots.write("auto_0", _save(3)).ok)
	var by_id: Dictionary = {}
	for entry: Dictionary in _slots.list():
		by_id[entry["slot_id"]] = entry
	assert_eq(by_id["manual_a"]["kind"], "manual")
	assert_eq(by_id["quick"]["kind"], "quick")
	assert_eq(by_id["auto_0"]["kind"], "auto")
	var manual: Dictionary = by_id["manual_a"]
	assert_eq(manual["saved_unix"], FIXED_TIME + 5)
	assert_eq(manual["playtime_s"], 10.0)
	assert_eq(manual["schema_version"], 2)
	assert_eq(manual["game_version"], "0.1.0")
	assert_eq(manual["label"], {"location": "Cellar"}, "the label defaults to the save header's meta")
	assert_eq(manual["damaged"], false)
	assert_eq(by_id["quick"]["label"], {"location": "Hub", "note": &"quick"}, "a label passed to write() wins")
	assert_eq(written.value["slot_id"], "quick")


func test_list_order_and_latest() -> void:
	assert_eq(_slots.list(), [] as Array[Dictionary], "an empty (missing) root lists nothing")
	assert_eq(_slots.latest(), {})
	assert_true(_slots.write("middle", _save(1, FIXED_TIME + 10)).ok)
	assert_true(_slots.write("newest", _save(2, FIXED_TIME + 20)).ok)
	assert_true(_slots.write("oldest", _save(3, FIXED_TIME)).ok)
	assert_true(_slots.write("same_second_later", _save(4, FIXED_TIME)).ok)
	assert_eq(_ids(_slots.list()), ["newest", "middle", "same_second_later", "oldest"] as Array[String])
	assert_eq(_slots.latest()["slot_id"], "newest")
	DirAccess.make_dir_recursive_absolute(_root.path_join("empty_folder"))
	DirAccess.make_dir_recursive_absolute(_root.path_join("Not A Slot"))
	assert_eq(_slots.list().size(), 4, "folders that are not valid slots are skipped")


func test_damaged_meta_is_rebuilt_from_save_header() -> void:
	assert_true(_slots.write("cellar", _save(7, FIXED_TIME + 3), {"location": "Cellar"}).ok)
	var meta_path: String = _slots.store.resolve("cellar/meta.json")
	for damage: String in ["{broken", ""]:
		_write_raw(meta_path, damage)
		_slots._save_reads = 0
		var entry: Dictionary = _slots.list()[0]
		assert_eq(_slots._save_reads, 1, "the save was read once to rebuild meta.json")
		assert_eq(entry["slot_id"], "cellar")
		assert_eq(entry["saved_unix"], FIXED_TIME + 3)
		assert_eq(entry["damaged"], false)
		_slots._save_reads = 0
		_slots.list()
		assert_eq(_slots._save_reads, 0, "the rebuilt meta.json is written back and used next time")
	DirAccess.remove_absolute(meta_path)
	assert_eq(_slots.list()[0]["slot_id"], "cellar", "a missing meta.json is rebuilt too")


func _entry(entries: Array[Dictionary], slot_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["slot_id"] == slot_id:
			return entry
	return {}


func test_damaged_save_is_listed_as_damaged() -> void:
	assert_true(_slots.write("good", _save(1)).ok)
	assert_true(_slots.write("broken", _save(2)).ok) # written once, so it has no backup
	_write_raw(_slots.store.resolve("broken/save.json"), "{broken")
	DirAccess.remove_absolute(_slots.store.resolve("broken/meta.json"))
	var entries: Array[Dictionary] = _slots.list()
	assert_eq(entries.size(), 2, "the damaged slot is not hidden")
	assert_eq(_entry(entries, "broken")["damaged"], true)
	assert_eq(_entry(entries, "good")["damaged"], false)
	assert_eq(_slots.read("broken").code, StrongboxFileStore.E_NO_VALID_SAVE)


func test_damaged_main_with_good_backup_recovers() -> void:
	assert_true(_slots.write("cellar", _save(1)).ok)
	assert_true(_slots.write("cellar", _save(2)).ok) # .bak1 now holds save 1
	_write_raw(_slots.store.resolve("cellar/save.json"), "{broken")
	DirAccess.remove_absolute(_slots.store.resolve("cellar/meta.json"))
	assert_eq(_slots.list()[0]["damaged"], false, "the rebuild recovers from the backup")
	var read: StrongboxResult = _slots.read("cellar")
	assert_eq(read.value["source"], "bak1")
	assert_eq(read.value["save"]["body"]["n"], 1)


func test_read_and_write_refuse_bad_ids() -> void:
	for slot_id: String in ["", "Upper", "a/b", "../escape", "dot.dot", "x".repeat(33), "space here"]:
		assert_eq(_slots.write(slot_id, _save(1)).code, StrongboxSlots.E_BAD_SLOT, "write '%s'" % slot_id)
		assert_eq(_slots.read(slot_id).code, StrongboxSlots.E_BAD_SLOT, "read '%s'" % slot_id)
		assert_eq(_slots.delete(slot_id).code, StrongboxSlots.E_BAD_SLOT, "delete '%s'" % slot_id)
		assert_false(_slots.exists(slot_id))
	assert_true(_slots.write("x".repeat(32), _save(1)).ok, "32 characters is the limit")
	assert_eq(_slots.read("missing").code, StrongboxSlots.E_NO_SLOT)
	assert_eq(_slots.write("bad_text", "not a save").code, StrongboxEnvelope.E_JSON)
	assert_false(_slots.exists("bad_text"))


func test_delete_removes_only_that_slot() -> void:
	assert_true(_slots.write("keep", _save(1)).ok)
	assert_true(_slots.write("remove_me", _save(2)).ok)
	assert_true(_slots.write_thumbnail("remove_me", Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)).ok)
	var sibling: String = _root + "_sibling"
	DirAccess.make_dir_recursive_absolute(sibling)
	_write_raw(sibling.path_join("save.json"), "outside the root")
	assert_true(_slots.delete("remove_me").ok)
	assert_false(DirAccess.dir_exists_absolute(_root.path_join("remove_me")))
	assert_false(_slots.exists("remove_me"))
	assert_true(_slots.exists("keep"))
	assert_true(FileAccess.file_exists(sibling.path_join("save.json")), "nothing outside the root is touched")
	assert_eq(_slots.delete("remove_me").code, StrongboxSlots.E_NO_SLOT)
	_delete_tree(sibling)


func test_thumbnail_round_trip() -> void:
	assert_true(_slots.write("cellar", _save(1)).ok)
	assert_null(_slots.read_thumbnail("cellar"), "a slot with no thumbnail works")
	var cases: Dictionary = {Vector2i(640, 360): Vector2i(320, 180), Vector2i(100, 50): Vector2i(100, 50), Vector2i(1000, 100): Vector2i(320, 32)}
	for size: Vector2i in cases:
		var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.6, 1.0, 1.0))
		assert_true(_slots.write_thumbnail("cellar", image).ok)
		var thumb: Image = _slots.read_thumbnail("cellar")
		assert_not_null(thumb)
		assert_eq(thumb.get_size(), cases[size], "size %s" % size)
		assert_true(thumb.get_pixel(0, 0).is_equal_approx(Color(0.2, 0.6, 1.0, 1.0)))
	_write_raw(_slots.store.resolve("cellar/thumb.png"), "not a png")
	assert_null(_slots.read_thumbnail("cellar"), "a broken thumbnail reads as none")
	assert_true(_slots.read("cellar").ok, "the save is unaffected")
	assert_eq(_slots.write_thumbnail("../x", Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)).code, StrongboxSlots.E_BAD_SLOT)


func test_listing_fifty_slots_opens_no_save() -> void:
	for i: int in 50:
		assert_true(_slots.write("slot_%02d" % i, _save(i, FIXED_TIME + i)).ok)
	_slots._save_reads = 0
	var entries: Array[Dictionary] = _slots.list()
	assert_eq(entries.size(), 50)
	assert_eq(_slots._save_reads, 0, "every meta.json is valid, so no save.json is opened")
	assert_eq(entries[0]["slot_id"], "slot_49")


func test_zz_test_folders_are_cleaned_up() -> void:
	var leftovers: Array[String] = []
	for dir: String in DirAccess.get_directories_at("user://"):
		if ("user://" + dir).begins_with(TEST_ROOT_PREFIX) and "user://" + dir != _root:
			leftovers.append(dir)
	assert_eq(leftovers, [] as Array[String])
