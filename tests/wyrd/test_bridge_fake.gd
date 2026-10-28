extends GutTest

## StrongboxWyrdBridge against a fake Wyrd facade: install checks, the guard, capture and restore
## data, failed reports, warnings, and the stable-API-only rule.

const Rig: GDScript = preload("res://tests/wyrd/service_rig.gd")
const FakeWyrd: GDScript = preload("res://tests/wyrd/fake_wyrd.gd")
const BRIDGE_SOURCE: String = "res://addons/strongbox_wyrd/wyrd_bridge.gd"

var _root: String = ""
var _service: StrongboxService = null
var _wyrd: Node = null
var _bridge: StrongboxWyrdBridge = null


func before_each() -> void:
	_root = "%s%d_%d" % [Rig.ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_service = Rig.make(self, _root)
	autofree(_service)
	_wyrd = FakeWyrd.new()
	add_child_autofree(_wyrd)
	_wyrd.state = {"facts": {"cellar.lever_pulled": true}, "quests": {"cellar_chest": {"stage": "open_chest"}}}
	var installed: StrongboxResult = StrongboxWyrdBridge.install(_service, _wyrd)
	assert_true(installed.ok, str(installed))
	_bridge = installed.value


func after_each() -> void:
	Rig.delete_tree(_root)


func test_install_refuses_a_node_that_is_not_a_wyrd_facade() -> void:
	var plain: Node = autofree(Node.new())
	assert_eq(StrongboxWyrdBridge.install(_service, plain).code, StrongboxWyrdBridge.E_NOT_WYRD)
	assert_eq(StrongboxWyrdBridge.install(_service, null).code, StrongboxWyrdBridge.E_NOT_WYRD)


func test_guard_refuses_while_a_scene_is_open() -> void:
	_wyrd.scene_open = true
	assert_eq(_service.can_save()["reasons"], [StrongboxWyrdBridge.GUARD_REASON] as Array[String])
	var refused: StrongboxResult = await _service.save("slot1")
	assert_eq(refused.code, StrongboxService.E_REFUSED)
	assert_string_contains(refused.message, "A dialogue scene is open")
	assert_eq(_wyrd.save_calls, 0, "save_state is not called while refused")
	assert_null(_bridge.capture(), "capture gives no data while a scene is open")
	assert_eq(_wyrd.save_calls, 0, "nor does it call save_state, which the real Wyrd refuses with an error")
	_wyrd.scene_open = false
	assert_true((await _service.save("slot1")).ok)


func test_capture_and_restore_get_the_right_data_after_game_providers() -> void:
	var order: Array[String] = []
	_service.register_provider(&"profile", func() -> Dictionary: return {"level": 2},
		func(_data: Dictionary) -> void: order.append("profile"))
	_wyrd.on_load = func() -> void: order.append("wyrd")
	var saved: StrongboxResult = await _service.save("slot1")
	assert_true(saved.ok, str(saved))
	assert_eq(_wyrd.save_calls, 1)
	_service.world.globals.clear()
	var loaded: StrongboxResult = await _service.load("slot1")
	assert_true(loaded.ok, str(loaded))
	assert_eq(_wyrd.loaded, [_wyrd.state] as Array[Dictionary], "load_state gets exactly what save_state gave")
	assert_eq(order, ["profile", "wyrd"] as Array[String], "priority 100 restores after a game provider at 0")
	assert_eq(_bridge.last_result.value["warnings"], [] as Array[String])


func test_failed_report_fails_the_restore_with_wyrd_codes() -> void:
	_wyrd.next_report = FakeWyrd.report(false, {&"E_SAVE_SCHEMA": &"error", &"W_KEPT_ID": &"warning"})
	var restored: StrongboxResult = _bridge.restore(_wyrd.state)
	assert_push_error("E_SAVE_SCHEMA")
	assert_eq(restored.code, &"E_PROVIDER")
	assert_string_contains(restored.message, "E_SAVE_SCHEMA")
	assert_eq(restored.value["codes"], ["E_SAVE_SCHEMA"] as Array[String])
	_wyrd.next_report = FakeWyrd.report(true, {&"E_ROW": &"error"})
	assert_eq(_bridge.restore(_wyrd.state).code, &"E_PROVIDER", "an ok report with errors still fails")
	assert_push_error("E_ROW")


func test_warnings_are_passed_through_and_empty_data_is_skipped() -> void:
	_wyrd.next_report = FakeWyrd.report(true, {&"W_UNKNOWN_FACT": &"warning"})
	var restored: StrongboxResult = _bridge.restore(_wyrd.state)
	assert_true(restored.ok)
	assert_eq(restored.value["warnings"], ["W_UNKNOWN_FACT"] as Array[String])
	var skipped: StrongboxResult = _bridge.restore({})
	assert_true(skipped.ok and skipped.value["skipped"], "a save without Wyrd data leaves Wyrd alone")
	assert_eq(_wyrd.loaded.size(), 1)
	assert_eq(_bridge.validate({}), "")
	assert_ne(_bridge.validate([1]), "")


func test_bridge_uses_only_the_stable_wyrd_api() -> void:
	var source: String = FileAccess.get_file_as_string(BRIDGE_SOURCE)
	assert_ne(source, "")
	assert_false(source.contains("WyrdSave"), "the bridge must not use WyrdSave internals")
	for call: String in RegEx.create_from_string("call\\(&\"(\\w+)\"").search_all(source).map(func(m: RegExMatch) -> String: return m.get_string(1)):
		assert_has(["can_save", "save_state", "load_state", "error_count"], call, "only stable facade and report calls")


func test_zz_test_folders_are_cleaned_up() -> void:
	var leftovers: Array[String] = []
	for dir: String in DirAccess.get_directories_at("user://"):
		if ("user://" + dir).begins_with(Rig.ROOT_PREFIX) and "user://" + dir != _root:
			leftovers.append(dir)
	assert_eq(leftovers, [] as Array[String])
