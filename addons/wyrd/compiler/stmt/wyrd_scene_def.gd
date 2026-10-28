class_name WyrdSceneDef
extends WyrdStmtSpan

## One compiled scene.
##
## @experimental
## [member on_abort] runs if the scene aborts. [member items] keeps source order.

var id: String = ""
## Fact keys from [code]ai_context:[/code], in source order. Empty when omitted.
var ai_context: PackedStringArray = PackedStringArray()
var on_abort: Array[WyrdEffectDef] = []
var items: Array[WyrdSceneItem] = []
