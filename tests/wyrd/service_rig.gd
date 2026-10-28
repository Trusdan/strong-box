extends RefCounted

## Test helper: a StrongboxService with its own save folder and a Cellar room under a holder
## node, plus a scene_changer that swaps in a fresh Cellar.

const CELLAR: PackedScene = preload("res://tests/fixtures/cellar_room.tscn")
const ROOT_PREFIX: String = "user://strongbox_wyrd_test_"


## Builds the service and holder under [param parent]; the save folder is [param save_root].
static func make(parent: Node, save_root: String) -> StrongboxService:
	var holder: Node = Node.new()
	parent.add_child(holder)
	holder.add_child(CELLAR.instantiate())
	var service: StrongboxService = StrongboxService.new()
	service.slots.store.root = save_root
	service.current_scene_provider = func() -> Node: return holder.get_child(0)
	service.scene_changer = func(_scene_key: String) -> Node:
		holder.get_child(0).free()
		var room: Node = CELLAR.instantiate()
		holder.add_child(room)
		return room
	parent.add_child(service)
	service.set_process(false)
	service.tree_exited.connect(holder.queue_free)
	return service


## Deletes [param path] and everything under it.
static func delete_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		delete_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
