@tool
extends EditorPlugin

## Editor entry point for the optional Strongbox Wyrd bridge.
##
## @experimental
## Kept thin on purpose: the bridge is [StrongboxWyrdBridge], installed from game code with
## [method StrongboxWyrdBridge.install]. This plugin registers nothing.


func _enter_tree() -> void:
	return


func _exit_tree() -> void:
	return
