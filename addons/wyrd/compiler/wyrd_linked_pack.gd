class_name WyrdLinkedPack
extends RefCounted

## Plain data for one linked content pack.
##
## @experimental
## [member units] keeps sorted file records: [code]path[/code], [code]text[/code],
## [code]hash[/code], and [code]file[/code] ([WyrdFileDef]). No callables.

var pack_id: String = ""
var language_version: int = 1
var schema: WyrdFactSchema
var units: Array = []
var topics: PackedStringArray = PackedStringArray()
var xref: WyrdFactXref
## Event name to [WyrdEventDef]. Built at link. Not a save document.
var events: Dictionary = {}
## Sorted storylet ids by scope and speaker. Built at link. Not a save field.
var storylet_index: WyrdStoryletIndex
## Resolved [code]was:[/code] tables. A kind key is present only when that kind has entries.
## [code]stage[/code] maps a quest or template id to old stage id to final id.
## [code]role[/code], [code]document[/code], and [code]verb[/code] map an old id to its final id.
## Nothing reads this at runtime yet.
var aliases: Dictionary = {}
