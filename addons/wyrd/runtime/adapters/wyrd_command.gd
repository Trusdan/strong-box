class_name WyrdCommand
extends RefCounted

## A host command the action adapter runs.
##
## [member args] is an untyped dictionary until the command schema describes each argument.

## Command name the action adapter runs.
var name: StringName = &""
## Untyped argument dictionary until a schema describes each argument.
var args: Dictionary = {}


func _init(command_name: StringName = &"", command_args: Dictionary = {}) -> void:
	name = command_name
	args = command_args
