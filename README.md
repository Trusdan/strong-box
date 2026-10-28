# Strongbox

A generic save and load addon for Godot 4. Versioned save files, save slots, crash-safe writes, and a world that remembers rooms the player has left.

> **Status: 0.1.0, the first release.** Everything works and is tested on Linux and Windows. The API may still change before 1.0, so every public class is marked `@experimental`. Changes are listed in [`CHANGELOG.md`](CHANGELOG.md).

## Features

- **Safe save files.** Versioned JSON with a checksum. Nothing in a save can create an object or run code.
- **Crash-safe writes.** Every save is written to a temporary file, checked, then swapped in, with rolling backups. A damaged save falls back to its backup.
- **Slots.** Named slots, a quicksave and a ring of autosaves, with metadata for a load menu and optional thumbnails.
- **Opt-in saved nodes.** Pick the nodes to save; every other node is ignored.
- **Rooms you have left.** Opened chests stay open, picked-up items stay gone, and dropped items come back, even after quitting and loading.
- **Global state** (a player profile, a quest system) through named providers.
- **Save guards** (for example "no saving during a cutscene").
- **Migrations**, so old saves keep loading after your game changes.

## Install

1. Copy `addons/strongbox/` into your project's `addons/` folder.
2. In **Project → Project Settings → Plugins**, enable **Strongbox**.
3. In **Project → Project Settings → Globals → Autoload**, add `res://addons/strongbox/service/service.gd` with the name **`Strongbox`**. The plugin doesn't add it for you, so your `project.godot` only changes when you choose.

## Quick start (5 minutes)

**1. Make a node savable.** Add it to the group `strongbox_persist` and give it two methods:

```gdscript
# chest.gd
extends Node3D

var opened: bool = false

func persist_capture() -> Dictionary:
	return {"opened": opened}

func persist_restore(data: Dictionary) -> void:
	opened = data.get("opened", false)
```

The node keeps the same id in every instance of the scene (its path, unless you set one), so its state comes back to the right node.

**2. Add a small autoload for your game's save code.** Create `game.gd` and add it in **Project → Project Settings → Globals → Autoload** with the name **`Game`**, below `Strongbox`:

```gdscript
# game.gd (autoload "Game")
extends Node

func _ready() -> void:
	# Tell Strongbox how your game changes scenes.
	Strongbox.scene_changer = func(scene_key: String) -> Node:
		get_tree().change_scene_to_file(scene_key)
		await get_tree().scene_changed
		return get_tree().current_scene

func save_game(slot_id: String) -> void:
	var saved: StrongboxResult = Strongbox.save(slot_id)
	if not saved.ok:
		print(StrongboxService.message_for(saved.code))

func load_game(slot_id: String) -> void:
	var loaded: StrongboxResult = await Strongbox.load(slot_id)
	if not loaded.ok:
		print(StrongboxService.message_for(loaded.code))
```

**Why an autoload:** loading replaces the current scene. A `scene_changer` set by a node in that scene (a main menu, a player) stops working as soon as the node is freed, and the load fails with `E_SCENE_CHANGE`. The same goes for code that awaits `load()`. An autoload lives through scene changes, so both keep running.

**3. Save and load** from anywhere, for example a menu button or a key press:

```gdscript
Game.save_game("slot1")
Game.load_game("slot1")
```

`save()` returns at once. `load()` waits for your `scene_changer`, which is why `load_game` awaits it. Code in the old scene doesn't need to wait: `Game` finishes the load. To react when it's done, connect to `Strongbox.load_finished` or `Strongbox.load_failed` from an autoload or from the new scene. Every call returns a `StrongboxResult`: `ok`, `value`, a `code` such as `E_NO_SLOT`, and a `message`.

That's it. The chest is open again after loading. To keep rooms the player has left, read on.

## The example project

`example/` is a small playable demo built from plain shapes. It has:

- a **Hub** with a bed that saves and a button that drops crates;
- a **Cellar** with a chest, a coin and a lever;
- an autosave on every room change;
- a slot list with Save, Load and Delete.

Open this repository in Godot 4.7 and press **F5**. `example/main.gd` is the game code, commented as you would write it. [`docs/tutorial.md`](docs/tutorial.md) walks through it.

## Concepts

### Saved nodes

A node is saved when it's in the group `strongbox_persist`, or when it has a `StrongboxPersistComponent` child. Every other node is ignored.

- **What is saved:** either the node implements `persist_capture()` and `persist_restore(data)`, or its component lists the property names to save (for example `["pulled"]`). Saved values must be plain data: numbers, strings, vectors, colors, arrays, dictionaries and the like. Objects, Callables and Resources are refused.
- **Its id**, in order: the component's `persist_id`, the node's `strongbox_id` metadata, or its node path in the scene (`Props/Chest01`).
- **Its scene key:** the scene root's `strongbox_scene_key` metadata, or its scene file path.

### Rooms you have left

