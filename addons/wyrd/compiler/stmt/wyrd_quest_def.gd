class_name WyrdQuestDef
extends WyrdStmtSpan

## One compiled quest.
##
## @experimental
## [member title] is a quoted title and is not interpolated.
## [member requires] names packs. The linker warns when a pack is not the one being linked.
## [member on_empty] is the only quest-level slot-state default in this slice.
## [member on_missing_stage] names the top-level stage used when a save's stage is gone.

var id: String = ""
var title: String = ""
var slots: Array[WyrdSlotDef] = []
var on_empty: String = ""
var on_missing_stage: String = ""
var on_missing_stage_line: int = 1
var on_missing_stage_col: int = 1
var start_when: WyrdCompiledCondition = null
var start_text: String = ""
var requires: PackedStringArray = PackedStringArray()
var requires_line: int = 1
var requires_col: int = 1
var stages: Array[WyrdStageDef] = []
