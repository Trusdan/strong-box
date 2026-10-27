# CLAUDE.md

Rules for AI coding agents (and humans) working in this repository. Read this before every task.
If a task description and this file disagree, follow this file and say so in the pull request.

## What this project is

Strongbox is a **generic save and load addon for Godot 4** (4.7 or newer). Any Godot game should be able to use it: versioned save files, save slots, crash-safe writes and the state of scenes that are not loaded. It is MIT licensed.

## Generic only (no host-game terms)

- Never put a host game's names, places, characters, lore or story in code, comments, tests, docs, commit messages, branch names or pull request text.
- Examples and test fixtures use only the neutral demo: a **"Hub"** room and a **"Cellar"** room with a chest, a lever and a coin pickup.
- CI checks every change against a private deny-list (the `STRONGBOX_HYGIENE_TERMS` secret). The log never shows the term. If the check fails, find and remove the game-specific wording.

## Code style

- GDScript only. **No C#, no .NET, no GDExtension or other native code**, and no third-party addons except the vendored GUT.
- **Static typing everywhere**: variables, parameters and return types.
- Public classes use the **`Strongbox` prefix** (`class_name StrongboxCodec`). File names are **`snake_case`** (`codec.gd`).
- Indent with **tabs**.
- Every public class and method gets a **`##` doc comment**. API before 1.0 is marked **`@experimental`** in its doc comment.
- Put logic in plain **`RefCounted`** classes so GUT can test it headless. **`plugin.gd` stays thin**: no save logic in the editor plugin.
- Save files come from players' disks, so treat them as **untrusted input**: never create objects or run code from save data.

## Workflow

- **One pull request per Jira task.** Branch from the latest `main` as **`claude/<KEY>-<short-slug>`** (for example `claude/PROJ-123-codec`).
- **Never push to `main`, never merge, never force-push**, and never change repository settings, secrets or branch protection. The maintainer reviews and merges.
- Change only the files in the task's **"May touch"** list. If another file needs a change, stop and describe it in the pull request.
- **Do not edit `addons/gut/`.** It is vendored GUT. Upgrading it is its own task, together with `tools/pins.env`.
- Commit messages use **[Conventional Commits](https://www.conventionalcommits.org/)** (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`).
- Aim for about **300 to 600 changed lines per pull request**, tests included. If a task clearly needs more, stop at a clean point and propose a split in the pull request.
- **Never commit secrets, tokens, credentials or `user://` files** (save files, logs, screenshots from a run).

## Before opening a pull request

1. Run **`tools/run_tests.sh`**. It needs `godot` (the version in `tools/pins.env`) on `PATH`. All GUT tests must pass, with no new warnings or script errors.
2. Fill in every section of the pull request template: Jira key, Summary, Files touched, How to test, Acceptance criteria, Deviations, Open questions.
3. Check that CI is green.

## When unsure

Take the smallest reasonable choice, keep going, and list the question under **Open questions** in the pull request description. Do not widen the scope of a task.