`Strongbox.world` (a `StrongboxWorldStore`) keeps each room's state while the room is unloaded.

- **The game's own scene changes** (not loads): call `Strongbox.world.stash_scene(room)` right before you unload a room, and `Strongbox.world.restore_scene(room)` once the new instance is ready. `Strongbox.load()` restores the loaded room itself.
- **Picked-up items:** call `Strongbox.world.registry.mark_gone(node)` before freeing the node. That room's later saves list the id as gone, and the node is freed again whenever the room is restored. Saving never frees anything; restoring does.
- **Items dropped at runtime:** add the node to the room, then call `Strongbox.world.register_spawned(node, "res://items/crate.tscn", room)`. On restore it is instanced again under the same parent, with the same transform and data.
  - Scenes load only from folders you allow: `Strongbox.world.spawn_allow_prefixes = PackedStringArray(["res://items/"])`. Any other path in a save is refused.
  - An allowed scene that no longer exists (removed in a later version) is skipped and listed in the restore result's `missing`; the rest of the room still loads.
- **`StrongboxSceneWatcher`** is a helper node that stashes its parent room on exit and restores it when ready. **Don't use its `restore_on_ready` together with `Strongbox.load()`.** When the loaded save's room is the room you are already in, the old instance's stash would overwrite the loaded state before the new instance restores, bringing back stale picked-up items and dropped crates that the load can't undo.

### Global state

Save state that doesn't live in a room (a player profile, a quest log) with a provider:

```gdscript
Strongbox.register_provider(&"player",
	func() -> Dictionary: return {"coins": coins},
	func(data: Dictionary) -> void: coins = data.get("coins", 0))
```

- Providers restore in ascending `priority` (the fourth argument, default 0).
- A provider with nothing in the save gets `{}`.
- Data for a provider that isn't registered is kept and written back on the next save.
- An optional fifth argument, `validate(data) -> String`, can refuse bad data before the load changes anything.
- A restore may return a `StrongboxResult`. If it fails, the load stops and fails with that provider's error, and later providers aren't called. Providers restore **after the scene change has begun**, so this failure leaves the game part-loaded: treat it like any late `load_failed` (see "Good to know"). What successful restores return is in `result.value["providers"]`.

### Save guards

```gdscript
Strongbox.add_save_guard(&"cutscene", func() -> String:
	return "a cutscene is playing" if in_cutscene else "")
```

While any guard returns a reason, `save()` is refused with `E_REFUSED` and the reasons, and nothing is written.

### Slots

Saves live under `user://saves/<slot_id>/` (`Strongbox.slots.store.root` changes the folder):

- `save.json`, with backups `.bak1` and `.bak2`;
- `meta.json`, for the load menu;
- an optional `thumb.png`.

Slot ids are 1 to 32 characters of `a-z`, `0-9`, `_` and `-`.

- **`quick`** is the quicksave. **`auto_0`, `auto_1` and `auto_2`** are the autosave ring; `Strongbox.slots.next_autosave_id()` picks the next one.
- **`Strongbox.slots.list()`** gives every slot's metadata, newest first, for a load menu. A slot that can't be read is listed as `damaged`, not hidden. **`latest()`** is the newest slot, for a "Continue" button. **`delete(slot_id)`** removes a slot.
- **`write_thumbnail(slot_id, image)`** and **`read_thumbnail(slot_id)`** store an optional screenshot.

### Migrations

When your save data changes shape, bump `Strongbox.migrations.current_version` and register one step per version:

```gdscript
Strongbox.migrations.current_version = 2
Strongbox.migrations.register(1, func(body: Dictionary) -> Dictionary:
	var player: Dictionary = body["world"]["globals"].get("player", {})
	if player.has("gold"):
		player["coins"] = player["gold"]   # version 1 called it "gold"
		player.erase("gold")
	return body)
```

`load()` runs the steps in order before anything changes, and refuses a save from a newer version (`E_SCHEMA_TOO_NEW`). A step that hits a script error fails the load (`E_MIGRATION_FAILED`) instead of silently emptying the save. Steps must be **synchronous**: no `await`. `Strongbox.migrations.validate_chain()` checks that no step is missing.

While a step runs, **any** error logged by Godot counts as that step failing, including an error another thread happens to log at the same moment. Such a load fails with `E_MIGRATION_FAILED` and the other thread's message, but nothing is changed and loading again works. Run loads while your own worker threads are quiet. This trade-off is deliberate: a broken step must never silently empty a save.

### Signals

- Saving: `save_started(slot_id)`, then `save_finished(slot_id, result)`.
- Loading: `load_started(slot_id)`, then either `load_finished(slot_id, result)` or `load_failed(slot_id, code, message)`.

A call that is refused at once (busy, or a guard says no) emits nothing.

## Error codes

Every code has a short message: `StrongboxService.message_for(code)`.

