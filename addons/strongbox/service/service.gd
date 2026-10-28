class_name StrongboxService
extends Node

## One place for a game to save and load: slots, the world store, migrations and playtime.
##
## @experimental
## Use it as an autoload (for example named [code]Strongbox[/code]). The game owns scene changes:
## set [member scene_changer] to a function that loads a scene by key and returns its root once
## it is ready. [method save] returns at once; [method load] is a coroutine, so call it with
## [code]await[/code].
## Both return a [StrongboxResult]; every error code has a short message in [constant MESSAGES].
## [br][br]
## Signals fire in this order: [signal save_started] then [signal save_finished] (also on a
## failed write); [signal load_started] then either [signal load_finished] or [signal load_failed].
## A call refused at once (busy, or a guard says no) emits nothing.

## Emitted when a save begins, after the busy check and the guards.
signal save_started(slot_id: String)
## Emitted when a save ends, with its result (check [member StrongboxResult.ok]).
signal save_finished(slot_id: String, result: StrongboxResult)
## Emitted when a load begins, after the busy check.
signal load_started(slot_id: String)
## Emitted when a load succeeded.
signal load_finished(slot_id: String, result: StrongboxResult)
## Emitted when a load failed. Before the live step the running game is untouched.
signal load_failed(slot_id: String, code: StringName, message: String)

## A save or load is already running.
const E_BUSY: StringName = &"E_BUSY"
## A save guard refused the save. The reasons are in the message and in the result's value.
const E_REFUSED: StringName = &"E_REFUSED"
## There is no current scene to save, or its scene key is empty.
const E_NO_SCENE: StringName = &"E_NO_SCENE"
## The save body does not have the keys or shapes a Strongbox save needs.
const E_BAD_BODY: StringName = &"E_BAD_BODY"
## A provider's validator refused its saved data.
const E_INVALID_GLOBALS: StringName = &"E_INVALID_GLOBALS"
## [member scene_changer] is not set, or did not return the new scene root.
const E_SCENE_CHANGE: StringName = &"E_SCENE_CHANGE"

## A short English message for every code [method save] and [method load] can return.
const MESSAGES: Dictionary = {
	E_BUSY: "A save or load is already running.",
	E_REFUSED: "Saving is not allowed right now.",
	E_NO_SCENE: "There is no current scene to save.",
	E_BAD_BODY: "The save is missing data it needs.",
	E_INVALID_GLOBALS: "Part of the save was refused by the game.",
	E_SCENE_CHANGE: "The game could not change to the saved scene.",
	&"E_BAD_SLOT": "That is not a valid slot name.",
	&"E_NO_SLOT": "There is no save in that slot.",
	&"E_NO_VALID_SAVE": "The save and all its backups are damaged.",
	&"E_WRITE": "The save could not be written.",
	&"E_VERIFY": "The written save did not read back correctly.",
	&"E_RENAME": "The save could not be put in place.",
	&"E_DISK": "There is not enough disk space to save.",
	&"E_BAD_PATH": "The save folder is not allowed.",
	&"E_SCHEMA_TOO_NEW": "This save is from a newer version of the game.",
	&"E_SCHEMA_TOO_OLD": "This save is too old for this version of the game.",
	&"E_SCHEMA_GAP": "This save cannot be upgraded: an upgrade step is missing.",
	&"E_MIGRATION_FAILED": "This save could not be upgraded.",
	&"E_FORMAT_TOO_NEW": "This save is from a newer version of Strongbox.",
	&"E_SPAWN_PATH": "The save names a scene the game does not allow.",
	&"E_PROVIDER": "Part of the game state could not be saved.",
	&"E_BAD_DATA": "The save's world data is damaged.",
	&"E_DUPLICATE_ID": "Two saved objects in the scene share an id.",
	&"E_CAPTURE": "An object in the scene could not be saved.",
	&"E_SCENE_KEY": "The current scene has no scene key.",
	&"E_UNSUPPORTED_TYPE": "The game tried to save a value that cannot be saved.",
}

## Save slots on disk.
var slots: StrongboxSlots = StrongboxSlots.new()
## Scene, spawned and global state.
var world: StrongboxWorldStore = StrongboxWorldStore.new()
## Upgrades for older save bodies. Its [member StrongboxMigrations.current_version] is the
## [code]schema_version[/code] written to new saves.
var migrations: StrongboxMigrations = StrongboxMigrations.new()
## Written to each save header.
var game_version: String = ""
## [code](scene_key: String) -> Node[/code], may be a coroutine. Loads the scene for
## [param scene_key] in the game's own way and returns its root once it is ready.
var scene_changer: Callable
## [code]() -> Node[/code]: returns the current scene root. Defaults to the tree's current scene.
var current_scene_provider: Callable
## Seconds played, counted while the tree is not paused. Saved in the header and restored on load.
var playtime_s: float = 0.0

