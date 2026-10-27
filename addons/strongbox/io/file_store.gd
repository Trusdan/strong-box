class_name StrongboxFileStore
extends RefCounted

## Writes save files so a crash or power cut mid-save can never destroy the last good save,
## and recovers from a damaged file on load.
##
## @experimental
## [method write_atomic] writes [code]<path>.tmp[/code], reads it back and checks it, rotates
## the backups ([code]<path>.bak1[/code], [code].bak2[/code], ...), then renames the temp file
## into place. [method read_verified] returns the newest file that unpacks cleanly. All paths
## must stay inside [member root]. See "Crash safety" in [code]docs/format.md[/code].

## Writing the temp file failed.
const E_WRITE: StringName = &"E_WRITE"
## The temp file did not read back identical, or did not unpack with a valid checksum.
const E_VERIFY: StringName = &"E_VERIFY"
## Rotating the backups or renaming the temp file into place failed.
const E_RENAME: StringName = &"E_RENAME"
## Not enough free disk space for the new file.
const E_DISK: StringName = &"E_DISK"
## The path is not inside [member root], or is not a plain relative file path.
const E_BAD_PATH: StringName = &"E_BAD_PATH"
## Neither the file nor any backup unpacks cleanly.
const E_NO_VALID_SAVE: StringName = &"E_NO_VALID_SAVE"
## The file does not exist (only used in the failure list of [method read_verified]).
const E_MISSING: StringName = &"E_MISSING"

## The default folder for save files.
const DEFAULT_ROOT: String = "user://saves"
const _TMP_SUFFIX: String = ".tmp"

## How many older copies to keep ([code].bak1[/code] is the newest). 0 keeps none.
var backup_count: int = 2
## The folder every path must stay inside. Relative paths are resolved against it.
var root: String = DEFAULT_ROOT
## Test-only hook. Set to [code]&"space"[/code], [code]&"write"[/code], [code]&"verify"[/code],
## [code]&"rotate"[/code] or [code]&"rename"[/code] to simulate a failure at that step:
## "space" reports a full disk, "rename" simulates the final rename failing (and is rolled
## back), and the others stop right after the step, as a crash would.
var _fail_at: StringName = &""


## Writes [param text] (a [StrongboxEnvelope] save) to [param path] safely. On any failure the
## previous good save can still be read with [method read_verified]. On success
## [member StrongboxResult.value] is the full path written.
## @experimental
func write_atomic(path: String, text: String) -> StrongboxResult:
	var full: String = resolve(path)
	if full == "":
		return _bad_path(path)
	var dir: String = full.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return StrongboxResult.failure(E_WRITE, "Could not create the folder %s." % dir)
	if not _has_space_for(dir, text):
		return StrongboxResult.failure(E_DISK, "Not enough free disk space to write %s." % full)
	var tmp: String = full + _TMP_SUFFIX

	# 1. Write the temp file, flush and close.
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return StrongboxResult.failure(E_WRITE, "Could not open %s for writing (error %d)." % [tmp, FileAccess.get_open_error()])
	var stored: bool = file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK:
		DirAccess.remove_absolute(tmp)
		return StrongboxResult.failure(E_WRITE, "Could not write %s (error %d)." % [tmp, write_error])
	if _fail_at == &"write":
		return StrongboxResult.failure(E_WRITE, "Simulated failure after writing the temp file.")

	# 2. Read it back and check it is identical and unpacks with a valid checksum.
	var check: String = _read_text(tmp)
	if check != text or not StrongboxEnvelope.unpack(check).ok:
		DirAccess.remove_absolute(tmp)
		return StrongboxResult.failure(E_VERIFY, "The temp file %s did not read back as a valid save." % tmp)
	if _fail_at == &"verify":
		return StrongboxResult.failure(E_VERIFY, "Simulated failure after verifying the temp file.")

	# 3. Rotate backups: drop the oldest, shift the rest, move the current file to .bak1.
	if backup_count > 0:
		var oldest: String = _backup_path(full, backup_count)
		if FileAccess.file_exists(oldest) and DirAccess.remove_absolute(oldest) != OK:
			return StrongboxResult.failure(E_RENAME, "Could not remove the oldest backup %s." % oldest)
		for i: int in range(backup_count - 1, 0, -1):
			var from: String = _backup_path(full, i)
			if FileAccess.file_exists(from) and DirAccess.rename_absolute(from, _backup_path(full, i + 1)) != OK:
				return StrongboxResult.failure(E_RENAME, "Could not rotate the backup %s." % from)
		if FileAccess.file_exists(full) and DirAccess.rename_absolute(full, _backup_path(full, 1)) != OK:
			return StrongboxResult.failure(E_RENAME, "Could not move %s to its first backup." % full)
	if _fail_at == &"rotate":
		return StrongboxResult.failure(E_RENAME, "Simulated failure after rotating the backups.")

	# 4. Rename the temp file into place. With backups, the target no longer exists here, so
	# this never relies on replacing a file (which is not atomic on Windows).
	var renamed: bool = _fail_at != &"rename" and DirAccess.rename_absolute(tmp, full) == OK
	if not renamed:
		var first_backup: String = _backup_path(full, 1)
		if backup_count > 0 and not FileAccess.file_exists(full) and FileAccess.file_exists(first_backup):
			DirAccess.rename_absolute(first_backup, full)
		DirAccess.remove_absolute(tmp)
		return StrongboxResult.failure(E_RENAME, "Could not rename %s into place." % tmp)
	return StrongboxResult.success(full)


