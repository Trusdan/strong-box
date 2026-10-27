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
