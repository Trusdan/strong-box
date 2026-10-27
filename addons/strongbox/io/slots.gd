class_name StrongboxSlots
extends RefCounted

## Named save slots with metadata for a load menu, a quicksave slot and an autosave ring.
##
## @experimental
## Each slot is a folder [code]<root>/<slot_id>/[/code] holding [code]save.json[/code] (written
## by [StrongboxFileStore], with its backups), a small [code]meta.json[/code] so a load menu can
## list slots without opening any save, and an optional [code]thumb.png[/code].
## [br][br]
## [code]meta.json[/code] is a cache: it is a [StrongboxEnvelope] whose body holds
## [code]slot_id[/code], [code]kind[/code], [code]saved_unix[/code], [code]playtime_s[/code],
## [code]schema_version[/code], [code]game_version[/code], [code]label[/code] and
## [code]seq[/code] (a write counter that orders slots saved in the same second). If it is
## missing or damaged, [method list] rebuilds it from the save's header.

## The slot id is not 1-32 characters of [code]a-z 0-9 _ -[/code].
const E_BAD_SLOT: StringName = &"E_BAD_SLOT"
## There is no slot with that id.
const E_NO_SLOT: StringName = &"E_NO_SLOT"
## Writing or reading the thumbnail failed (the save itself is not affected).
const E_THUMBNAIL: StringName = &"E_THUMBNAIL"

## The quicksave slot id.
const QUICK_ID: String = "quick"
## Autosave slot ids are this prefix plus an index from 0 to [member autosave_count] - 1.
const AUTO_PREFIX: String = "auto_"
## Thumbnails are scaled down to fit inside this size.
const THUMBNAIL_MAX: Vector2i = Vector2i(320, 180)

const _SAVE_FILE: String = "save.json"
const _META_FILE: String = "meta.json"
const _THUMB_FILE: String = "thumb.png"

## The file store that writes [code]save.json[/code]. Set [member StrongboxFileStore.root] on it
## to change the save folder.
var store: StrongboxFileStore = StrongboxFileStore.new()
## How many autosave slots the ring holds.
var autosave_count: int = 3
## Test-only hook: how many times [method list] has read a [code]save.json[/code].
var _save_reads: int = 0

var _id_regex: RegEx = RegEx.create_from_string("^[a-z0-9_-]{1,32}$")
var _auto_regex: RegEx = RegEx.create_from_string("^auto_([0-9]+)$")


## Returns [code]true[/code] if [param slot_id] is a valid slot id.
## @experimental
func is_valid_id(slot_id: String) -> bool:
	return _id_regex.search(slot_id) != null


## Returns [code]"quick"[/code], [code]"auto"[/code] or [code]"manual"[/code] for [param slot_id].
## @experimental
func kind_of(slot_id: String) -> String:
	if slot_id == QUICK_ID:
		return "quick"
	if _auto_regex.search(slot_id) != null:
		return "auto"
	return "manual"


## Returns [code]true[/code] if the slot has a save file or a backup of one.
## @experimental
func exists(slot_id: String) -> bool:
	if not is_valid_id(slot_id):
		return false
	var save: String = _path(slot_id, _SAVE_FILE)
	if save == "":
		return false
	if FileAccess.file_exists(save):
		return true
	for i: int in range(1, store.backup_count + 1):
		if FileAccess.file_exists("%s.bak%d" % [save, i]):
			return true
	return false


## Writes save [param text] (from [method StrongboxEnvelope.pack]) to [param slot_id], then its
## [code]meta.json[/code]. [param label] holds load-menu labels such as a location name; when it
## is empty, the save header's [code]meta[/code] is used. On success
## [member StrongboxResult.value] is the slot's metadata. A failed [code]meta.json[/code] write
## does not fail the save: [method list] rebuilds it.
## @experimental
func write(slot_id: String, text: String, label: Dictionary = {}) -> StrongboxResult:
	if not is_valid_id(slot_id):
		return _bad_id(slot_id)
	var unpacked: StrongboxResult = StrongboxEnvelope.unpack(text)
	if not unpacked.ok:
		return unpacked
	var seq: int = _next_seq()
	var written: StrongboxResult = store.write_atomic(_relative(slot_id, _SAVE_FILE), text)
	if not written.ok:
		return written
	var meta: Dictionary = _meta_from_header(slot_id, unpacked.value["header"])
	if not label.is_empty():
		meta["label"] = label
	meta["seq"] = seq
	_write_meta(slot_id, meta)
	return StrongboxResult.success(meta)


