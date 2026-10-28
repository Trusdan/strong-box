class_name WyrdCheckWatch
extends RefCounted

## Polls a check pack and reprints one cycle when a watched file changes.
##
## @experimental
## The entry script drives [method tick]. There is no runtime state and no editor API.

const POLL_MS := 500

var _manifest := ""
var _root := ""
var _check_args := PackedStringArray()
var _read_md5: Callable
var _run_check: Callable
var _started := false
var _last_poll_ms := 0
var _snapshot: Dictionary = {}


func _init(
	parsed: Dictionary,
	check_args: PackedStringArray = PackedStringArray(),
	read_md5: Callable = Callable(),
	run_check: Callable = Callable()
) -> void:
	_manifest = str(parsed.get("manifest", ""))
	_root = str(parsed.get("note_path", ""))
	_check_args = check_args
	_read_md5 = read_md5 if read_md5.is_valid() else Callable(WyrdCheckWatch, &"_default_md5")
	_run_check = run_check if run_check.is_valid() else Callable(WyrdCheckWatch, &"_default_run")


## Text for one cycle, or empty when nothing changed. [param now_ms] is the caller's clock.
func tick(now_ms: int) -> String:
	if not _started:
		_started = true
		_last_poll_ms = now_ms
		return _cycle()
	if now_ms - _last_poll_ms < POLL_MS:
		return ""
	_last_poll_ms = now_ms
	var snap := _take_snapshot()
	if _same(_snapshot, snap):
		return ""
	_snapshot = snap
	return _emit(_run_check.call(_check_args))


func _cycle() -> String:
	_snapshot = _take_snapshot()
	return _emit(_run_check.call(_check_args))


func _emit(result: Dictionary) -> String:
	var body := str(result.get("output", "")).strip_edges()
	var lines := PackedStringArray()
	lines.append("wyrd: check started")
	if not body.is_empty():
		lines.append(body)
	lines.append(
		"wyrd: check finished errors=%d warnings=%d" % [int(result.get("errors", 0)), int(result.get("warnings", 0))]
	)
	return "\n".join(lines) + "\n"


func _take_snapshot() -> Dictionary:
	var snap := {}
	for path in _watched_paths():
		snap[path] = str(_read_md5.call(path))
	return snap


func _watched_paths() -> PackedStringArray:
	if _manifest.is_empty():
		return WyrdCli._collect(_root)
	var paths := PackedStringArray()
	if FileAccess.file_exists(_manifest):
		paths.append(_manifest)
	var commands := _manifest.get_base_dir() + "/wyrd_commands.json"
	if FileAccess.file_exists(commands):
		paths.append(commands)
	var resource := ResourceLoader.load(_manifest, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is WyrdContentManifest:
		var spec := resource as WyrdContentManifest
		for listed in spec.files:
			paths.append(WyrdCli._resolve(str(listed)))
	return paths


func _same(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in right:
		if not left.has(key) or str(left[key]) != str(right[key]):
			return false
	return true


static func _default_md5(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_md5(path)
	return ""


static func _default_run(args: PackedStringArray) -> Dictionary:
	return WyrdCli._run_check(args)
