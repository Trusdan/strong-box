class_name WyrdNode
extends RefCounted

## A file, block, fact entry, or generic statement line.
##
## @experimental
## [member kind] is [code]file[/code], [code]facts[/code], [code]quest[/code], [code]scene[/code],
## [code]role[/code], [code]storylet[/code], [code]fact[/code], or [code]line[/code].
## Quest, scene, role, and storylet bodies stay a generic line tree.

var kind: StringName = &"line"
var keyword: String = ""
## The token [member keyword] was taken from. Paragraph prose needs it back.
## Parse goldens do not print it.
var lead: WyrdToken = null
var head: Array[WyrdToken] = []
var title: String = ""
var line_tag: String = ""
var tags: PackedStringArray = PackedStringArray()
## Name from [code]#secrecy:[/code]. Empty when the line has none.
var secrecy: String = ""
var children: Array[WyrdNode] = []
var entries: Array[WyrdFact] = []
var events: Array[WyrdEventDef] = []
var schema: WyrdFactSchema = null
var start_line: int = 1
var start_col: int = 1
var end_line: int = 1
var end_col: int = 1
