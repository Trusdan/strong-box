extends SceneTree

## Rewrites the cross-platform golden save fixtures in tests/fixtures/golden/.
##
## Off by default. Without --write it only reports which fixtures differ and exits 1 if any do.
## Run from the repository root:
##   godot --headless --path . -s res://tools/regenerate_golden_fixtures.gd            (check)
##   godot --headless --path . -s res://tools/regenerate_golden_fixtures.gd -- --write (rewrite)
## Regenerate only on purpose (a deliberate dataset or format change), and say in the pull
## request which platform produced the new files.

const Dataset: GDScript = preload("res://tests/fixtures/golden/golden_dataset.gd")


func _init() -> void:
	var write: bool = OS.get_cmdline_user_args().has("--write")
	var differing: int = 0
	for file_name: String in Dataset.FIXTURES:
		var path: String = Dataset.FOLDER + file_name
		var packed: StrongboxResult = Dataset.pack_fixture(file_name)
		if not packed.ok:
			printerr("%s: pack failed: %s" % [file_name, packed.message])
			quit(2)
			return
		var bytes: PackedByteArray = (packed.value as String).to_utf8_buffer()
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
			print("%s: up to date" % file_name)
			continue
		differing += 1
		if not write:
			print("%s: differs (run with -- --write to rewrite it)" % file_name)
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		print("%s: written (%d bytes on %s)" % [file_name, bytes.size(), OS.get_name()])
	quit(1 if differing > 0 and not write else 0)
