class_name WyrdActionAdapter
extends RefCounted

## Runs host commands and publishes the command schema.
##
## Default bodies are not implemented. [method execute] returns a failed result so a caller
## never mistakes a stub for success.

## Command and skill names the host accepts. The default body reports that it is not implemented and returns an empty schema.
func command_schema() -> WyrdCommandSchema:
	push_error("not implemented: WyrdActionAdapter.command_schema()")
	return WyrdCommandSchema.new()


## Runs one command. The default body reports that it is not implemented and returns a failed result.
func execute(cmd: WyrdCommand) -> WyrdCommandResult:
	var command_name := &""
	if cmd != null:
		command_name = cmd.name
	push_error("not implemented: WyrdActionAdapter.execute(%s)" % command_name)
	return WyrdCommandResult.failed(&"not_implemented")