## Reads [param slot_id] through [method StrongboxFileStore.read_verified], so a damaged save
## falls back to its backups. On success [member StrongboxResult.value] is that method's
## Dictionary ([code]text[/code], [code]save[/code], [code]source[/code], [code]failures[/code]).
## @experimental
func read(slot_id: String) -> StrongboxResult:
	if not is_valid_id(slot_id):
		return _bad_id(slot_id)
	if not exists(slot_id):
		return StrongboxResult.failure(E_NO_SLOT, "There is no slot \"%s\"." % slot_id)
	return store.read_verified(_relative(slot_id, _SAVE_FILE))


## Deletes the folder of [param slot_id] and everything in it. Nothing outside that folder,
## or outside the root, is touched.
## @experimental
func delete(slot_id: String) -> StrongboxResult:
	if not is_valid_id(slot_id):
		return _bad_id(slot_id)
	var folder: String = store.resolve(slot_id)
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return StrongboxResult.failure(E_NO_SLOT, "There is no slot \"%s\"." % slot_id)
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	if DirAccess.remove_absolute(folder) != OK:
		return StrongboxResult.failure(E_NO_SLOT, "Could not remove the slot folder %s." % folder)
	return StrongboxResult.success(slot_id)


## Returns the metadata of every slot, newest first. Each entry has [code]damaged[/code]:
## [code]true[/code] when the slot's save cannot be read (its other fields may then be empty).
## Folders that are not valid slots are skipped. A valid [code]meta.json[/code] is used as is,
## so listing does not open any [code]save.json[/code]; a missing or damaged one is rebuilt.
## @experimental
func list() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var root: String = store.root.simplify_path()
	if not DirAccess.dir_exists_absolute(root):
		return entries
	for slot_id: String in DirAccess.get_directories_at(root):
		if not exists(slot_id):
			continue
		var meta: Variant = _read_meta(slot_id)
		if meta == null:
			meta = _rebuild_meta(slot_id)
		entries.append(meta)
	entries.sort_custom(_newer_first)
	return entries


## Returns the newest slot of any kind, or an empty Dictionary when there are none.
## @experimental
func latest() -> Dictionary:
	var entries: Array[Dictionary] = list()
	return entries[0] if not entries.is_empty() else {}


## Returns the autosave slot to write next: the first empty one in the ring, otherwise the
## one written longest ago.
## @experimental
func next_autosave_id() -> String:
	var oldest: Dictionary = {}
	for i: int in autosave_count:
		var slot_id: String = AUTO_PREFIX + str(i)
		if not exists(slot_id):
			return slot_id
		var meta: Variant = _read_meta(slot_id)
		if meta == null:
			meta = _rebuild_meta(slot_id)
		if oldest.is_empty() or _newer_first(oldest, meta):
			oldest = meta
	return oldest.get("slot_id", AUTO_PREFIX + "0")


## Saves [param image] as the slot's PNG thumbnail, scaled down to fit
## [constant THUMBNAIL_MAX]. Never affects the save itself.
## @experimental
func write_thumbnail(slot_id: String, image: Image) -> StrongboxResult:
	if not is_valid_id(slot_id):
		return _bad_id(slot_id)
	if image == null or image.is_empty():
		return StrongboxResult.failure(E_THUMBNAIL, "The thumbnail image is empty.")
	var thumb: Image = image.duplicate() as Image
	if thumb.is_compressed() and thumb.decompress() != OK:
		return StrongboxResult.failure(E_THUMBNAIL, "Could not decompress the thumbnail image.")
	var size: Vector2i = thumb.get_size()
	var scale: float = minf(1.0, minf(float(THUMBNAIL_MAX.x) / size.x, float(THUMBNAIL_MAX.y) / size.y))
	if scale < 1.0:
		thumb.resize(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)), Image.INTERPOLATE_BILINEAR)
	var path: String = _path(slot_id, _THUMB_FILE)
	if path == "" or DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return StrongboxResult.failure(E_THUMBNAIL, "Could not create the folder for slot \"%s\"." % slot_id)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return StrongboxResult.failure(E_THUMBNAIL, "Could not write the thumbnail for slot \"%s\"." % slot_id)
	file.store_buffer(thumb.save_png_to_buffer())
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return StrongboxResult.failure(E_THUMBNAIL, "Could not write the thumbnail for slot \"%s\"." % slot_id)
	return StrongboxResult.success(path)


