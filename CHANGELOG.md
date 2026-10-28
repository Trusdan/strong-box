# Changelog

All notable changes to Strongbox. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Before 1.0, any minor version may change the API. Every public class is marked `@experimental` until then.

## [0.1.0] - unreleased

The first release.

### Added

- **Safe save format** (`StrongboxCodec`, `StrongboxEnvelope`):
  - versioned JSON with a header and a checksum;
  - every plain Godot type round-trips exactly, including reals bit for bit (`-0.0`, NaN, `INF`);
  - nothing in a save can create an object or run code.
- **Crash-safe files** (`StrongboxFileStore`): write to a temporary file, verify it, rotate the backups, then rename it into place. A damaged save falls back to its backups.
- **Slots** (`StrongboxSlots`): named slots, a quicksave, an autosave ring, `meta.json` for fast load menus, and optional thumbnails.
- **Saved nodes** (`StrongboxPersist`, `StrongboxPersistComponent`, `StrongboxRegistry`): opt-in by group or component, stable ids, and tombstones for nodes removed for good.
- **Off-scene world state** (`StrongboxWorldStore`, `StrongboxSceneWatcher`):
  - rooms remember their state while unloaded;
  - runtime-spawned nodes are re-created, from allow-listed `res://` folders only;
  - global providers are restored by priority.
- **Migrations** (`StrongboxMigrations`): ordered upgrade steps, gap checks, and script errors in a step caught instead of emptying a save.
- **The service** (`StrongboxService`): `save()` and `load()` with save guards, busy protection, signals, playtime, and a short message for every error code. A load checks everything before it changes the running game.
- **A failed global provider restore fails `load()`.** What successful providers return reaches the load result as `providers`.
- **The optional Wyrd bridge** (`addons/strongbox_wyrd/`, `StrongboxWyrdBridge`): saves the Wyrd narrative engine's state through its stable API.
- **The example project** (`example/`), the tutorial, generated API docs (`docs/api/`, `tools/gen_api_docs.sh`) and this release checklist.
- **Tests and CI:** CI runs the GUT suite on Linux and Windows, plus a core-only job without the bridge. Golden save fixtures prove that Linux and Windows write byte-identical saves.

### Before 1.0

Known items to settle before the API is frozen:

- `StrongboxService` calls the world store's private `_check_spawn_path()` to check spawn paths before a load changes anything. That check should become a public `StrongboxWorldStore` method.
- `StrongboxSceneWatcher.restore_on_ready` should not be combined with `StrongboxService.load()` (see the README). The watcher could instead pause while a load runs.
- Loads are not all-or-nothing once the scene change has begun (see the README's "Good to know").
