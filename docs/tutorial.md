# Tutorial: walk through the example

This walk-through uses the example project in `example/`. Open this repository in Godot 4.7 and press **F5**. You start in the **Hub**: a floor, a bed and a few buttons. The **Cellar** next door has a chest, a coin and a lever.

The game code is one script, `example/main.gd`. Each section below plays one part of the example, then shows the lines that make it work. For the basics (installing, making one node savable), read the README's quick start first.

## 1. Setting up the service

A game would usually add `StrongboxService` as an autoload named `Strongbox`. The example creates its own instance instead, so the dev project needs no autoload. Everything else is what a game would do once at start-up:

```gdscript
strongbox.slots.store.root = save_root            # "user://strongbox_example"
strongbox.game_version = "0.1.0"
strongbox.world.spawn_allow_prefixes = PackedStringArray(["res://example/items/"])
strongbox.scene_changer = _change_room
strongbox.current_scene_provider = func() -> Node: return _room
```

The example changes rooms itself, by freeing one room scene and adding the other under a holder node. `main.gd` sits above the rooms and is never replaced, so it can set `scene_changer` and await `load()` safely. In a game that replaces the whole scene, put this code in an autoload, as the README's quick start does. So it tells Strongbox both how to change scenes (`_change_room`) and which node is the current room. `_change_room(scene_key)` instances the room for that key (its scene file path), waits a frame, and returns the new room.

## 2. Rooms you have left

**Try it:** go to the Cellar, press **Open chest** and **Pull lever**, go back to the Hub, then return. The chest is still open and the lever still pulled, although the Cellar scene was freed and loaded again.

Two things make that work.

**The saved nodes.** In `rooms/cellar.tscn`, the chest (`props/chest.gd`) is in the `strongbox_persist` group and implements the two methods:

```gdscript
func persist_capture() -> Dictionary:
	return {"opened": opened}

func persist_restore(data: Dictionary) -> void:
	opened = data.get("opened", false)
```

The lever has no save code at all. It has a `StrongboxPersistComponent` child whose `properties` list is `["pulled"]`, and that property is saved and restored for it.

**Stash and restore on every room change.** `go_to()` is the example's door:

```gdscript
func go_to(scene_key: String) -> void:
	_changing = true
	strongbox.world.stash_scene(_room)               # remember the room we are leaving
	var entered: Node = await _change_room(scene_key)
	strongbox.world.restore_scene(entered)           # bring back what we left here before
	_changing = false
	_report(strongbox.save(strongbox.slots.next_autosave_id(), {"location": _room.name}), "Autosaved")
```

`stash_scene` keeps the room's state in `strongbox.world` while the room is unloaded. `restore_scene` puts it back into the fresh instance. Both use the nodes' stable ids (here, their paths in the room), so the state lands on the right node.

The last line **autosaves on every room change**. `next_autosave_id()` cycles through `auto_0`, `auto_1` and `auto_2`, reusing the oldest. The slot list shows them.

## 3. Picked-up items: tombstones

**Try it:** in the Cellar, press **Take coin**. Leave and come back: the coin is gone for good, and the coin count stays at 1.

```gdscript
func take_coin() -> void:
	var coin: Node = _room.get_node_or_null("Coin")
	if coin == null:
		return
	coins += coin.value
	strongbox.world.registry.mark_gone(coin)   # a tombstone: this coin is gone for good
	coin.queue_free()
	_refresh()
```

The Cellar scene file still contains the coin, so every fresh instance of the room has one. `mark_gone` records a **tombstone** for the coin's id. Saving lists the id as gone and never frees anything; restoring frees that node from each new instance. Call `mark_gone` before freeing the node.

## 4. Dropped items: spawned nodes

**Try it:** in the Hub, press **Drop crate** a few times. Visit the Cellar and come back: the crates are where you left them.

The crates aren't in the Hub scene file; the game creates them at run time. Strongbox needs to know the scene to re-create them from:

