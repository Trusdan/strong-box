extends Node3D

## Test fixture: a lever saved through its component's property whitelist ("on" and "angle").
## "label" is not listed, so it must never be saved or restored.

var on: bool = false
var angle: float = 0.0
var label: String = "not saved"
