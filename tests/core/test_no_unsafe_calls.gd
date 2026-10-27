extends GutTest

## Source scan: the addon must never deserialize save data with engine calls that can create
## objects or run code. See "Unsafe-call rule" in docs/format.md.

const ADDON_DIR: String = "res://addons/strongbox"
const MARKER: String = "# strongbox: allow-load (res:// allow-list checked)"
## The only files allowed to carry the marker. A new exception must be agreed on its task first.
const MARKER_ALLOWED_IN: Array[String] = ["res://addons/strongbox/state/world_store.gd"]
## Always refused, marker or not.
const ALWAYS_FORBIDDEN: Array[String] = [
	"\\bstr_to_var\\b", "\\bbytes_to_var\\b", "\\bbytes_to_var_with_objects\\b",
	"\\bvar_to_str\\b", "\\bResourceLoader\\b",
]
## A bare load( or preload( call: not a member call (.load) and not part of a longer name.
const BARE_LOAD: String = "(?<![\\w.])(?:pre)?load\\s*\\("
## The definition of a method named load, which is allowed.
const LOAD_DEFINITION: String = "\\bfunc\\s+(?:pre)?load\\s*\\("


## Splits [param line] into its code part and its comment part. A "#" inside a string literal
## does not start a comment.
static func split_comment(line: String) -> PackedStringArray:
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if quote == "":
			if ch == "#":
				return PackedStringArray([line.substr(0, i), line.substr(i)])
			if ch == "\"" or ch == "'":
				quote = ch
		elif ch == "\\":
			i += 1
		elif ch == quote:
			quote = ""
		i += 1
	return PackedStringArray([line, ""])


## Returns the problems found on one source line; empty when the line is fine.
static func problems_in_line(line: String) -> Array[String]:
	var found: Array[String] = []
	var parts: PackedStringArray = split_comment(line)
	var code: String = parts[0]
	for pattern: String in ALWAYS_FORBIDDEN:
		if RegEx.create_from_string(pattern).search(code) != null:
			found.append(pattern.replace("\\b", ""))
	var allowed: bool = parts[1].contains(MARKER)
	var without_definition: String = RegEx.create_from_string(LOAD_DEFINITION).sub(code, "func _defined(", true)
	if not allowed and RegEx.create_from_string(BARE_LOAD).search(without_definition) != null:
		found.append("bare load()/preload()")
	return found


func _addon_scripts(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			files.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		files.append_array(_addon_scripts(dir_path.path_join(sub)))
	return files


func test_scanner_rules() -> void:
	var bad: Array[String] = [
		"var data = str_to_var(text)",
		"var v := bytes_to_var(buf)",
		"var v := bytes_to_var_with_objects(buf)",
		"var s := var_to_str(x)",
		"var r := ResourceLoader.load(path)",
		"var scene := load(path)",
		"const S := preload(\"res://x.tscn\")",
		"var x := \"a # not a comment\"; var y := load(p)",
		"var r := ResourceLoader.load(p) " + MARKER,
	]
	var good: Array[String] = [
		"var img := Image.load_png_from_buffer(bytes)",
		"func load(slot_id: String) -> StrongboxResult:",
		"var result := await Strongbox.load(\"slot1\")",
		"# load(path) in a comment is fine",
		"## Never call str_to_var on save data.",
		"var n := unload(x) + overload(y)",
		"var label := \"load\"",
		"var scene := load(path) " + MARKER,
	]
	for line: String in bad:
		assert_false(problems_in_line(line).is_empty(), "should be flagged: %s" % line)
	for line: String in good:
		assert_eq(problems_in_line(line), [] as Array[String], "should pass: %s" % line)


func test_addon_source_has_no_unsafe_calls() -> void:
	var files: Array[String] = _addon_scripts(ADDON_DIR)
	assert_true(files.has(ADDON_DIR.path_join("core/codec.gd")), "the scan must see the addon's scripts")
	var report: Array[String] = []
	for path: String in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for n: int in lines.size():
			for problem: String in problems_in_line(lines[n]):
				report.append("%s:%d: %s" % [path, n + 1, problem])
			if split_comment(lines[n])[1].contains(MARKER) and not MARKER_ALLOWED_IN.has(path):
				report.append("%s:%d: allow-load marker is only allowed in %s" % [path, n + 1, MARKER_ALLOWED_IN])
	assert_eq(report, [] as Array[String], "\n".join(report))
