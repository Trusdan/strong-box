extends MeshInstance3D

## Example chest: saves whether it is open, through persist_capture and persist_restore.

var opened: bool = false:
	set(value):
		opened = value
		rotation_degrees.x = -35.0 if opened else 0.0


func persist_capture() -> Dictionary:
	return {"opened": opened}


func persist_restore(data: Dictionary) -> void:
	opened = data.get("opened", false)
