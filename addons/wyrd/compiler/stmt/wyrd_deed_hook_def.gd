class_name WyrdDeedHookDef
extends WyrdStmtSpan

## One [code]on_deed[/code] hook on a template.
##
## @experimental
## [member where_cond] is a wait condition. Empty means every deed of [member verb].
## The condition may read [code]deed.actor[/code], [code]deed.target[/code],
## [code]deed.place[/code], and [code]deed.magnitude[/code]. It must not read a
## slot or param of this template.

var verb: String = ""
var where_cond: WyrdCompiledCondition = null
var where_text: String = ""
