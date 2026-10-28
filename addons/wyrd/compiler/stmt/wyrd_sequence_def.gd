class_name WyrdSequenceDef
extends WyrdStmtSpan

## One timed event sequence (WFR15).
##
## @experimental
## [member mode] is [code]ordered[/code] or [code]any[/code]. [member need] is how
## many matches finish it. [member total] is the cap. [member within_minutes] is
## the window in game minutes. [member reset_event] is a declared event name.
## [member reset_cond] is used when the reset is not a bare event. [member steps]
## are match-only [code]on[/code] handlers.

var id: String = ""
var mode: StringName = &"ordered"
var need: int = 0
var total: int = 0
var within_minutes: int = 0
var reset_event: String = ""
var reset_text: String = ""
var reset_cond: WyrdCompiledCondition = null
var steps: Array[WyrdOnEventDef] = []
