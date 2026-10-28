extends MeshInstance3D

## Example lever. Saved by its StrongboxPersistComponent, which lists the "pulled" property.

var pulled: bool = false:
	set(value):
		pulled = value
		rotation_degrees.z = 40.0 if pulled else -40.0
