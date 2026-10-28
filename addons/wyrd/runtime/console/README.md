# console

`WyrdConsole` is the playtest command layer. `wyrd console <pack>` is the prompt. Tests call `exec` on a bound runtime. There is no facade member and no editor panel.

A release export must set `exclude_filter` to `addons/wyrd/runtime/console/*` (`WyrdConsole.RELEASE_EXCLUDE`). This repository's Linux preset does that. The runtime and the facade do not reference the script, so the exclude removes it from the PCK. `wyrd console` in a build where `OS.is_debug_build()` is false, or where that script did not load, prints `wyrd: console is not in this build` and exits 1.

Commands:

- `set <fact> <value>` writes a world fact through `set`. The value is the rest of the line, compiled as an expression. Provenance `scene` is `console` and `choice` is `set`.
- `kill <role>` vacates the holder with reason `died`.
- `vacate <role>` vacates the holder with reason `left`.
- `replace <role> <entity>` assigns that holder.
- `time <minutes>` calls `tick` with a whole number of minutes, zero or more.
- `event <name> [field=value ...]` emits that event. `true` and `false` are bools, a whole number is an int, a decimal is a float, and any other token is a symbol.
- `scene <id>` opens a scene and prints the waiting line, or numbered choices.
- `advance` passes a waiting line.
- `choose <n>` picks a choice. `n` is the printed number, starting at 1.
- `quit` ends the prompt.

A blank line and a line that starts with `#` are ignored. `quit` and those lines are not traced. An unknown verb is not a command and is not traced. A known command that fails still writes one trace line with `ok=false`.

A scene run from the console keeps that scene's own provenance on its effects. The `scene`, `advance`, and `choose` commands still record source `console`.

When tracing is on, one line is logged per command: `wyrd console command=%s key=%s role=%s source=console ok=%s`. `path` is `console`. `key` is the fact, role, event, scene, or minute text. `role` is set for `kill`, `vacate`, and `replace`. An empty key or role prints `-`. The prefix matches `path`, `key`, or `role`. Load does not log one. Replay skips it. The CLI does not turn tracing on.

`wyrd console <pack> [--save path] [--out path] [--cmd <line> ...]` boots a runtime, optionally loads a save, then runs commands. Repeated `--cmd` runs those lines and does not read stdin. With no `--cmd`, the prompt prints `wyrd>` and reads lines until `quit` or end of input. `--out` (or `-o`) writes `save_state()` JSON after the commands when every command succeeded. An open scene prints `wyrd: console could not write the save: a scene is open` and does not write. A failed command does not stop the rest and does not write the file. The process exits 1 when any command failed or the save could not be written.
