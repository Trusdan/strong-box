class_name StrongboxMigrations
extends RefCounted

## Upgrades older save bodies to the current shape through small ordered steps.
##
## @experimental
## A game sets [member current_version] (its save [code]schema_version[/code]) and registers one
## step per version with [method register]. [method run] applies the steps from a save's version
## up to [member current_version], working on a deep copy so the input is never changed.
## The addon's own [code]format_version[/code] has a separate step table, see
## [method format_migrations].

## The save is from a newer version than [member current_version].
const E_SCHEMA_TOO_NEW: StringName = &"E_SCHEMA_TOO_NEW"
## The save is older than [member min_supported_version].
const E_SCHEMA_TOO_OLD: StringName = &"E_SCHEMA_TOO_OLD"
## A step between the save's version and [member current_version] is not registered.
const E_SCHEMA_GAP: StringName = &"E_SCHEMA_GAP"
## A step returned something other than a Dictionary, or failed with a script error.
const E_MIGRATION_FAILED: StringName = &"E_MIGRATION_FAILED"
## [method register] was given a bad version, an invalid step, or a version that already has one.
const E_BAD_STEP: StringName = &"E_BAD_STEP"

## The version this game writes. Set by the game; bump it when the save shape changes.
var current_version: int = 1
## The oldest version this game still loads. Older saves are refused.
var min_supported_version: int = 1
## Registered steps: [code]{from_version: Callable}[/code].
var _steps: Dictionary = {}

## Steps for the addon's own [code]format_version[/code]. Empty for now: format 1 is the
## first. Tests may add entries here and must remove them afterwards.
static var _format_steps: Dictionary = {}


## Notices script and engine errors while a step runs. A step typed [code]-> Dictionary[/code]
## that hits a runtime error stops and returns an empty Dictionary, so the return value alone
## cannot tell a failed step from one that really emptied the body.
class _ErrorWatch extends Logger:
	var count: int = 0
	var first: String = ""

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1
		if first == "":
			first = rationale if rationale != "" else code


## Registers [param step], which upgrades a body from [param from_version] to
## [code]from_version + 1[/code]. The step receives a Dictionary and must return one.
## Registering the same version twice, a version below 1, or an invalid Callable fails.
## @experimental
func register(from_version: int, step: Callable) -> StrongboxResult:
	if from_version < 1:
		return StrongboxResult.failure(E_BAD_STEP, "Step versions start at 1, not %d." % from_version)
	if not step.is_valid():
		return StrongboxResult.failure(E_BAD_STEP, "The step for version %d is not a valid Callable." % from_version)
	if _steps.has(from_version):
		return StrongboxResult.failure(E_BAD_STEP, "A step from version %d to %d is already registered." % [from_version, from_version + 1])
	_steps[from_version] = step
	return StrongboxResult.success(from_version)


## Upgrades [param body], saved at [param from_version], to [member current_version].
## On success [member StrongboxResult.value] is [code]{"body": Dictionary, "version": int,
## "report": Array}[/code], where each report entry is [code]{"from": n, "to": n + 1}[/code]
## for a step applied. [param body] itself is never changed.
## @experimental
func run(body: Dictionary, from_version: int) -> StrongboxResult:
	if from_version > current_version:
		return StrongboxResult.failure(E_SCHEMA_TOO_NEW, "This save is from a newer game version (schema %d); this game reads up to schema %d." % [from_version, current_version])
	if from_version < min_supported_version:
		return StrongboxResult.failure(E_SCHEMA_TOO_OLD, "This save is too old (schema %d); this game reads schema %d and newer." % [from_version, min_supported_version])
	var missing: Array[int] = _missing_steps(from_version)
	if not missing.is_empty():
		return StrongboxResult.failure(E_SCHEMA_GAP, "No upgrade step is registered from schema %s." % ", ".join(missing.map(func(v: int) -> String: return "%d to %d" % [v, v + 1])))
	var working: Dictionary = body.duplicate(true)
	var report: Array[Dictionary] = []
	for version: int in range(from_version, current_version):
		var step: Callable = _steps[version]
		var watch: _ErrorWatch = _ErrorWatch.new()
		OS.add_logger(watch)
		var upgraded: Variant = step.call(working)
		OS.remove_logger(watch)
		if watch.count > 0:
			return StrongboxResult.failure(E_MIGRATION_FAILED, "The upgrade step from schema %d to %d failed with an error: %s" % [version, version + 1, watch.first])
		if typeof(upgraded) != TYPE_DICTIONARY:
			return StrongboxResult.failure(E_MIGRATION_FAILED, "The upgrade step from schema %d to %d failed or did not return a Dictionary." % [version, version + 1])
		working = upgraded
		report.append({"from": version, "to": version + 1})
	return StrongboxResult.success({"body": working, "version": current_version, "report": report})


## Checks that a step is registered for every version from [member min_supported_version]
## up to [member current_version]. On failure the message lists every missing step.
## @experimental
func validate_chain() -> StrongboxResult:
	if min_supported_version < 1 or min_supported_version > current_version:
		return StrongboxResult.failure(E_SCHEMA_GAP, "min_supported_version (%d) must be between 1 and current_version (%d)." % [min_supported_version, current_version])
	var missing: Array[int] = _missing_steps(min_supported_version)
	if not missing.is_empty():
		return StrongboxResult.failure(E_SCHEMA_GAP, "Missing upgrade steps from schema %s." % ", ".join(missing.map(func(v: int) -> String: return str(v))))
	return StrongboxResult.success(current_version)


## Returns a migrations object for the addon's own [code]format_version[/code], using the
## internal step table. Its [member current_version] is [constant StrongboxEnvelope.FORMAT_VERSION].
## @experimental
static func format_migrations() -> StrongboxMigrations:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = StrongboxEnvelope.FORMAT_VERSION
	for version: int in _format_steps:
		migrations.register(version, _format_steps[version])
	return migrations


func _missing_steps(from_version: int) -> Array[int]:
	var missing: Array[int] = []
	for version: int in range(from_version, current_version):
		if not _steps.has(version):
			missing.append(version)
	return missing
