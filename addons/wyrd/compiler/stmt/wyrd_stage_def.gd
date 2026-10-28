class_name WyrdStageDef
extends WyrdStmtSpan

## One quest stage, or the statement body of a variant.
##
## @experimental
## [member scenes] entries are [code]id[/code], [code]with[/code], and a span.
## [member hosts] entries are [code]screen[/code], [code]fields[/code], and a span.
## [member transitions] entries are [code]target[/code], [code]when[/code], [code]expr[/code], and a span.
## [member variants] holds [WyrdVariantDef] records. The array is untyped so the
## stage and variant records can name each other.

var id: String = ""
## Old stage ids from a top-level [code]was:[/code] list, with the token position of each.
var was_ids: PackedStringArray = PackedStringArray()
var was_lines: PackedInt32Array = PackedInt32Array()
var was_cols: PackedInt32Array = PackedInt32Array()
var waits_until: WyrdCompiledCondition = null
var waits_text: String = ""
var journals: Array[WyrdLineDef] = []
var scenes: Array = []
var transitions: Array = []
var effects: Array[WyrdEffectDef] = []
var hosts: Array = []
var variants: Array = []
var handlers: Array[WyrdOnEventDef] = []
## [WyrdRegionDef] records. Untyped so a stage and a region can name each other.
var regions: Array = []
