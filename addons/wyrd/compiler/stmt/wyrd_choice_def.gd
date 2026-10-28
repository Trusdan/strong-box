class_name WyrdChoiceDef
extends WyrdStmtSpan

## One scene choice.
##
## @experimental
## [member disabled_when] is the [code]show_disabled_when[/code] condition text.
## [code]disabled_when[/code] is a deprecated alias. [member disabled_condition]
## is that condition, compiled in storylet context. [member disabled_reason] is
## the quoted string and is not interpolated. [member check_skill] is empty
## when the choice has no skill check.
## [member tags] holds names from [code]#tag:[/code]. [code]voiced[/code] is the
## recording tag.

var line_id: String = ""
## Source file. Stamped when the pack is loaded. Not a save field.
var source_path: String = ""
var label: WyrdExprNode = null
var condition: WyrdCompiledCondition = null
var condition_text: String = ""
var target: String = ""
var effects: Array[WyrdEffectDef] = []
var disabled_when: String = ""
var disabled_condition: WyrdCompiledCondition = null
var disabled_reason: String = ""
var check_skill: String = ""
var check_args: Array = []
var check_on_fail: String = ""
var check_line: int = 0
var check_col: int = 0
var tags: PackedStringArray = PackedStringArray()
## Name from [code]#secrecy:[/code]. Empty stays visible.
var secrecy: String = ""
var scene_id: String = ""
