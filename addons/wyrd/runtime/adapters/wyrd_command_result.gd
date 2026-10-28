class_name WyrdCommandResult
extends RefCounted

## Result of a host command: ok, or failed with a reason.
##

enum Status {
	## The command succeeded. The reason is empty.
	OK,
	## The command failed. The reason names why.
	FAILED,
}

## Status value. A new result starts as FAILED.
var status: Status = Status.FAILED
## Failure reason. Empty on an ok result.
var reason: StringName = &""


## Returns a result whose status is OK and whose reason is empty.
static func ok() -> WyrdCommandResult:
	var result := WyrdCommandResult.new()
	result.status = Status.OK
	result.reason = &""
	return result


## Returns a result whose status is FAILED and whose reason is the argument.
static func failed(failure_reason: StringName) -> WyrdCommandResult:
	var result := WyrdCommandResult.new()
	result.status = Status.FAILED
	result.reason = failure_reason
	return result


## True when the status is OK.
func is_ok() -> bool:
	return status == Status.OK