| Code | Message |
| --- | --- |
| `E_BUSY` | A save or load is already running. |
| `E_REFUSED` | Saving is not allowed right now. (The guards' reasons follow.) |
| `E_NO_SCENE` | There is no current scene to save. |
| `E_BAD_BODY` | The save is missing data it needs. |
| `E_INVALID_GLOBALS` | Part of the save was refused by the game. |
| `E_SCENE_CHANGE` | The game could not change to the saved scene. |
| `E_BAD_SLOT` / `E_NO_SLOT` | That is not a valid slot name. / There is no save in that slot. |
| `E_NO_VALID_SAVE` | The save and all its backups are damaged. |
| `E_WRITE`, `E_VERIFY`, `E_RENAME`, `E_DISK`, `E_BAD_PATH` | The save could not be written (see the message for which step). |
| `E_SCHEMA_TOO_NEW` / `E_SCHEMA_TOO_OLD` | This save is from a newer version of the game. / This save is too old for this version of the game. |
| `E_SCHEMA_GAP` / `E_MIGRATION_FAILED` | This save cannot be upgraded. |
| `E_FORMAT_TOO_NEW` | This save is from a newer version of Strongbox. |
| `E_SPAWN_PATH` | The save names a scene the game does not allow. |
| `E_PROVIDER`, `E_BAD_DATA`, `E_DUPLICATE_ID`, `E_CAPTURE`, `E_SCENE_KEY`, `E_UNSUPPORTED_TYPE` | Part of the game state could not be saved or read. |

## Good to know

- **A load can fail after it has started changing the game.** Everything that can be checked is checked first: the file, the backups, migrations, the body, spawn paths and validators. A failure there leaves the running game untouched.

  A failure after the scene change has begun leaves the game part-loaded. That includes `scene_changer` returning nothing, a provider's restore failing, or a room's restore failing. Treat a `load_failed` at that point as a failed load, for example by going back to the main menu. Loading again starts cleanly.
- **Call `load()` from a node that survives the scene change**, such as an autoload, and set `scene_changer` there too. Code in the old scene stops when that scene is freed, including anything after an `await Strongbox.load(...)` there.
- **`new_game()`** clears every room, dropped item, picked-up item, global and the playtime. Providers, guards and the spawn allow-list stay.
- **Playtime:** `Strongbox.playtime_s` counts while the tree is not paused, and it is saved and restored.
- **Load menu order:** the newest save first, by the time it was saved and then by write order. If the computer's clock is set back, only the order changes; no save is lost.
- **Failed writes:** if the final step of a save fails, the previous save is put back. The oldest backup is lost in that case.
- **Windows:** keep at least one backup (the default is two). With no backups, replacing a save isn't atomic on Windows.
- **Limits:** dictionaries and arrays nest at most 64 deep, and all strings together hold at most 32 MB per save.
- **Negative zero in GDScript:** a literal `-0.0` in the same function as a literal `0.0` is silently turned into `0.0` by the compiler. Strongbox saves `-0.0` exactly, but if your code depends on it, build it at run time from its bits (as `tests/fixtures/golden/golden_dataset.gd` does).

The full file format is in [`docs/format.md`](docs/format.md).

## More documentation

- [`docs/tutorial.md`](docs/tutorial.md) walks through the example: rooms you have left, picked-up items, dropped items, a save guard and a migration.
- [`docs/api/`](docs/api/index.md) has a page for every class, generated from the code's doc comments.
- [`docs/format.md`](docs/format.md) describes the save file format and crash safety.
- [`docs/RELEASE.md`](docs/RELEASE.md) is the maintainer's release checklist.

## Optional: the Wyrd bridge

`addons/strongbox_wyrd/` saves the state of the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine through Strongbox. It is a separate, optional folder; see [`docs/wyrd-bridge.md`](docs/wyrd-bridge.md).

## Requirements

Godot 4.7 or newer. GDScript only: no C# or native code.

## Development

The root `project.godot` is a dev and test project. It enables the Strongbox and GUT plugins, runs the example as its main scene, and isn't part of a release. Its header is Godot's own, so opening the editor doesn't modify it.

The Godot and GUT versions are pinned in `tools/pins.env`. With that Godot version on `PATH` as `godot`, run the tests with:

```bash
tools/run_tests.sh
```

CI runs the full GUT suite on every pull request and every push to `main`:

- **`test` (Ubuntu)** also runs the API-docs, editor-load, content-hygiene and Wyrd pin checks;
- **`test-windows`** runs the suite on Windows;
- **`test-core-only`** runs the suite with the Wyrd bridge and the vendored Wyrd removed.

After changing a `##` doc comment in `addons/strongbox/`, run `tools/gen_api_docs.sh` and commit `docs/api/`. CI fails if `docs/api/` is out of date (`tools/gen_api_docs.sh --check`).

Contributor rules are in [`CLAUDE.md`](CLAUDE.md). How tasks are handed to an AI coding agent is in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## License

MIT. See [`LICENSE`](LICENSE).
