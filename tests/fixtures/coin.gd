extends Node3D

## Test fixture: a coin pickup that can be removed for good (tombstoned).

var value: int = 1


func persist_capture() -> Dictionary:
	return {"value": value}


func persist_restore(data: Dictionary) -> void:
	value = data.get("value", 1)