## Reads [param path], falling back to [code].bak1[/code], [code].bak2[/code], ... and returns
## the first that unpacks cleanly. On success [member StrongboxResult.value] is a Dictionary:
## [code]text[/code] (the file text), [code]save[/code] (the unpacked header and body),
## [code]source[/code] ([code]"main"[/code], [code]"bak1"[/code], ...) and [code]failures[/code]
## (one [code]{file, code, message}[/code] entry per file tried before it). Leftover temp files
## older than the main file are deleted; nothing else is.
## @experimental
func read_verified(path: String) -> StrongboxResult:
	var full: String = resolve(path)
	if full == "":
		return _bad_path(path)
	_clean_stale_tmp(full)
	var failures: Array[Dictionary] = []
	for i: int in backup_count + 1:
		var candidate: String = full if i == 0 else _backup_path(full, i)
		var source: String = "main" if i == 0 else "bak%d" % i
		if not FileAccess.file_exists(candidate):
			failures.append({"file": candidate, "code": E_MISSING, "message": "The file does not exist."})
			continue
		var text: String = _read_text(candidate)
		var unpacked: StrongboxResult = StrongboxEnvelope.unpack(text)
		if unpacked.ok:
			return StrongboxResult.success({"text": text, "save": unpacked.value, "source": source, "failures": failures})
		failures.append({"file": candidate, "code": unpacked.code, "message": unpacked.message})
	var lines: PackedStringArray = PackedStringArray()
	for failure: Dictionary in failures:
		lines.append("%s: %s" % [failure["file"], failure["code"]])
	var result: StrongboxResult = StrongboxResult.failure(E_NO_VALID_SAVE, "No valid save at %s (%s)." % [full, ", ".join(lines)])
	result.value = {"failures": failures}
	return result


## Returns the full path for [param path] inside [member root], or an empty string if it would
## leave [member root], points into [code]res://[/code], or is not a plain file path.
## @experimental
func resolve(path: String) -> String:
	var base: String = root.simplify_path()
	if path == "" or base == "" or base.begins_with("res://") or path.contains("\\"):
		return ""
	var full: String
	if path.contains("://") or path.begins_with("/"):
		full = path.simplify_path()
	else:
		if path.contains(":"):
			return ""
		full = base.path_join(path).simplify_path()
	if full.begins_with("res://") or not full.begins_with(base + "/"):
		return ""
	return full


func _bad_path(path: String) -> StrongboxResult:
	return StrongboxResult.failure(E_BAD_PATH, "The path \"%s\" is not a file inside %s." % [path, root])


func _backup_path(full: String, index: int) -> String:
	return "%s.bak%d" % [full, index]


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _has_space_for(dir: String, text: String) -> bool:
	if _fail_at == &"space":
		return false
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return true
	var left: int = access.get_space_left()
	# 0 means the platform could not tell; only refuse when it reports too little.
	return left == 0 or left > text.to_utf8_buffer().size() * 2


## Deletes a leftover temp file only when it is older than the main file. A newer temp file
## may be an unfinished newer save; the next write replaces it.
func _clean_stale_tmp(full: String) -> void:
	var tmp: String = full + _TMP_SUFFIX
	if FileAccess.file_exists(tmp) and FileAccess.file_exists(full):
		if FileAccess.get_modified_time(tmp) < FileAccess.get_modified_time(full):
			DirAccess.remove_absolute(tmp)
