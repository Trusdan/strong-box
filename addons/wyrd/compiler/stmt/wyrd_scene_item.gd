class_name WyrdSceneItem
extends WyrdStmtSpan

## One ordered scene step: a line, choice, divert, label, or effect.
##
## @experimental
## [member kind] is [code]line[/code], [code]choice[/code], [code]divert[/code],
## [code]label[/code], or [code]effect[/code].
## [member divert_kind] is [code]label[/code], [code]end[/code], or [code]scene[/code].
## An effect step holds one effect. Inline [code]on_fail[/code] is a label divert.

var kind: StringName = &""
var line_def: WyrdLineDef = null
var choice: WyrdChoiceDef = null
var effect: WyrdEffectDef = null
var divert_kind: StringName = &""
var target: String = ""
var label: String = ""
