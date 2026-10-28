class_name WyrdOnEventDef
extends WyrdStmtSpan

## A stage [code]on <event> where <cond>:[/code] handler.
##
## @experimental
## [member transitions] entries match stage transitions: [code]target[/code],
## [code]when[/code], [code]expr[/code], and a span. [code]event.<field>[/code]
## is a readonly binding in [member where_cond] and in nested effect expressions.
## Storylet [code]on[/code] is not part of this draft.

var event_name: String = ""
var where_text: String = ""
var where_cond: WyrdCompiledCondition = null
var effects: Array[WyrdEffectDef] = []
var transitions: Array = []
