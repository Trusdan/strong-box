@tool
extends EditorPlugin

## Editor entry point for Strongbox.
##
## @experimental
## Kept thin on purpose: all save logic lives in plain [RefCounted] classes so it can be
## tested headless. This plugin registers nothing yet.


func _enter_tree() -> void:
	return


func _exit_tree() -> void:
	return
