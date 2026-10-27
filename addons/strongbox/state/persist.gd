class_name StrongboxPersist
extends RefCounted

## The opt-in contract for nodes whose state Strongbox saves.
##
## @experimental
## A node takes part when it is in the group [constant GROUP], or when it has a
## [StrongboxPersistComponent] child (then the parent is the saved node).
## [br][br]
## A saved node either implements both methods below, or its component lists the properties to
## save in [member StrongboxPersistComponent.properties]. There is no automatic reflection over
## every property.
## [codeblock]
## func persist_capture() -> Dictionary   # returns the node's state (plain values only)
## func persist_restore(data: Dictionary) -> void
## [/codeblock]
## [br]
## A node's stable id is, in order: [member StrongboxPersistComponent.persist_id], the node's
## [constant META_ID] metadata, or its node path relative to the scene root (for example
## [code]Props/Chest01[/code]). A scene's key is the scene root's [constant META_SCENE_KEY]
## metadata, or its [member Node.scene_file_path].

## The group that opts a node in.
const GROUP: StringName = &"strongbox_persist"
## Node metadata that sets an explicit stable id.
const META_ID: StringName = &"strongbox_id"
## Scene-root metadata that overrides the scene key.
const META_SCENE_KEY: StringName = &"strongbox_scene_key"
## The method a saved node implements to return its state.
const CAPTURE_METHOD: StringName = &"persist_capture"
## The method a saved node implements to restore its state.
const RESTORE_METHOD: StringName = &"persist_restore"


## Returns the scene key for [param scene_root]: its [constant META_SCENE_KEY] metadata if set,
## otherwise its [member Node.scene_file_path]. Empty when it has neither.
## @experimental
static func scene_key_of(scene_root: Node) -> String:
	if scene_root.has_meta(META_SCENE_KEY):
		return str(scene_root.get_meta(META_SCENE_KEY))
	return scene_root.scene_file_path


## Returns the component attached to [param node], or null.
## @experimental
static func component_of(node: Node) -> StrongboxPersistComponent:
	for child: Node in node.get_children():
		if child is StrongboxPersistComponent:
			return child as StrongboxPersistComponent
	return null


## Returns the stable id of the saved [param node] inside [param scene_root].
## @experimental
static func id_of(node: Node, scene_root: Node) -> String:
	var component: StrongboxPersistComponent = component_of(node)
	if component != null and component.persist_id != &"":
		return str(component.persist_id)
	if node.has_meta(META_ID):
		return str(node.get_meta(META_ID))
	return str(scene_root.get_path_to(node))
