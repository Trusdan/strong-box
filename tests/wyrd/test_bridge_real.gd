extends GutTest

## StrongboxWyrdBridge against the pinned Wyrd release (addons/wyrd/) and the neutral pack in
## tests/wyrd_fixtures/: a fact and a quest stage survive save, reset and load, and saving is
## refused while a scene is open.

const Rig: GDScript = preload("res://tests/wyrd/service_rig.gd")
const WyrdFacade: GDScript = preload("res://addons/wyrd/runtime/wyrd.gd")
const Manifest: GDScript = preload("res://addons/wyrd/compiler/wyrd_content_manifest.gd")
const PACK: String = "res://tests/wyrd_fixtures/cellar.wyrd"
const QUEST: String = "cellar_chest"
const FACT: StringName = &"cellar.lever_pulled"

var _root: String = ""
var _service: StrongboxService = null
var _wyrd: Node = null
var _bridge: StrongboxWyrdBridge = null


func before_each() -> void:
	_root = "%s%d_%d" % [Rig.ROOT_PREFIX, Time.get_ticks_usec(), randi()]
	_service = Rig.make(self, _root)
	autofree(_service)
	_wyrd = WyrdFacade.new()
	add_child_autofree(_wyrd)
	var manifest: Resource = Manifest.new()
	manifest.set(&"pack_id", &"cellar")
	manifest.set(&"files", PackedStringArray([PACK]))
	var content: RefCounted = _wyrd.call(&"load_content", manifest)
	assert_true(bool(content.get(&"ok")), "the test pack compiles")
	_new_game()
	_bridge = StrongboxWyrdBridge.install(_service, _wyrd).value


func after_each() -> void:
	Rig.delete_tree(_root)


func _new_game() -> void:
	_wyrd.call(&"start_new_game", 1)
	_wyrd.call(&"tick", 1.0)


## The quest stage and the fact, read from Wyrd's own save dictionary.
func _state() -> Array:
	var saved: Dictionary = _wyrd.call(&"save_state")
	return [saved["quests"][QUEST]["stage"], saved["facts"]["world"].get(str(FACT))]


func test_fact_and_quest_stage_survive_save_reset_and_load() -> void:
	watch_signals(_wyrd)
	assert_eq(_state(), ["find_lever", null])
	assert_true(_wyrd.get(&"facts").call(&"set_in", FACT, true))
	_wyrd.call(&"tick", 1.0)
	assert_signal_emitted_with_parameters(_wyrd, "stage_changed", [QUEST, "open_chest"])
	assert_eq(_state(), ["open_chest", true], "the quest reached stage 2")
	var saved: StrongboxResult = await _service.save("slot1")
	assert_true(saved.ok, str(saved))

	_new_game()
	assert_eq(_state(), ["find_lever", null], "reset")
	var loaded: StrongboxResult = await _service.load("slot1")
	assert_true(loaded.ok, str(loaded))
	assert_eq(_state(), ["open_chest", true], "the fact and the stage are back")
	assert_true(_bridge.last_result.ok, str(_bridge.last_result))
	assert_true(bool(_bridge.last_report.get(&"ok")))


func test_saving_while_a_scene_is_open_is_refused_with_the_guard_reason() -> void:
	_wyrd.get(&"dialogue").call(&"open_scene", "cellar.greeting")
	assert_false(bool(_wyrd.call(&"can_save")))
	var refused: StrongboxResult = await _service.save("slot1")
	assert_eq(refused.code, StrongboxService.E_REFUSED)
	assert_string_contains(refused.message, StrongboxWyrdBridge.GUARD_REASON)
	assert_false(_service.slots.exists("slot1"))
	_wyrd.get(&"dialogue").call(&"abort", &"test")
	assert_true((await _service.save("slot1")).ok, "allowed again once the scene is closed")
