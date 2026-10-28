extends Node

## The Strongbox example: a Hub and a Cellar room, a chest, a coin, a lever, a bed that saves,
## an autosave on every room change, a dropped crate, and a slot list with Save, Load and Delete.
## The rooms are its own scenes; this script plays the part of the game.

const HUB: String = "res://example/rooms/hub.tscn"
const CELLAR: String = "res://example/rooms/cellar.tscn"
const ROOMS: Dictionary = {HUB: preload("res://example/rooms/hub.tscn"), CELLAR: preload("res://example/rooms/cellar.tscn")}
const CRATE: PackedScene = preload("res://example/items/crate.tscn")
const CRATE_PATH: String = "res://example/items/crate.tscn"

## Where the example keeps its saves. Tests point it somewhere else.
@export var save_root: String = "user://strongbox_example"

## The service. A game would usually make this an autoload named Strongbox.
var strongbox: StrongboxService = StrongboxService.new()
## Coins the player carries (saved through the "player" provider).
var coins: int = 0

var _room: Node3D = null
var _changing: bool = false
var _holder: Node3D = Node3D.new()
var _info: Label = Label.new()
var _status: Label = Label.new()
var _actions: HBoxContainer = HBoxContainer.new()
var _slot_list: ItemList = ItemList.new()


func _ready() -> void:
	strongbox.slots.store.root = save_root
	strongbox.game_version = "0.1.0"
	strongbox.world.spawn_allow_prefixes = PackedStringArray(["res://example/items/"])
	strongbox.scene_changer = _change_room
	strongbox.current_scene_provider = func() -> Node: return _room
	strongbox.register_provider(&"player", func() -> Dictionary: return {"coins": coins},
		func(data: Dictionary) -> void: coins = data.get("coins", 0))
	# No saving while walking between rooms.
	strongbox.add_save_guard(&"travelling", func() -> String: return "travelling between rooms" if _changing else "")
	# Version 1 of this example stored the player's coins as "gold".
	strongbox.migrations.current_version = 2
	strongbox.migrations.register(1, func(body: Dictionary) -> Dictionary:
		var player: Dictionary = body["world"]["globals"].get("player", {})
		if player.has("gold"):
			player["coins"] = player["gold"]
			player.erase("gold")
		return body)
	add_child(strongbox)
	add_child(_holder)
	_build_ui()
	strongbox.new_game()
	_room = await _change_room(HUB)
	_refresh()


## Moves the player to the room [param scene_key]: stash this room, change, restore, autosave.
func go_to(scene_key: String) -> void:
	_changing = true
	strongbox.world.stash_scene(_room)
	var entered: Node = await _change_room(scene_key)
	strongbox.world.restore_scene(entered)
	_changing = false
	_report(strongbox.save(strongbox.slots.next_autosave_id(), {"location": _room.name}), "Autosaved")


## Opens the chest in the Cellar.
func open_chest() -> void:
	_room.get_node("Chest").opened = true
	_refresh()


## Takes the Cellar coin for good: a tombstone keeps it gone in this and every later visit.
func take_coin() -> void:
	var coin: Node = _room.get_node_or_null("Coin")
	if coin == null:
		return
	coins += coin.value
	strongbox.world.registry.mark_gone(coin)
	coin.queue_free()
	_refresh()


## Flips the Cellar lever.
func pull_lever() -> void:
	var lever: Node = _room.get_node("Lever")
	lever.pulled = not lever.pulled
	_refresh()


## Drops a crate in the Hub. It is a spawned node, so the world store re-creates it.
func drop_crate() -> void:
	var crate: Node3D = CRATE.instantiate()
	var items: Node3D = _room.get_node("Items")
	items.add_child(crate)
	crate.position = Vector3(randf_range(-3, 3), 0.3, randf_range(0, 2))
	strongbox.world.register_spawned(crate, CRATE_PATH, _room)
	_refresh()


## Rests in the Hub bed, which saves to the quicksave slot.
func rest_in_bed() -> void:
	_report(strongbox.save(StrongboxSlots.QUICK_ID, {"location": "Hub bed"}), "Rested and saved")


## Saves to [param slot_id] (a new manual slot when empty).
func save_slot(slot_id: String = "") -> StrongboxResult:
	if slot_id == "":
		slot_id = "slot%d" % (strongbox.slots.list().size() + 1)
	var result: StrongboxResult = strongbox.save(slot_id, {"location": _room.name})
	_report(result, "Saved to %s" % slot_id)
	return result


## Loads [param slot_id].
func load_slot(slot_id: String) -> StrongboxResult:
	var result: StrongboxResult = await strongbox.load(slot_id)
	_report(result, "Loaded %s" % slot_id)
	return result


## Deletes [param slot_id].
func delete_slot(slot_id: String) -> void:
	_report(strongbox.slots.delete(slot_id), "Deleted %s" % slot_id)


## The current room.
func room() -> Node3D:
	return _room


func _change_room(scene_key: String) -> Node:
	if not ROOMS.has(scene_key):
		return null
	if _room != null:
		_room.free()
	_room = (ROOMS[scene_key] as PackedScene).instantiate()
	_holder.add_child(_room)
	await get_tree().process_frame
	_refresh()
	return _room


func _report(result: StrongboxResult, done: String) -> void:
	_status.text = done if result.ok else "%s (%s)" % [StrongboxService.message_for(result.code), result.code]
	_refresh()


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(420, 0)
	layer.add_child(panel)
	panel.add_child(_info)
	panel.add_child(_status)
	panel.add_child(_actions)
	_slot_list.custom_minimum_size = Vector2(420, 160)
	panel.add_child(_slot_list)
	var slot_buttons: HBoxContainer = HBoxContainer.new()
	panel.add_child(slot_buttons)
	_button(slot_buttons, "Save", func() -> void: save_slot(_selected()))
	_button(slot_buttons, "Load", _load_selected)
	_button(slot_buttons, "Delete", _delete_selected)


func _refresh() -> void:
	if _room == null or not is_inside_tree():
		return
	for child: Node in _actions.get_children():
		child.queue_free()
	if _room.name == "Hub":
		_button(_actions, "Go to Cellar", func() -> void: go_to(CELLAR))
		_button(_actions, "Rest in bed", rest_in_bed)
		_button(_actions, "Drop crate", drop_crate)
	else:
		_button(_actions, "Go to Hub", func() -> void: go_to(HUB))
		_button(_actions, "Open chest", open_chest)
		_button(_actions, "Take coin", take_coin)
		_button(_actions, "Pull lever", pull_lever)
	_slot_list.clear()
	for entry: Dictionary in strongbox.slots.list():
		_slot_list.add_item("%s  %s  %s" % [entry["slot_id"], entry["label"].get("location", ""), "(damaged)" if entry["damaged"] else ""])
		_slot_list.set_item_metadata(_slot_list.item_count - 1, entry["slot_id"])
	_info.text = "%s. Coins: %d" % [_room.name, coins]


func _load_selected() -> void:
	if _selected() != "":
		load_slot(_selected())


func _delete_selected() -> void:
	if _selected() != "":
		delete_slot(_selected())


func _selected() -> String:
	var picked: PackedInt32Array = _slot_list.get_selected_items()
	return "" if picked.is_empty() else str(_slot_list.get_item_metadata(picked[0]))


func _button(parent: Node, text: String, pressed: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(pressed)
	parent.add_child(button)
