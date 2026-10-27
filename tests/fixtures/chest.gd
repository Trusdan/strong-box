extends Node3D

## Test fixture: a chest that saves itself through persist_capture and persist_restore.

var opened: bool = false
var gold: int = 0


func persist_capture() -> Dictionary:
	return {"opened": opened, "gold": gold}


func persist_restore(data: Dictionary) -> void:
	opened = data.get("opened", false)
	gold = data.get("gold", 0)
