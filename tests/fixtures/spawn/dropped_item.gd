extends Node3D

## Test fixture: an item dropped at runtime, saved by the world store as a spawned node.

var item_name: String = ""
var count: int = 1


func persist_capture() -> Dictionary:
	return {"item_name": item_name, "count": count}


func persist_restore(data: Dictionary) -> void:
	item_name = data.get("item_name", "")
	count = data.get("count", 1)
