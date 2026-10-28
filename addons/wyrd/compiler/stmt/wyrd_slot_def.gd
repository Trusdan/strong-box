class_name WyrdSlotDef
extends WyrdStmtSpan

## One quest slot.
##
## @experimental
## [member mode] is [code]live[/code], [code]locked_at[/code], or [code]cast[/code].
## [member cast_when] filters [method WyrdWorldAdapter.candidates] at quest start.
## [code]candidate[/code] is the entity under test.
## [member kind] is [code]object[/code], [code]item[/code], or empty for a role slot.
## [member cast_tag] is the top-level [code]has_tag(candidate, <symbol>)[/code] tag, or empty.

var name: String = ""
var role: String = ""
var kind: String = ""
var cast_tag: String = ""
var mode: StringName = &""
var locked_stage: String = ""
var cast_when: WyrdCompiledCondition = null
var cast_text: String = ""
## Cast-clause split. Not exported, not saved, and not dumped by goldens.
var cast_plan: WyrdCastPlan = null
