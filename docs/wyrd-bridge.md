# Strongbox Wyrd bridge

`addons/strongbox_wyrd/` is an optional add-on. It saves and restores the state of the [Wyrd](https://github.com/Trusdan/wyrd) narrative engine (dialogue, quests, facts) through a `StrongboxService`. The core Strongbox addon does not need it, and the bridge does not need Wyrd to compile.

## Install

Copy `addons/strongbox_wyrd/` next to `addons/strongbox/`. You don't need to enable its editor plugin, because the bridge is installed from game code. Do it once, after both autoloads exist:

```gdscript
var installed: StrongboxResult = StrongboxWyrdBridge.install(Strongbox, Wyrd)
if not installed.ok:
	push_error(installed.message)
```

`install(service, wyrd, priority = 100)` refuses with `E_NOT_WYRD` if the node has no `can_save()`, `save_state()` or `load_state()`. On success, `installed.value` is the bridge. It adds two things to the service, both named `wyrd`:

- **a save guard**, which refuses with "A dialogue scene is open" while Wyrd's `can_save()` is false;
- **a global provider**, with a validator.

## Priority

Global providers restore in ascending priority. The default of **100** restores Wyrd after a game's own providers, which usually sit at 0. So when Wyrd loads its state, the game's world (for example the inventory or the player profile) is already back. Pass a lower number to restore Wyrd earlier.

## What is saved

Whatever Wyrd's stable `save_state()` returns: its facts, quests, roles, deeds and the rest of its play state. Strongbox stores that Dictionary as the `wyrd` entry of the save's globals and doesn't look inside it. Wyrd checks it on load and reports what it changed.

If a save has no `wyrd` entry (for example, one made before the bridge was installed), the bridge skips the restore and leaves Wyrd's current state as it is. Resetting the story is the game's call, not the bridge's.

## What is refused, and why

| Case | Result | Why |
| --- | --- | --- |
| Saving while a dialogue scene is open | `E_REFUSED` with "A dialogue scene is open" | Wyrd can't save mid-scene: `save_state()` returns `{}` and refuses. |
| Wyrd returns no data when captured | The save fails with `E_PROVIDER` | Storing an empty Wyrd state would wipe the story on the next load. |
| The saved `wyrd` entry is not a Dictionary | The load fails with `E_INVALID_GLOBALS` before anything changes | It can't be Wyrd data. Deeper checks are Wyrd's. |
| Wyrd's `load_state()` reports an error | `Strongbox.load()` fails with `E_PROVIDER`, a message naming Wyrd's error codes, and the codes in `result.value["codes"]`. The bridge logs the error once. | Wyrd refused or partly refused the data. |
| A save with no `wyrd` entry (made before the bridge was installed) | Skipped: Wyrd is left as it is | There is nothing to restore. |

Wyrd's warnings (for example ids it kept but doesn't declare) don't fail a restore. They reach the load result as `result.value["providers"]["wyrd"]["warnings"]`. The bridge also keeps them in `bridge.last_result`, and the full report in `bridge.last_report`.

## How a provider failure affects `load()`

This applies to every global provider, not only Wyrd.

- **A restore may return a `StrongboxResult`.** A failed one stops the restore:
  - later providers are not called;
  - `Strongbox.load()` returns that failure, with the provider's own code and value and the message `Provider "<name>": <message>`;
  - `load_failed` is emitted.

  Strongbox doesn't log it again, so the provider logs its own error (the bridge does, once).
- **What successful restores return is passed through** in `result.value["providers"]`, keyed by provider name. A restore that returns nothing has no entry, so existing providers are unaffected.
- **This happens after the scene change has begun**, so the game is part-way through the load. Treat a failed load at this point like any other failed load, for example by returning to the main menu. Loading the save again, or another save, starts cleanly.

## Stable API only

The bridge calls only members that Wyrd 1.x lists as stable in its `docs/stability.md`:

- `can_save`, `save_state` and `load_state` on the facade;
- `ok`, `error_count`, `diagnostics` and `rows` on the load report.

It calls them by name, so it compiles without Wyrd. A test fails if the bridge source mentions `WyrdSave` or calls anything else.

## Tests

`tests/wyrd/test_bridge_fake.gd` uses a fake facade. `tests/wyrd/test_bridge_real.gd` uses the Wyrd release vendored under `addons/wyrd/` (pinned in `tools/wyrd-pin.env`, checked by `tools/check_wyrd_pin.sh`) and the neutral pack in `tests/wyrd_fixtures/`. CI also runs the core tests in a job with the bridge, the vendored Wyrd and their tests deleted.
