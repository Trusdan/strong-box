class_name WyrdSkillCheck
extends RefCounted

## One skill check handed to the host.
##
## Wyrd attaches no meaning to [member skill], [member args], or [member roll].
## The host decides pass or fail and may ignore [member roll]. [member roll] is
## in [code][0, 1)[/code].

## Skill id from the choice. Wyrd attaches no meaning to it.
var skill: StringName = &""
## Evaluated check arguments. Wyrd attaches no meaning to them.
var args: Dictionary = {}
## Scene that presented the choice.
var scene_id: String = ""
## Line id of the choice.
var choice_id: String = ""
## Unit in the half-open range from 0 to 1, drawn for this check. The host may ignore it.
var roll: float = 0.0
