class_name WyrdEventDef
extends RefCounted

## One declared world event.
##
## @experimental
## [member fields] entries are [code]name[/code] and [code]type[/code]
## ([code]bool[/code], [code]int[/code], [code]float[/code], [code]symbol[/code]).
## An empty field list is an invalidate-only event: the payload must be empty.

var name: String = ""
var fields: Array[Dictionary] = []
var line: int = 1
var col: int = 1
## Concrete stored fact written to [code]world[/code] when this event is emitted.
## Empty when the event leaves no evidence.
var leaves_key: String = ""
## [code]bool[/code], [code]int[/code], [code]float[/code], or [code]symbol[/code].
var leaves_kind: StringName = &""
var leaves_value: Variant = null
## Game minutes until the evidence fact clears. [code]-1[/code] means it stays.
var decays_minutes: int = -1
var leaves_line: int = 0
var leaves_col: int = 0
## File that declared the event. Set when packs merge.
var source_path: String = ""


func field_type(field_name: String) -> StringName:
	for row in fields:
		if str(row.get("name", "")) == field_name:
			return StringName(str(row.get("type", "")))
	return &""
