# Strongbox

A generic save and load addon for Godot 4.

> **Status: early development (0.0.1).** There is no save logic yet. This repository currently holds the project skeleton, the test runner and CI. Do not use it in a game yet.

## Planned features

- A versioned save format with a safe serializer: no objects or code are ever created from a save file.
- Crash-safe writes, rolling backups and recovery from damaged files.
- Save slots with metadata, a quicksave slot and rotating autosaves.
- Opt-in persistence for nodes, including the state of scenes that are not currently loaded.
- Schema migrations, so older saves keep loading after a game changes.

## Requirements

Godot 4.7 or newer. GDScript only: no C# or native code.

## Development

The root `project.godot` is a small dev and test project for the addon. It enables the Strongbox and GUT plugins and is not part of a release. Its header is Godot's own, so opening the editor does not modify it.

The Godot and GUT versions are pinned in `tools/pins.env`. With that Godot version on `PATH` as `godot`, run the tests with:

```bash
tools/run_tests.sh
```

Contributor rules are in [`CLAUDE.md`](CLAUDE.md). How tasks are handed to an AI coding agent is in [`docs/HANDOFF.md`](docs/HANDOFF.md).

## License

MIT. See [`LICENSE`](LICENSE).
