# Strongbox

A generic save and load addon for Godot 4.

> **Status: early development (0.0.1).** There is no save logic yet. This repository currently holds the project skeleton, the test runner and CI. Do not use it in a game yet.

## Planned features

- A versioned save format with a safe serializer: no objects or code are ever created from a save file.
- Crash-safe writes, rolling backups and recovery from damaged files.
- Save slots with metadata, a quicksave slot and rotating autosaves.
- Opt-in persistence for nodes, including the state of scenes that are not currently loaded.
- Schema migrations, so older saves keep loading after a game changes.

## Slots

`StrongboxSlots` gives a game named save slots, a quicksave and a ring of autosaves. Each slot is a folder under the save root (default `user://saves`):

```
user://saves/<slot_id>/save.json        the save, written crash-safely with backups (.bak1, .bak2)
user://saves/<slot_id>/meta.json        small metadata for a load menu
user://saves/<slot_id>/thumb.png        optional thumbnail
```

- **Slot ids** are 1 to 32 characters of `a-z`, `0-9`, `_` and `-`. Anything else is refused with `E_BAD_SLOT`.
- **`quick`** is the quicksave. **`auto_0` … `auto_<n-1>`** are the autosave ring (`autosave_count`, default 3). `next_autosave_id()` returns the first empty one, otherwise the one written longest ago. The game decides *when* to autosave.
- **`write(slot_id, text, label = {})`** saves text from `StrongboxEnvelope.pack`, then writes `meta.json`. `label` holds load-menu labels such as `{"location": "Cellar"}`; when it is empty, the save header's `meta` is used.
- **`list()`** returns every slot's metadata, newest first: `slot_id`, `kind` (`manual`, `quick` or `auto`), `saved_unix`, `playtime_s`, `schema_version`, `game_version`, `label`, `seq` and `damaged`.
  - It reads only the `meta.json` files, so a load menu stays fast with many slots.
  - A missing or damaged `meta.json` is rebuilt from the save's header.
  - A slot whose save cannot be read at all is listed with `damaged: true`, not hidden.
- **`latest()`** returns the newest slot of any kind (for a "Continue" button), or `{}` when there are none.
- **`read(slot_id)`** returns the save, falling back to a backup if needed.
- **`delete(slot_id)`** removes only that slot's folder.
- **`exists(slot_id)`** tells whether a slot has a save.
- **`write_thumbnail(slot_id, image)`** stores a PNG scaled down to fit 320×180. **`read_thumbnail(slot_id)`** returns it as an `Image`, or `null`. Thumbnails are optional and never affect the save.

```gdscript
var slots := StrongboxSlots.new()
var text: String = StrongboxEnvelope.pack({"room": "Cellar"}, {"location": "Cellar"}).value
slots.write("slot1", text)
slots.write(slots.next_autosave_id(), text)
for entry in slots.list():
	print(entry["slot_id"], " ", entry["label"].get("location", ""), " ", entry["saved_unix"])
```

## Migrations

Games change their save data over time. `StrongboxMigrations` lets old saves keep loading by upgrading them through small, ordered steps.

- **`current_version`** is the save `schema_version` your game writes now. Bump it whenever the save body changes shape.
- **`register(from_version, step)`** adds one step. `step` takes the body as a Dictionary and returns the upgraded Dictionary, from `from_version` to `from_version + 1`. Each version can have only one step.
- **`run(body, from_version)`** applies every step from the save's version up to `current_version`, in order. It works on a deep copy, so `body` is never changed. On success, `result.value` holds:
  - `body`: the upgraded body;
  - `version`: the version it's now at;
  - `report`: one `{"from", "to"}` entry per step applied.

  Running it on a body that is already at `current_version` changes nothing.
- **`min_supported_version`** is the oldest schema your game still loads. **`validate_chain()`** checks that no step is missing between it and `current_version`. Call it once at start-up, or in a test.

`run` refuses, without changing anything:

| Code | When |
| --- | --- |
| `E_SCHEMA_TOO_NEW` | The save is from a newer game version. |
| `E_SCHEMA_TOO_OLD` | The save is older than `min_supported_version`. |
| `E_SCHEMA_GAP` | A step between the save's version and `current_version` is not registered. |
| `E_MIGRATION_FAILED` | A step returned something other than a Dictionary, or hit a script error. The message names the step, for example "schema 2 to 3". |

