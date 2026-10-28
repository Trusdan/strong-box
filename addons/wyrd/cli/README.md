# cli

`wyrd_cli.gd` is the command-line entry. With no arguments it prints the addon version and the command list. The text and the exit status come from `WyrdCli`, so tests can call it without starting another process.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check <file-or-dir>
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest <pack.wyrdmanifest.tres>
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- tag-lines <file-or-dir> [--dry-run]
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- export-json <file-or-dir> [-o <out.json>]
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- facts <file-or-dir> [--json]
```

`check` compiles and links one pack. A path with no manifest is one pack named after the folder (or the file stem). `--manifest` uses the listed files and reads `wyrd_commands.json` beside the manifest. A missing command file is one info line when a `do` exists. `check` exits 1 on an error. `--strict` also fails on warnings. `W_RECAP_UNMARKED` is one of those warnings: `check` prints `warning[W_RECAP_UNMARKED]` and exits 0, and `check --strict` exits 1. There is no separate suppress switch. `recap: true` and `recap: false` on the fact silence that line, and the code greps like `W_FACT_NEVER_SET`.

`choices` prints fact writes from a save's provenance map: key, scene, choice, time, and recap. `--scene`, `--choice`, `--prefix`, `--from`, and `--to` filter it. `--from` and `--to` are inclusive game minutes. With no save the table is only the header.

`coverage` prints storylets, slot variants, and line ids that have no count in the merge file. Columns are kind, id, and `path:line`. `--file` selects that JSON file. The default is `user://wyrd_coverage.json`. A missing file treats every id as never hit. The command does not record hits and does not turn tracing on.

`console <pack>` is the playtest prompt. `--cmd` may be repeated and runs those lines without reading stdin. With no `--cmd`, the prompt prints `wyrd>` and reads until `quit` or end of input. `--save` loads a JSON save first. `--out` (or `-o`) writes the JSON save after those commands when every command succeeded. An open scene refuses that write. A failed command does not write the file. The command does not turn tracing on. A release build prints `wyrd: console is not in this build` and exits 1. See `runtime/console/README.md`.

`generate --dry-run` prints one host proposal, or `none reason=…`, and does not accept it or write a file. It needs `--manifest`, `--source`, and `--key`. `--tier`, `--template`, `--seed` (default 1), and `--save` are optional. `--world` is a JSON file of entities (`kind`, `name`, `tags`, `alive`, `place`, `owner`, `protected`, `out_of_bounds`; missing keys use defaults) registered as the world, spatial, and inventory adapters. Without it, those adapters stay unregistered. A missing `--dry-run` exits 1 with `wyrd: generate needs --dry-run`. A proposal prints `proposal template=… instance=… casts=… params=…`. A rejection prints `none reason=rejected` and one `rule=` line per `gen_reject`. Both exit 0.

`why-not <template>` runs one dry propose of that template when the id is a template and not a storylet. `--source` and `--key` default to `cli` and `why-not`. `--world` is the same JSON file and is registered only for that path. The output is `why_not template=<t> reason=<r>` and one indented `rule=` line per rejection. Exit 0. A storylet id still takes the storylet path, including an unknown id.

`tag-lines` appends a missing `#line:` id and does not change an existing one. `--dry-run` prints `path:line: + #line:<id>` and does not write. `export-json` writes the debug pack document. `facts` prints the cross-reference table; `--json` prints the `xref` object. `test` prints `not implemented`.

`voice-check` prints one `speaker=<id> lines=<n> voiced=<n> variable=<n>` row per speaker, then one indented `<id> <context>` row for each line that interpolates variable text. It exits 1 when any line does. `script-export --speaker <id>` writes `id= text= tags= scene= context=` for that speaker, including holder variants of those lines, sorted by id. `unvoiced-report` lists every line id that has no audio. `--locale` may be repeated and defaults to `en`. `--audio <file.json>` is `{ "<locale>": ["<line-id>", ...] }` of ids that do have audio.
