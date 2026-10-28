class_name StrongboxWyrdBridge
extends RefCounted

## Saves and restores the Wyrd narrative engine's state through a [StrongboxService].
##
## @experimental
## [method install] adds a save guard and a global provider, both named [code]wyrd[/code], to the
## service. Only Wyrd's stable facade API is used ([code]can_save[/code], [code]save_state[/code],
## [code]load_state[/code] and the returned load report), called by name, so this script compiles
## and the core addon works with no Wyrd in the project.

## The name of the save guard and of the global provider.
const NAME: StringName = &"wyrd"
## The save guard's reason while a dialogue scene is open.
const GUARD_REASON: String = "A dialogue scene is open"
## The node given to [method install] is not a Wyrd facade.
const E_NOT_WYRD: StringName = &"E_NOT_WYRD"

const _REQUIRED: Array[StringName] = [&"can_save", &"save_state", &"load_state"]

## The Wyrd facade (usually the [code]Wyrd[/code] autoload).
var wyrd: Node
## The report from the last restore (a [code]WyrdLoadReport[/code]), or null.
var last_report: RefCounted = null
## The result of the last restore: success with [code]{"warnings"}[/code], or [code]E_PROVIDER[/code]
## naming Wyrd's error codes. Null before the first restore.
var last_result: StrongboxResult = null


## Installs the bridge on [param service] for [param wyrd_facade]. [param priority] orders the
## restore among global providers; the default 100 restores Wyrd after a game's own providers.
## On success [member StrongboxResult.value] is the bridge.
## @experimental
static func install(service: StrongboxService, wyrd_facade: Node, priority: int = 100) -> StrongboxResult:
	if wyrd_facade == null:
		return StrongboxResult.failure(E_NOT_WYRD, "No Wyrd facade was given.")
	for method: StringName in _REQUIRED:
		if not wyrd_facade.has_method(method):
			return StrongboxResult.failure(E_NOT_WYRD, "\"%s\" has no %s(), so it is not a Wyrd facade." % [wyrd_facade.name, method])
	var bridge: StrongboxWyrdBridge = StrongboxWyrdBridge.new()
	bridge.wyrd = wyrd_facade
	# The lambdas hold the bridge, so it lives as long as the service keeps them.
	var registered: StrongboxResult = service.register_provider(NAME,
		func() -> Variant: return bridge.capture(),
		func(data: Dictionary) -> StrongboxResult: return bridge.restore(data),
		priority,
		func(data: Dictionary) -> String: return bridge.validate(data))
	if not registered.ok:
		return registered
	service.add_save_guard(NAME, func() -> String: return bridge.guard())
	return StrongboxResult.success(bridge)


## The save guard: refuses while a dialogue scene is open.
## @experimental
func guard() -> String:
	return "" if _can_save() else GUARD_REASON


## The provider's capture: Wyrd's save dictionary. Returns null while a scene is open, so the
## save fails instead of storing an empty Wyrd state (the guard normally refuses first).
## @experimental
func capture() -> Variant:
	if not _can_save():
		return null
	var data: Variant = wyrd.call(&"save_state")
	if typeof(data) != TYPE_DICTIONARY or (data as Dictionary).is_empty():
		return null
	return data


## The provider's restore: applies [param data] with Wyrd's [code]load_state[/code]. Fails with
## [code]E_PROVIDER[/code] and Wyrd's error codes when the report is not ok or has errors, and
## pushes that error. Warnings are returned in the success value. Empty data (a save made
## without the bridge) is skipped.
## @experimental
func restore(data: Dictionary) -> StrongboxResult:
	if data.is_empty():
		last_report = null
		last_result = StrongboxResult.success({"warnings": [], "skipped": true})
		return last_result
	last_report = wyrd.call(&"load_state", data) as RefCounted
	var errors: Array[String] = _codes(&"error")
	var warnings: Array[String] = _codes(&"warning")
	var failed: bool = last_report == null or not bool(last_report.get(&"ok")) or int(last_report.call(&"error_count")) > 0
	if failed:
		last_result = StrongboxResult.failure(&"E_PROVIDER", "Wyrd refused the saved state: %s" % (", ".join(errors) if not errors.is_empty() else "load_state was not ok"))
		last_result.value = {"codes": errors, "warnings": warnings}
		push_error(last_result.message)
		return last_result
	last_result = StrongboxResult.success({"warnings": warnings, "skipped": false})
	return last_result


## The provider's validator: the saved Wyrd data must be a Dictionary. Deeper checks are Wyrd's.
## @experimental
func validate(data: Variant) -> String:
	return "" if typeof(data) == TYPE_DICTIONARY else "the saved Wyrd state is not a dictionary"


func _can_save() -> bool:
	return bool(wyrd.call(&"can_save"))


## Diagnostic codes of [param severity] in [member last_report], plus the codes of its rows.
func _codes(severity: StringName) -> Array[String]:
	var codes: Array[String] = []
	if last_report == null:
		return codes
	var diagnostics: Variant = last_report.get(&"diagnostics")
	if diagnostics is Object:
		for item: Variant in (diagnostics as Object).get(&"items"):
			if item is Object and StringName((item as Object).get(&"severity")) == severity:
				codes.append(str((item as Object).get(&"code")))
	if severity == &"error" and not bool(last_report.get(&"ok")):
		for row: Variant in last_report.get(&"rows"):
			if row is Dictionary and str(row.get("code", "")).begins_with("E_") and not codes.has(str(row["code"])):
				codes.append(str(row["code"]))
	return codes