A script error inside a step is caught, not ignored. In GDScript, a function declared `-> Dictionary` that fails returns an empty Dictionary, and a save body must never be silently emptied that way.

### Worked example

Version 1 stored the player's health as `hp`. Version 2 renamed it to `health`. Version 3 added `stamina`, with a default of 50.

```gdscript
var migrations := StrongboxMigrations.new()
migrations.current_version = 3

migrations.register(1, func(body: Dictionary) -> Dictionary:
	body["health"] = body.get("hp", 100)
	body.erase("hp")
	return body)

migrations.register(2, func(body: Dictionary) -> Dictionary:
	body["stamina"] = body.get("stamina", 50)
	return body)

assert(migrations.validate_chain().ok)

var result := migrations.run({"hp": 80, "room": "Cellar"}, 1)
# result.value["body"]   == {"health": 80, "room": "Cellar", "stamina": 50}
# result.value["report"] == [{"from": 1, "to": 2}, {"from": 2, "to": 3}]
```

Strongbox's own file `format_version` is separate from your `schema_version`. It has its own internal step table, which is empty while the format is at version 1.

## Saving and loading

`StrongboxService` is a Node that ties the pieces together. Add it as an autoload (for example named `Strongbox`) and give it two functions from your game:

- **`scene_changer`** `(scene_key: String) -> Node` changes to a scene in your own way (fades, loading screen) and returns the new scene root once it is ready. It may be a coroutine.
- **`current_scene_provider`** `() -> Node` returns the current scene root. It defaults to the tree's `current_scene`.

```gdscript
Strongbox.scene_changer = func(scene_key: String) -> Node:
	get_tree().change_scene_to_file(scene_key)
	await get_tree().scene_changed
	return get_tree().current_scene
Strongbox.world.spawn_allow_prefixes = PackedStringArray(["res://items/"])
Strongbox.add_save_guard(&"cutscene", func() -> String:
	return "a cutscene is playing" if in_cutscene else "")

var saved: StrongboxResult = await Strongbox.save("slot1", {"location": "Cellar"})
var loaded: StrongboxResult = await Strongbox.load("slot1")
if not loaded.ok:
	print(StrongboxService.message_for(loaded.code))
```

- **`save(slot_id, label = {})`** checks the guards, stashes the current scene, captures globals, and writes the slot. If it fails, the world store is left as it was.
- **`load(slot_id)`** does its checks first, before anything in the running game changes:
  - reads the slot, falling back to a backup;
  - upgrades the body with `migrations`;
  - checks the whole body, including spawn paths and each provider's optional `validate` (passed to `Strongbox.register_provider`).

  Only after that does it replace the world store, call `scene_changer`, restore globals in priority order, and restore the scene. `result.value["source"]` says whether a backup was used.
- **`new_game()`** clears the world store and playtime.
- **`playtime_s`** counts while the tree is not paused. It is saved in the header and restored on load.
- **Signals:** `save_started` → `save_finished(slot_id, result)`, and `load_started` → `load_finished(slot_id, result)` or `load_failed(slot_id, code, message)`. A call that is refused at once (busy, or a guard says no) emits nothing.

Every code has a short message in `StrongboxService.MESSAGES`:

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

## Requirements

Godot 4.7 or newer. GDScript only: no C# or native code.

## Development

The root `project.godot` is a small dev and test project for the addon. It enables the Strongbox and GUT plugins and is not part of a release. Its header is Godot's own, so opening the editor does not modify it.

The Godot and GUT versions are pinned in `tools/pins.env`. With that Godot version on `PATH` as `godot`, run the tests with:

```bash
tools/run_tests.sh
```

CI runs the full GUT suite on every pull request and every push to `main`, on both Ubuntu (job `test`) and Windows (job `test-windows`). The content-hygiene check and the editor-load check run on Ubuntu only.

Contributor rules are in [`CLAUDE.md`](CLAUDE.md). How tasks are handed to an AI coding agent is in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## License

MIT. See [`LICENSE`](LICENSE).
