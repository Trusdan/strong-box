class_name WyrdAIResult
extends RefCounted

## One AI answer. This release discards it after [method WyrdAI.deliver].
##

## True when the provider produced an answer.
var ok: bool = false
## Answer text recorded with the delivery.
var text: String = ""
## Error text recorded with the delivery.
var error: String = ""
