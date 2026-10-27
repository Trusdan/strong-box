extends GutTest

## StrongboxFileStore: atomic writes, backups, fault injection, recovery and path safety.

const TEST_ROOT_PREFIX: String = "user://strongbox_test_"
const FIXED_TIME: int = 1767225600

var _root: String = ""
var _store: StrongboxFileStore = null


func before_each() -> void:
	_root = "%s%d_%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_store = StrongboxFileStore.new()
	_store.root = _root


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


## A valid save text whose body records [param n].
func _save(n: int) -> String:
	return StrongboxEnvelope.pack({"n": n, "room": "Cellar"}, {}, 1, "", 0.0, FIXED_TIME).value


func _n_of(result: StrongboxResult) -> int:
	return result.value["save"]["body"]["n"]


func _write_raw(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read_raw(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_write_then_read_returns_same_text() -> void:
	var written: StrongboxResult = _store.write_atomic("slot/save.json", _save(1))
	assert_true(written.ok, str(written))
	assert_eq(written.value, _root + "/slot/save.json")
	var read: StrongboxResult = _store.read_verified("slot/save.json")
	assert_true(read.ok, str(read))
	assert_eq(read.value["text"], _save(1))
	assert_eq(read.value["source"], "main")
	assert_eq(read.value["failures"], [])
	assert_false(FileAccess.file_exists(_root + "/slot/save.json.tmp"), "no temp file is left after a write")


func test_each_failure_point_keeps_previous_save() -> void:
	var expected: Dictionary = {
		&"space": StrongboxFileStore.E_DISK, &"write": StrongboxFileStore.E_WRITE,
		&"verify": StrongboxFileStore.E_VERIFY, &"rotate": StrongboxFileStore.E_RENAME,
		&"rename": StrongboxFileStore.E_RENAME,
	}
	for step: StringName in expected:
		var path: String = "fault_%s/save.json" % step
		assert_true(_store.write_atomic(path, _save(1)).ok)
		assert_true(_store.write_atomic(path, _save(2)).ok)
		_store._fail_at = step
		var failed: StrongboxResult = _store.write_atomic(path, _save(3))
		_store._fail_at = &""
		assert_false(failed.ok, "%s should fail" % step)
		assert_eq(failed.code, expected[step], str(step))
		var read: StrongboxResult = _store.read_verified(path)
		assert_true(read.ok, "%s: %s" % [step, read])
		assert_eq(_n_of(read), 2, "%s: the previous good save must still load" % step)
		assert_true(_store.write_atomic(path, _save(4)).ok, "%s: the next write works" % step)
		assert_eq(_n_of(_store.read_verified(path)), 4)


func test_rename_failure_is_rolled_back_to_main() -> void:
	assert_true(_store.write_atomic("save.json", _save(1)).ok)
	_store._fail_at = &"rename"
	assert_false(_store.write_atomic("save.json", _save(2)).ok)
	_store._fail_at = &""
	var read: StrongboxResult = _store.read_verified("save.json")
	assert_eq(read.value["source"], "main", "the previous file is moved back into place")
	assert_eq(_n_of(read), 1)
	assert_false(FileAccess.file_exists(_root + "/save.json.tmp"))


func test_unverifiable_text_is_refused_and_previous_kept() -> void:
	assert_true(_store.write_atomic("save.json", _save(1)).ok)
	var result: StrongboxResult = _store.write_atomic("save.json", "not a save")
	assert_eq(result.code, StrongboxFileStore.E_VERIFY)
	assert_eq(_n_of(_store.read_verified("save.json")), 1)
	assert_false(FileAccess.file_exists(_root + "/save.json.tmp"))


func test_damaged_main_falls_back_to_bak1() -> void:
	var good: String = _save(2)
	var damage: Dictionary = {
		"truncated": good.substr(0, good.length() >> 1),
		"empty": "",
		"changed byte": good.replace("\"room\":\"Cellar\"", "\"room\":\"Cellas\""),
	}
	for label: String in damage:
		var path: String = "damage_%s/save.json" % label.replace(" ", "_")
		assert_true(_store.write_atomic(path, _save(1)).ok)
		assert_true(_store.write_atomic(path, good).ok)
		_write_raw(_store.resolve(path), damage[label])
		var read: StrongboxResult = _store.read_verified(path)
		assert_true(read.ok, "%s: %s" % [label, read])
		assert_eq(read.value["source"], "bak1", label)
		assert_eq(_n_of(read), 1, label)
		assert_eq(read.value["failures"].size(), 1, label)
		assert_eq(read.value["failures"][0]["file"], _store.resolve(path), label)


func test_no_valid_file_reports_every_failure() -> void:
	for n: int in [1, 2, 3]:
		assert_true(_store.write_atomic("save.json", _save(n)).ok)
	var full: String = _store.resolve("save.json")
	for path: String in [full, full + ".bak1", full + ".bak2"]:
		_write_raw(path, "{broken")
	var read: StrongboxResult = _store.read_verified("save.json")
	assert_eq(read.code, StrongboxFileStore.E_NO_VALID_SAVE)
	assert_eq(read.value["failures"].size(), 3)
	assert_eq(_store.read_verified("missing.json").code, StrongboxFileStore.E_NO_VALID_SAVE)


func test_backup_counts() -> void:
	for count: int in [0, 1, 3]:
		_store.backup_count = count
		var path: String = "count_%d/save.json" % count
		for n: int in range(1, 6):
			assert_true(_store.write_atomic(path, _save(n)).ok, "count %d write %d" % [count, n])
		var full: String = _store.resolve(path)
		for i: int in range(1, count + 1):
			var backup: String = "%s.bak%d" % [full, i]
			assert_true(FileAccess.file_exists(backup), "count %d: %s exists" % [count, backup])
			assert_eq(StrongboxEnvelope.unpack(_read_raw(backup)).value["body"]["n"], 5 - i, "count %d: bak%d" % [count, i])
		assert_false(FileAccess.file_exists("%s.bak%d" % [full, count + 1]), "count %d: no extra backup" % count)
		_write_raw(full, "")
		var read: StrongboxResult = _store.read_verified(path)
		if count == 0:
			assert_eq(read.code, StrongboxFileStore.E_NO_VALID_SAVE, "no backup to fall back to")
		else:
			assert_eq(read.value["source"], "bak1")
			assert_eq(_n_of(read), 4)
	_store.backup_count = 2


func test_crash_leftover_tmp_is_ignored_and_replaced() -> void:
	assert_true(_store.write_atomic("save.json", _save(1)).ok)
	_store._fail_at = &"write"
	_store.write_atomic("save.json", _save(2))
	_store._fail_at = &""
	var tmp: String = _store.resolve("save.json") + ".tmp"
	assert_true(FileAccess.file_exists(tmp), "the simulated crash leaves a temp file")
	var read: StrongboxResult = _store.read_verified("save.json")
	assert_eq(_n_of(read), 1, "the temp file is ignored on read")
	assert_true(FileAccess.file_exists(tmp), "a temp file not older than the main file is kept on read")
	assert_true(_store.write_atomic("save.json", _save(3)).ok)
	assert_false(FileAccess.file_exists(tmp), "the next write replaces it")


func test_stale_tmp_older_than_main_is_cleaned_up() -> void:
	var full: String = _store.resolve("save.json")
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	_write_raw(full + ".tmp", "stale")
	OS.delay_msec(1100) # modification times have one-second resolution
	_write_raw(full, _save(1))
	var other: String = full.get_base_dir().path_join("notes.txt")
	_write_raw(other, "not ours")
	assert_true(_store.read_verified("save.json").ok)
	assert_false(FileAccess.file_exists(full + ".tmp"), "the stale temp file is deleted")
	assert_true(FileAccess.file_exists(other), "nothing else is deleted")


func test_paths_outside_root_are_refused() -> void:
	var bad: Array[String] = [
		"", "../escape.json", "slot/../../escape.json", "user://elsewhere/save.json",
		"res://save.json", "/tmp/save.json", "slot\\save.json", "C:/save.json", _root,
		_root + "_sibling/save.json",
	]
	for path: String in bad:
		assert_eq(_store.write_atomic(path, _save(1)).code, StrongboxFileStore.E_BAD_PATH, "write '%s'" % path)
		assert_eq(_store.read_verified(path).code, StrongboxFileStore.E_BAD_PATH, "read '%s'" % path)
	assert_false(DirAccess.dir_exists_absolute("user://elsewhere"))
	assert_true(_store.write_atomic(_root + "/abs/save.json", _save(1)).ok, "an absolute path inside root is fine")
	assert_true(_store.write_atomic("a/./b/../save.json", _save(1)).ok, "paths are simplified")
	assert_eq(_store.resolve("a/./b/../save.json"), _root + "/a/save.json")


func test_zz_test_folders_are_cleaned_up() -> void:
	# Runs last in this file: every earlier test's folder was removed by after_each.
	var leftovers: Array[String] = []
	for dir: String in DirAccess.get_directories_at("user://"):
		if ("user://" + dir).begins_with(TEST_ROOT_PREFIX) and "user://" + dir != _root:
			leftovers.append(dir)
	assert_eq(leftovers, [] as Array[String])
