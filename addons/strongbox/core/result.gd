class_name StrongboxResult
extends RefCounted

## The outcome of a Strongbox operation: a value on success, or an error code and message.
##
## @experimental
## Strongbox reports errors through this object instead of pushing engine errors or
## crashing, so the calling game can decide what to show the player.

## [code]true[/code] when the operation succeeded.
var ok: bool = false
## The produced value on success; [code]null[/code] on failure.
var value: Variant = null
## A short machine-readable error code such as [code]&"E_CHECKSUM"[/code]; empty on success.
var code: StringName = &""
## A human-readable English description of the error; empty on success.
var message: String = ""


## Returns a successful result holding [param result_value].
## @experimental
static func success(result_value: Variant = null) -> StrongboxResult:
	var result: StrongboxResult = StrongboxResult.new()
	result.ok = true
	result.value = result_value
	return result


## Returns a failed result with [param error_code] and [param error_message].
## @experimental
static func failure(error_code: StringName, error_message: String) -> StrongboxResult:
	var result: StrongboxResult = StrongboxResult.new()
	result.ok = false
	result.code = error_code
	result.message = error_message
	return result


## Returns a one-line description, for logs.
func _to_string() -> String:
	if ok:
		return "StrongboxResult(ok)"
	return "StrongboxResult(%s: %s)" % [code, message]
