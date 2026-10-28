class_name WyrdCliWorld
extends WyrdWorldAdapter

## World, place, and inventory for [code]generate --world[/code] and template [code]why-not[/code].
##
## @experimental
## One JSON object of entities supplies all three adapters. Missing keys use defaults:
## kind and name empty, tags empty, alive true, place and owner empty, protected false,
## and out of bounds false.

var spatial: Spatial
var inventory: Inventory
var _entities: Dictionary = {}


func _init() -> void:
	spatial = Spatial.new()
	inventory = Inventory.new()


static func from_data(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"error": "wyrd: world is not a JSON object\n", "ok": false}
	var listed: Variant = (data as Dictionary).get("entities", {})
	if not (listed is Dictionary):
		return {"error": "wyrd: world is not a JSON object\n", "ok": false}
	var world := WyrdCliWorld.new()
	for id in (listed as Dictionary).keys():
		var row: Variant = (listed as Dictionary)[id]
		if not (row is Dictionary):
			return {"error": "wyrd: world is not a JSON object\n", "ok": false}
		world._add(StringName(str(id)), row)
	return {"error": "", "ok": true, "world": world}


func exists(id: StringName) -> bool:
	return _entities.has(id)


func kind(id: StringName) -> StringName:
	var record := _row(id)
	if record.is_empty():
		return &""
	return StringName(str(record.get("kind", "")))


func tags(id: StringName) -> PackedStringArray:
	var record := _row(id)
	var rows := PackedStringArray()
	if record.is_empty():
		return rows
	var listed: Variant = record.get("tags", PackedStringArray())
	if listed is PackedStringArray:
		return (listed as PackedStringArray).duplicate()
	return rows


func attr(_id: StringName, _key: StringName) -> Variant:
	return null


func is_alive(id: StringName) -> bool:
	var record := _row(id)
	if record.is_empty():
		return false
	return bool(record.get("alive", false))


func display_name(id: StringName) -> String:
	var record := _row(id)
	if record.is_empty():
		return ""
	return str(record.get("name", ""))


func members(_faction: StringName) -> PackedStringArray:
	return PackedStringArray()


## The JSON world does not change during a run, so casts may reuse [method candidates].
func reports_changes() -> bool:
	return true


func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
	var rows := PackedStringArray()
	for id in _entities.keys():
		var who := StringName(str(id))
		if filter != null and filter.kind != &"" and kind(who) != filter.kind:
			continue
		if filter != null and filter.tag != &"" and not tags(who).has(String(filter.tag)):
			continue
		rows.append(String(who))
	rows.sort()
	return rows


func is_protected(id: StringName) -> bool:
	var record := _row(id)
	if record.is_empty():
		return false
	return bool(record.get("protected", false))


func in_bounds(id: StringName, _pack: String) -> bool:
	var record := _row(id)
	if record.is_empty():
		return true
	return not bool(record.get("out_of_bounds", false))


func _add(id: StringName, row: Dictionary) -> void:
	var tag_rows := PackedStringArray()
	var listed: Variant = row.get("tags", [])
	if listed is Array:
		for item in listed:
			tag_rows.append(str(item))
	var alive := true
	if row.has("alive"):
		alive = bool(row["alive"])
	var guarded := false
	if row.has("protected"):
		guarded = bool(row["protected"])
	var out_of_bounds := false
	if row.has("out_of_bounds"):
		out_of_bounds = bool(row["out_of_bounds"])
	_entities[id] = {
		"alive": alive,
		"kind": str(row.get("kind", "")),
		"name": str(row.get("name", "")),
		"out_of_bounds": out_of_bounds,
		"protected": guarded,
		"tags": tag_rows,
	}
	spatial.places[id] = StringName(str(row.get("place", "")))
	inventory.owners[id] = StringName(str(row.get("owner", "")))


func _row(id: StringName) -> Dictionary:
	if not _entities.has(id):
		return {}
	return _entities[id] as Dictionary


class Spatial extends WyrdSpatialAdapter:
	var places: Dictionary = {}

	func place_of(entity: StringName) -> StringName:
		if not places.has(entity):
			return &""
		return places[entity] as StringName


class Inventory extends WyrdInventoryAdapter:
	var owners: Dictionary = {}

	func count(_holder: StringName, _item_or_tag: StringName) -> int:
		return 0

	func items(_holder: StringName, _filter: StringName) -> PackedStringArray:
		return PackedStringArray()

	func owner_of(item: StringName) -> StringName:
		if not owners.has(item):
			return &""
		return owners[item] as StringName