var _busy: bool = false
var _guards: Dictionary = {}
var _validators: Dictionary = {}


func _process(delta: float) -> void:
	if not get_tree().paused:
		playtime_s += delta


## Returns the short message for [param code], or an empty string for an unknown code.
## @experimental
static func message_for(code: StringName) -> String:
	return MESSAGES.get(code, "")


## Adds a save guard. [param guard] takes no arguments and returns an empty String to allow
## saving, or a reason to refuse. A guard with the same name is replaced.
## @experimental
func add_save_guard(guard_name: StringName, guard: Callable) -> void:
	_guards[guard_name] = guard


## Removes a save guard.
## @experimental
func remove_save_guard(guard_name: StringName) -> void:
	_guards.erase(guard_name)


## Asks every guard. Returns [code]{"ok": bool, "reasons": Array[String]}[/code].
## @experimental
func can_save() -> Dictionary:
	var reasons: Array[String] = []
	for guard_name: StringName in _guards:
		var reason: Variant = (_guards[guard_name] as Callable).call()
		if typeof(reason) != TYPE_STRING:
			reasons.append("%s: the guard did not return a String." % guard_name)
		elif reason != "":
			reasons.append(reason)
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Registers a global provider on [member world] (see [method StrongboxWorldStore.register_provider]),
## with an optional [param validate] [code](data: Dictionary) -> String[/code]. On load each
## validator checks its provider's data before anything live changes; a non-empty String refuses
## the load.
## @experimental
func register_provider(provider_name: StringName, capture: Callable, restore: Callable, priority: int = 0, validate: Callable = Callable()) -> StrongboxResult:
	var registered: StrongboxResult = world.register_provider(provider_name, capture, restore, priority)
	if registered.ok and validate.is_valid():
		_validators[str(provider_name)] = validate
	elif registered.ok:
		_validators.erase(str(provider_name))
	return registered


## Saves the current scene, the world store and globals to [param slot_id]. [param label] holds
## load-menu labels (see [method StrongboxSlots.write]). On failure the world store is unchanged.
## On success [member StrongboxResult.value] is the slot's metadata.
## @experimental
func save(slot_id: String, label: Dictionary = {}) -> StrongboxResult:
	if _busy:
		return _failure(E_BUSY, "")
	var allowed: Dictionary = can_save()
	if not allowed["ok"]:
		var refused: StrongboxResult = _failure(E_REFUSED, "; ".join(allowed["reasons"]))
		refused.value = {"reasons": allowed["reasons"]}
		return refused
	_busy = true
	save_started.emit(slot_id)
	var result: StrongboxResult = _save_steps(slot_id, label)
	_busy = false
	save_finished.emit(slot_id, result)
	return result


## Loads [param slot_id]: reads it (falling back to a backup), upgrades it, validates all of it,
## and only then replaces the world store, changes to the saved scene through
## [member scene_changer], restores globals and restores the scene. If anything fails before
## that, the running game is untouched. On success [member StrongboxResult.value] is
## [code]{"source", "failures", "migrated", "scene_key", "restore", "providers"}[/code];
## [code]source[/code] is [code]"main"[/code] or the backup used, [code]failures[/code] lists the
## files skipped, and [code]providers[/code] holds what successful provider restores returned.
## A provider restore that returns a failed [StrongboxResult] fails the load with that result.
## @experimental
func load(slot_id: String) -> StrongboxResult:
	if _busy:
		return _failure(E_BUSY, "")
	_busy = true
	load_started.emit(slot_id)
	var result: StrongboxResult = await _load_steps(slot_id)
	_busy = false
	if result.ok:
		load_finished.emit(slot_id, result)
	else:
		load_failed.emit(slot_id, result.code, result.message)
	return result


## Starts a new game: clears the world store (scenes, spawned nodes, tombstones, globals) and
## playtime. Providers, guards and the spawn allow-list stay. Refused while busy.
## @experimental
func new_game() -> StrongboxResult:
	if _busy:
		return _failure(E_BUSY, "")
	world.clear()
	playtime_s = 0.0
	return StrongboxResult.success(null)


