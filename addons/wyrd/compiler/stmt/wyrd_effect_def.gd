class_name WyrdEffectDef
extends WyrdStmtSpan

## One slice effect. Plain data, with type-checked expressions.
##
## @experimental
## [member kind] is [code]set[/code], [code]inc[/code], [code]record_deed[/code],
## [code]unlock_topic[/code], [code]lock_topic[/code], [code]do[/code], [code]outcome[/code],
## [code]believe[/code], [code]unbelieve[/code], [code]declare[/code],
## [code]retract[/code], [code]learn[/code], [code]forget[/code],
## [code]start_quest[/code], [code]advance[/code], [code]assign_role[/code],
## [code]vacate_role[/code], [code]adjust_baseline[/code], or [code]create_document[/code].
## [member quest] and [member stage] are the quest-flow target.
## [member role] is the role id. [member entity] is the assignee.
## [member axis], [member a], and [member b] are the baseline edge.
## The amount of [code]adjust_baseline[/code] is [member value].
## [member agent] is the belief or knowledge agent, or the group id.
## A deed with [code]reveals[/code] stores the fact on [member fact_key] and the
## claim on [member value]. [code]statement: true[/code] stays in [member args].
## [member args] holds named deed or command arguments.
## Command names are checked against [code]WyrdCommandSchema[/code] when the linker has one.

var kind: StringName = &""
var fact_key: String = ""
var agent: String = ""
var target: WyrdCompiledCondition = null
var target_text: String = ""
var value: WyrdCompiledCondition = null
var value_text: String = ""
var verb: String = ""
var command: String = ""
var topic: String = ""
var quest: String = ""
var stage: String = ""
var role: String = ""
var entity: WyrdCompiledCondition = null
var entity_text: String = ""
var axis: String = ""
var a: WyrdCompiledCondition = null
var a_text: String = ""
var b: WyrdCompiledCondition = null
var b_text: String = ""
var branch: String = ""
var outcome: String = ""
var on_fail: String = ""
var args: Array = []
## [code]create_document[/code] names the frozen document and the copy id.
var document_id: String = ""
var copy_id: String = ""
