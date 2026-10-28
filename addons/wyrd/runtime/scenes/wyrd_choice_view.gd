class_name WyrdChoiceView
extends RefCounted

## One choice the host should show.
##
## A choice whose condition is false is omitted. [member enabled] is false when
## [code]show_disabled_when[/code] is true, and [member reason] is the quoted reason.
## [member check] is the skill id, empty when the choice has no check.
## [member check_args] is evaluated when the choice is presented. A hidden or
## disabled choice never calls the skill adapter. [member index] is the position
## in this presented list. [method WyrdSceneRunner.choose] uses that index.

## Position in the presented list. The scene runner's choose call uses it.
var index: int = 0
## Choice line id.
var id: String = ""
## Rendered choice label.
var text: String = ""
## False when the choice is shown disabled.
var enabled: bool = true
## Reason text when the choice is disabled. Empty when the choice is enabled.
var reason: String = ""
## Tags on the choice.
var tags: PackedStringArray = PackedStringArray()
## Skill id for this choice. Empty when the choice has no check.
var check: StringName = &""
## Check arguments, evaluated when the choice is presented.
var check_args: Dictionary = {}
