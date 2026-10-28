extends MeshInstance3D

## Example crate dropped at runtime. The world store re-creates it from this scene.

var label: String = "crate"


func persist_capture() -> Dictionary:
	return {"label": label}


func persist_restore(data: Dictionary) -> void:
	label = data.get("label", "crate")
