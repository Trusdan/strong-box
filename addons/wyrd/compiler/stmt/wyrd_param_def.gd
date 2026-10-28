class_name WyrdParamDef
extends WyrdStmtSpan

## One template parameter. Not a quest slot.
##
## @experimental
## [member kind] is [code]item[/code], [code]place[/code], or [code]object[/code].
## [member cast_when] uses the [code]candidate[/code] binding, as a kind slot does.
## [member cast_tag] is the top-level [code]has_tag(candidate, <symbol>)[/code] tag, or empty.

var name: String = ""
var kind: String = ""
var cast_when: WyrdCompiledCondition = null
var cast_text: String = ""
var cast_tag: String = ""
## Cast-clause split. Not exported, not saved, and not dumped by goldens.
var cast_plan: WyrdCastPlan = null
