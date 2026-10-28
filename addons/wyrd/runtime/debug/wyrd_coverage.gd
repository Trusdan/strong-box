class_name WyrdCoverage
extends RefCounted

## Hit counts for storylets, slot variants, and line ids.
##
## @experimental
## Recording is off until [member enabled] is set. A release build does not
## turn it on. Counts are not part of a save. [method merge] adds them to a
## JSON file, then clears the in-memory delta. The default file is
## [constant DEFAULT_PATH].

const DEFAULT_PATH := "user://wyrd_coverage.json"
const KINDS: PackedStringArray = ["line", "storylet", "variant"]

## When true, [method hit] increments. Default false in every build.
var enabled: bool = false
## [code](kind, id, count, path, line)[/code] after a recorded hit.
var on_hit: Callable = Callable()
## [code](missed)[/code] after [method render].
var on_report: Callable = Callable()

var _counts: Dictionary = {}
var _sites: Dictionary = {}


func _init() -> void:
	_counts = _empty()
	_sites = _empty()


func bind(content: WyrdContent) -> void:
	_sites = _empty()
	if content == null:
		return
	for item in content.coverage_sites:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var kind := String(row.get("kind", ""))
		var id := String(row.get("id", ""))
		if not _sites.has(kind) or id.is_empty():
			continue
		var bag: Dictionary = _sites[kind]
		if bag.has(id):
			continue
		bag[id] = {
			"line": int(row.get("line", 0)),
			"path": String(row.get("path", "")),
		}
		_sites[kind] = bag


func clear() -> void:
	_counts = _empty()


func count(kind: String, id: String) -> int:
	if not _counts.has(kind):
		return 0
	var bag: Dictionary = _counts[kind]
	return int(bag.get(id, 0))


func counts() -> Dictionary:
	return _copy(_counts)


## Records one hit. Does nothing while [member enabled] is false.
## An unknown [param kind] is [code]push_error[/code] and is not stored.
func hit(kind: String, id: String) -> void:
	if not enabled or id.is_empty():
		return
	if not _counts.has(kind):
		push_error("Wyrd.coverage: unknown kind \"%s\"" % kind)
		return
	var bag: Dictionary = _counts[kind]
	var total := int(bag.get(id, 0)) + 1
	bag[id] = total
	_counts[kind] = bag
	if not on_hit.is_valid():
		return
	var found := site(kind, id)
	on_hit.call(kind, id, total, String(found["path"]), int(found["line"]))


func site(kind: String, id: String) -> Dictionary:
	if not _sites.has(kind):
		return {"line": 0, "path": ""}
	var bag: Dictionary = _sites[kind]
	if not bag.has(id):
		return {"line": 0, "path": ""}
	var row: Dictionary = bag[id]
	return {"line": int(row.get("line", 0)), "path": String(row.get("path", ""))}


## Catalog ids whose count in [param counts] is 0. Ordered by kind, then id.
func missed_rows(counts: Dictionary) -> Array:
	var rows: Array = []
	for kind in KINDS:
		var sites: Dictionary = _sites.get(kind, {})
		var keys: Array = sites.keys()
		keys.sort()
		var bag: Variant = counts.get(kind, {})
		var hits: Dictionary = bag if bag is Dictionary else {}
		for id in keys:
			if int(hits.get(id, 0)) > 0:
				continue
			var found: Dictionary = sites[id]
			rows.append({
				"id": String(id),
				"kind": kind,
				"line": int(found.get("line", 0)),
				"path": String(found.get("path", "")),
			})
	return rows


## Never-hit table for [param counts]. One report line is logged when tracing is on.
func render(counts: Dictionary) -> String:
	var rows := missed_rows(counts)
	if on_report.is_valid():
		on_report.call(rows.size())
	return _table(rows)


## Adds in-memory counts to [param path] and clears that delta.
## A missing file starts at zero. A bad file is [code]push_error[/code] and is left unchanged.
func merge(path: String = DEFAULT_PATH) -> bool:
	var read := read_file(path)
	if not bool(read["ok"]):
		return false
	var prior: Dictionary = read["counts"]
	if not write_file(path, add_counts(prior, _counts)):
		return false
	_counts = _empty()
	return true


