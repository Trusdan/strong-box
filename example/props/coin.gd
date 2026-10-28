extends MeshInstance3D

## Example coin pickup. Taking it records a tombstone, so it stays gone.

var value: int = 1


func persist_capture() -> Dictionary:
	return {"value": value}


func persist_restore(data: Dictionary) -> void:
	value = data.get("value", 1)