func _save_steps(slot_id: String, label: Dictionary) -> StrongboxResult:
	var root: Node = _current_scene()
	if root == null or StrongboxPersist.scene_key_of(root) == "":
		return _failure(E_NO_SCENE, "")
	var key: String = StrongboxPersist.scene_key_of(root)
	# Keep what this save may change, so a failure leaves the store as it was.
	var had_entry: bool = world.scenes.has(key)
	var old_entry: Variant = world.scenes.get(key)
	var old_globals: Dictionary = world.globals
	var result: StrongboxResult = world.stash_scene(root)
	if result.ok:
		result = world.capture_globals()
	if result.ok:
		var body: Dictionary = {"world": world.to_dict(), "current_scene": key}
		result = StrongboxEnvelope.pack(body, label, migrations.current_version, game_version, playtime_s)
	if result.ok:
		result = slots.write(slot_id, result.value, label)
	if not result.ok:
		if had_entry:
			world.scenes[key] = old_entry
		else:
			world.scenes.erase(key)
		world.globals = old_globals
	return result


func _load_steps(slot_id: String) -> StrongboxResult:
	var read: StrongboxResult = slots.read(slot_id)
	if not read.ok:
		return read
	var header: Dictionary = read.value["save"]["header"]
	var upgraded: StrongboxResult = StrongboxMigrations.format_migrations().run(read.value["save"]["body"], header["format_version"])
	if upgraded.ok:
		upgraded = migrations.run(upgraded.value["body"], header["schema_version"])
	if not upgraded.ok:
		return upgraded
	var body: Dictionary = upgraded.value["body"]
	var invalid: StrongboxResult = _validate_body(body)
	if invalid != null:
		return invalid

	# The live step: from here on the running game changes.
	var key: String = body["current_scene"]
	var world_data: Dictionary = body["world"]
	var old_root: Node = _current_scene()
	var old_key: String = StrongboxPersist.scene_key_of(old_root) if old_root != null else ""
	world.clear()
	world.from_dict(world_data)
	var changed: Variant = await scene_changer.call(key)
	if not changed is Node or not is_instance_valid(changed):
		return _failure(E_SCENE_CHANGE, "scene_changer returned no scene root for \"%s\"." % key)
	# The scene that was just left may have stashed itself (for example through a
	# StrongboxSceneWatcher); put back the loaded entry for it.
	if old_key != "":
		if world_data["scenes"].has(old_key):
			world.scenes[old_key] = world_data["scenes"][old_key].duplicate(true)
		else:
			world.scenes.erase(old_key)
	var globals_result: StrongboxResult = world.restore_globals(world.globals)
	if not globals_result.ok:
		return globals_result
	var restored: StrongboxResult = world.restore_scene(changed)
	if not restored.ok:
		return restored
	playtime_s = header["playtime_s"]
	return StrongboxResult.success({
		"source": read.value["source"],
		"failures": read.value["failures"],
		"migrated": upgraded.value["report"],
		"scene_key": key,
		"restore": restored.value,
		"providers": globals_result.value["results"],
	})


## Checks everything that can be checked before the live step. Returns null when the body is fine.
func _validate_body(body: Dictionary) -> StrongboxResult:
	if typeof(body.get("world")) != TYPE_DICTIONARY or typeof(body.get("current_scene")) != TYPE_STRING or body["current_scene"] == "":
		return _failure(E_BAD_BODY, "The body needs a \"world\" dictionary and a \"current_scene\" key.")
	var probe: StrongboxWorldStore = StrongboxWorldStore.new()
	var shape: StrongboxResult = probe.from_dict(body["world"])
	if not shape.ok:
		return shape
	for scene_key: String in probe.scenes:
		for record: Dictionary in probe.scenes[scene_key]["spawned"]:
			var path_ok: StrongboxResult = world._check_spawn_path(record["scene_path"])
			if not path_ok.ok:
				return path_ok
	for provider_name: String in _validators:
		var data: Dictionary = probe.globals.get(provider_name, {})
		var reason: Variant = (_validators[provider_name] as Callable).call(data.duplicate(true))
		if typeof(reason) == TYPE_STRING and reason != "":
			return _failure(E_INVALID_GLOBALS, "%s: %s" % [provider_name, reason])
	if not scene_changer.is_valid():
		return _failure(E_SCENE_CHANGE, "Set scene_changer before loading.")
	return null


func _current_scene() -> Node:
	if current_scene_provider.is_valid():
		return current_scene_provider.call()
	return get_tree().current_scene if is_inside_tree() else null


func _failure(code: StringName, detail: String) -> StrongboxResult:
	var message: String = message_for(code)
	if detail != "":
		message = "%s %s" % [message, detail]
	return StrongboxResult.failure(code, message)