static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"counts": _empty(), "ok": true}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("Wyrd.coverage: file is not a JSON object")
		return {"counts": _empty(), "ok": false}
	var root: Dictionary = parsed
	var raw: Variant = root.get("counts", {})
	if not (raw is Dictionary):
		push_error("Wyrd.coverage: counts must be an object")
		return {"counts": _empty(), "ok": false}
	var counts := _normalize(raw)
	if counts.is_empty():
		return {"counts": _empty(), "ok": false}
	return {"counts": counts, "ok": true}


static func write_file(path: String, counts: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Wyrd.coverage: could not write %s" % path)
		return false
	file.store_string(JSON.stringify(_document(counts), "\t"))
	return true


static func add_counts(left: Dictionary, right: Dictionary) -> Dictionary:
	var out := _empty()
	for kind in KINDS:
		var bag: Dictionary = out[kind]
		_add_bag(bag, left.get(kind, {}))
		_add_bag(bag, right.get(kind, {}))
		out[kind] = bag
	return out


static func _document(counts: Dictionary) -> Dictionary:
	var body := {}
	for kind in KINDS:
		var raw: Variant = counts.get(kind, {})
		var bag: Dictionary = raw if raw is Dictionary else {}
		var keys: Array = bag.keys()
		keys.sort()
		var stored := {}
		for id in keys:
			var total := int(bag[id])
			if total <= 0:
				continue
			stored[String(id)] = total
		body[kind] = stored
	return {"counts": body}


static func _normalize(raw: Dictionary) -> Dictionary:
	var out := _empty()
	for key in raw.keys():
		var kind := String(key)
		if not out.has(kind):
			continue
		var value: Variant = raw[key]
		if not (value is Dictionary):
			push_error("Wyrd.coverage: %s must be an object" % kind)
			return {}
		var bag: Dictionary = out[kind]
		var rows: Dictionary = value
		for id in rows.keys():
			var total: Variant = rows[id]
			if typeof(total) != TYPE_INT and typeof(total) != TYPE_FLOAT:
				push_error("Wyrd.coverage: count for \"%s\" must be a number" % String(id))
				return {}
			var whole := int(total)
			if whole <= 0:
				continue
			bag[String(id)] = whole
		out[kind] = bag
	return out


static func _add_bag(into: Dictionary, raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	var rows: Dictionary = raw
	for id in rows.keys():
		var name := String(id)
		into[name] = int(into.get(name, 0)) + int(rows[id])


static func _empty() -> Dictionary:
	return {"line": {}, "storylet": {}, "variant": {}}


static func _copy(counts: Dictionary) -> Dictionary:
	var out := _empty()
	for kind in KINDS:
		var raw: Variant = counts.get(kind, {})
		var bag: Dictionary = raw if raw is Dictionary else {}
		var copy := {}
		for id in bag.keys():
			copy[String(id)] = int(bag[id])
		out[kind] = copy
	return out


func _table(rows: Array) -> String:
	var header := PackedStringArray(["kind", "id", "at"])
	var lines: Array = []
	for item in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var path := String(row.get("path", ""))
		var at := "%s:%d" % [path, int(row.get("line", 0))] if not path.is_empty() else "-"
		lines.append(PackedStringArray([
			String(row.get("kind", "")),
			String(row.get("id", "")),
			at,
		]))
	return _format(header, lines)


func _format(header: PackedStringArray, rows: Array) -> String:
	var width := PackedInt32Array()
	width.resize(header.size())
	for i in header.size():
		width[i] = header[i].length()
	for item in rows:
		var cells: PackedStringArray = item
		for i in header.size():
			if cells[i].length() > width[i]:
				width[i] = cells[i].length()
	var lines := PackedStringArray()
	lines.append(_line(header, width))
	for item in rows:
		lines.append(_line(item, width))
	return "\n".join(lines) + "\n"


func _line(cells: PackedStringArray, width: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for i in cells.size():
		parts.append(cells[i].rpad(width[i]))
	return "  ".join(parts)