## Returns the slot's thumbnail, or [code]null[/code] if it has none or it cannot be read.
## Loaded with [method Image.load_png_from_buffer]; no resource loading is involved.
## @experimental
func read_thumbnail(slot_id: String) -> Image:
	if not is_valid_id(slot_id):
		return null
	var path: String = _path(slot_id, _THUMB_FILE)
	if path == "" or not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var png_signature: PackedByteArray = PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	if bytes.size() < 8 or bytes.slice(0, 8) != png_signature:
		return null
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


func _relative(slot_id: String, file: String) -> String:
	return slot_id.path_join(file)


func _path(slot_id: String, file: String) -> String:
	return store.resolve(_relative(slot_id, file))


func _bad_id(slot_id: String) -> StrongboxResult:
	return StrongboxResult.failure(E_BAD_SLOT, "\"%s\" is not a valid slot id (1-32 characters of a-z, 0-9, _ and -)." % slot_id)


func _meta_from_header(slot_id: String, header: Dictionary) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": kind_of(slot_id),
		"saved_unix": header["saved_unix"],
		"playtime_s": header["playtime_s"],
		"schema_version": header["schema_version"],
		"game_version": header["game_version"],
		"label": header["meta"],
		"seq": 0,
		"damaged": false,
	}


## A file store for meta.json: no backups, since meta.json can always be rebuilt.
func _meta_store() -> StrongboxFileStore:
	var meta_store: StrongboxFileStore = StrongboxFileStore.new()
	meta_store.root = store.root
	meta_store.backup_count = 0
	return meta_store


func _write_meta(slot_id: String, meta: Dictionary) -> void:
	var packed: StrongboxResult = StrongboxEnvelope.pack(meta, {})
	if packed.ok:
		_meta_store().write_atomic(_relative(slot_id, _META_FILE), packed.value)


## Returns the slot's metadata from meta.json, or null if it is missing, damaged or belongs
## to another slot.
func _read_meta(slot_id: String) -> Variant:
	if not FileAccess.file_exists(_path(slot_id, _META_FILE)):
		return null
	var read_result: StrongboxResult = _meta_store().read_verified(_relative(slot_id, _META_FILE))
	if not read_result.ok:
		return null
	var meta: Dictionary = read_result.value["save"]["body"]
	if not (meta.get("slot_id") is String and meta["slot_id"] == slot_id):
		return null
	if not (meta.get("saved_unix") is int and meta.get("seq") is int):
		return null
	meta["damaged"] = false
	return meta


## Rebuilds metadata from the save header and rewrites meta.json. A save that cannot be read
## gives a [code]damaged: true[/code] entry instead.
func _rebuild_meta(slot_id: String) -> Dictionary:
	_save_reads += 1
	var read_result: StrongboxResult = store.read_verified(_relative(slot_id, _SAVE_FILE))
	if not read_result.ok:
		return {"slot_id": slot_id, "kind": kind_of(slot_id), "saved_unix": 0, "playtime_s": 0.0,
			"schema_version": 0, "game_version": "", "label": {}, "seq": 0, "damaged": true}
	var meta: Dictionary = _meta_from_header(slot_id, read_result.value["save"]["header"])
	_write_meta(slot_id, meta)
	return meta


func _next_seq() -> int:
	var highest: int = 0
	for meta: Dictionary in list():
		highest = maxi(highest, int(meta.get("seq", 0)))
	return highest + 1


## Sort order: newer save time first, then the later write, then slot id.
func _newer_first(a: Dictionary, b: Dictionary) -> bool:
	if a["saved_unix"] != b["saved_unix"]:
		return a["saved_unix"] > b["saved_unix"]
	if a["seq"] != b["seq"]:
		return a["seq"] > b["seq"]
	return str(a["slot_id"]) < str(b["slot_id"])
