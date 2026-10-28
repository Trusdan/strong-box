class_name WyrdCommandSchema
extends RefCounted

## Names of the commands a host accepts, and an optional skill list.
##
## Argument types land with the real schema. S0 only records command names.
## [member checks_skills] is true when [code]wyrd_commands.json[/code] has a [code]skills[/code] key.

## Command names the host accepts.
var command_names: Array[StringName] = []
## Skill names the host accepts.
var skill_names: Array[StringName] = []
## True when the command file has a skills key.
var checks_skills: bool = false


## Records a command name once.
func add_command(command_name: StringName) -> void:
	if not command_names.has(command_name):
		command_names.append(command_name)


## True when that command name was recorded.
func has_command(command_name: StringName) -> bool:
	return command_names.has(command_name)


## Records a skill name once.
func add_skill(skill_name: StringName) -> void:
	if not skill_names.has(skill_name):
		skill_names.append(skill_name)


## True when that skill name was recorded.
func has_skill(skill_name: StringName) -> bool:
	return skill_names.has(skill_name)
