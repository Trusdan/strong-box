class_name WyrdFact
extends RefCounted

## One declared fact key or key pattern.
##
## @experimental
## [member origin] is [code]stored[/code] or [code]resolved[/code].
## [member invalidate] is empty, [code]on_event[/code], [code]poll[/code], or [code]per_query[/code].
## [member recap] keeps provenance for a concrete stored fact when deeds compact.
## [member recap_marked] is true when the source wrote [code]recap:[/code], including [code]false[/code].
## Pattern segments are stored as [code]{name}[/code].

var key: String = ""
var segments: PackedStringArray = PackedStringArray()
var type_name: StringName = &""
var origin: StringName = &""
var resolver: String = ""
var invalidate: StringName = &""
var invalidate_arg: String = ""
## A stored fact whose provenance survives deed compaction.
var recap: bool = false
## True when the source wrote a [code]recap:[/code] key. [code]false[/code] still marks it.
var recap_marked: bool = false
var doc: String = ""
var line: int = 1
var col: int = 1
var valid: bool = false


func is_pattern() -> bool:
	for segment in segments:
		if segment.begins_with("{"):
			return true
	return false
