extends SceneTree

const _Cli := preload("res://addons/wyrd/cli/wyrd_cli_app.gd")

var _watch: WyrdCheckWatch

## Command-line entry. With no arguments, prints the version and command list.
## [code]check[/code] compiles [code].wyrd[/code] files and prints diagnostics.
## [code]check --watch[/code] stays running and re-checks when a listed file changes.

func _init() -> void:
	var result: Dictionary = _Cli.execute(OS.get_cmdline_user_args())
	if result.has("watch"):
		_watch = result["watch"]
		Engine.max_fps = 10
		return
	var output := str(result["output"])
	if not output.is_empty():
		print(output.strip_edges())
	quit(int(result["exit_code"]))


func _process(_delta: float) -> bool:
	if _watch == null:
		return false
	var text := _watch.tick(Time.get_ticks_msec())
	if not text.is_empty():
		print(text.strip_edges())
	return false
