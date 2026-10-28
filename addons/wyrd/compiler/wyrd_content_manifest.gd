class_name WyrdContentManifest
extends Resource

## One content pack: the files the linker compiles together.
##
## [member pack_id] is the pack name used by [code]requires: [pack.<id>][/code].
## [member files] are [code]res://[/code] or project-relative [code].wyrd[/code] paths.
## [member language_version] is the pack's [code]language[/code] header. This slice is 1.
## Saved content hashes belong to the runtime load path, not this resource.

## Pack name used by a requires pack reference.
@export var pack_id: StringName = &""
## Project paths of the .wyrd files compiled together.
@export var files: PackedStringArray = PackedStringArray()
## Language header of the pack. This slice is 1.
@export var language_version: int = 1