```gdscript
func drop_crate() -> void:
	var crate: Node3D = CRATE.instantiate()
	var items: Node3D = _room.get_node("Items")
	items.add_child(crate)
	crate.position = Vector3(randf_range(-3, 3), 0.3, randf_range(0, 2))
	strongbox.world.register_spawned(crate, CRATE_PATH, _room)
	_refresh()
```

`register_spawned` gives the crate an id (`spawn_1`, `spawn_2` and so on). When the room is stashed, the store records the crate's scene path, its parent (`Items`), its transform and its `persist_capture()` data. On restore it instances `items/crate.tscn` again under `Items`.

For safety, Strongbox only loads spawned scenes from folders the game allows. A save is a file on the player's disk, and it must not be able to make the game load any scene it likes. That's why the setup lists `res://example/items/` in `spawn_allow_prefixes`.

If an allowed scene no longer exists (because a later version of the game removed it), that one item is skipped and listed in `missing`, and the rest of the room still loads.

## 5. Global state: providers

The coin count isn't in any room; it belongs to the player. The example saves it with a provider:

```gdscript
strongbox.register_provider(&"player", func() -> Dictionary: return {"coins": coins},
	func(data: Dictionary) -> void: coins = data.get("coins", 0))
```

Every save captures it. Every load restores it, in priority order, after the scene change has begun.

## 6. Saving, the bed and the slot list

**Try it:** in the Hub, press **Rest in bed**. That saves to the quicksave slot, `quick`:

```gdscript
func rest_in_bed() -> void:
	_report(strongbox.save(StrongboxSlots.QUICK_ID, {"location": "Hub bed"}), "Rested and saved")
```

The slot list under the buttons is `strongbox.slots.list()`: every slot, newest first, with the `location` label each save was given.
- **Save** writes a new manual slot, or overwrites the selected one.
- **Load** calls `await strongbox.load(slot_id)`.
- **Delete** calls `strongbox.slots.delete(slot_id)`.

`save()` returns its result at once. `load()` must be awaited, because it waits for `_change_room`.

**Try it:** rest in bed, then change things: take the coin, drop more crates, pull the lever back. Select `quick` and press **Load**. You are back in the Hub at the moment you rested, and every room is as it was then.

## 7. A save guard

**Try it:** this one is quick to miss. While the example walks between rooms, saving is refused.

```gdscript
strongbox.add_save_guard(&"travelling", func() -> String:
	return "travelling between rooms" if _changing else "")
```

`go_to()` sets `_changing` for the length of the room change. A save in that window would capture a half-changed world, so the guard refuses it. The result is `E_REFUSED` with the reason, and nothing is written. Guards are the place for rules like "not during a cutscene" or "not in combat".

## 8. A migration

Suppose version 1 of this game called the player's coins `gold`, and version 2 renamed them `coins`. Saves made with version 1 still exist on players' disks. The example handles them with one migration step:

```gdscript
strongbox.migrations.current_version = 2
strongbox.migrations.register(1, func(body: Dictionary) -> Dictionary:
	var player: Dictionary = body["world"]["globals"].get("player", {})
	if player.has("gold"):
		player["coins"] = player["gold"]
		player.erase("gold")
	return body)
```

Every save records the `schema_version` it was written with (here, 2). Loading a version-1 save runs this step first, before anything in the game changes, so the `player` provider only ever sees `coins`. `tests/example/test_example_roundtrip.gd` loads a real version-1 save this way.

Keep steps small and synchronous: no `await`. Each step upgrades one version.

## 9. When something goes wrong

Every call returns a `StrongboxResult`. The example's `_report()` shows the short message for a failed one:

```gdscript
StrongboxService.message_for(result.code)   # for example "There is no save in that slot."
```

A damaged save falls back to its backup by itself (`result.value["source"]` says which file was used). A save from a newer game version is refused before anything changes.

The README's "Good to know" section lists the cases to plan for, including a load that fails after the scene change has begun.

## Where next

- **The README** covers every concept briefly, along with the error codes.
- **[`docs/api/`](api/index.md)** has the full API of every class.
- **[`docs/format.md`](format.md)** describes the save file format and crash safety.
- **[`docs/wyrd-bridge.md`](wyrd-bridge.md)** covers saving Wyrd's narrative state.
