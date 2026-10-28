class_name StrongboxSceneWatcher
extends Node

## Restores its parent scene from a [StrongboxWorldStore] when the scene is ready, and stashes it
## when the scene leaves the tree.
##
## @experimental
## Add it as a direct child of a scene's root and set [member store] before the scene enters the
## tree (or before the scene leaves it, for stashing only). Errors are pushed and also sent
## through [signal restored] and [signal stashed].

## Emitted after the parent scene was restored, with the result of
## [method StrongboxWorldStore.restore_scene].
signal restored(result: StrongboxResult)
## Emitted after the parent scene was stashed, with the result of
## [method StrongboxWorldStore.stash_scene].
signal stashed(result: StrongboxResult)

## The store to restore from and stash into. Nothing happens while it is null.
var store: StrongboxWorldStore
## Restore the parent when it is ready.
@export var restore_on_ready: bool = true
## Stash the parent when it leaves the tree.
@export var stash_on_exit: bool = true


func _ready() -> void:
	var scene_root: Node = get_parent()
	if scene_root == null:
		return
	if not scene_root.tree_exiting.is_connected(_on_scene_exiting):
		scene_root.tree_exiting.connect(_on_scene_exiting)
	if not restore_on_ready:
		return
	# A child is ready before its parent, so wait for the parent's own _ready to finish.
	if scene_root.is_node_ready():
		_restore()
	else:
		scene_root.ready.connect(_restore, CONNECT_ONE_SHOT)


func _restore() -> void:
	if store == null:
		return
	var result: StrongboxResult = store.restore_scene(get_parent())
	if not result.ok:
		push_error("Strongbox could not restore \"%s\": %s" % [get_parent().name, result.message])
	restored.emit(result)


func _on_scene_exiting() -> void:
	if store == null or not stash_on_exit:
		return
	var result: StrongboxResult = store.stash_scene(get_parent())
	if not result.ok:
		push_error("Strongbox could not stash \"%s\": %s" % [get_parent().name, result.message])
	stashed.emit(result)
