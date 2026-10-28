class_name WyrdNullAIProvider
extends WyrdAIProvider

## Default provider. A fresh runtime registers it, and it answers nothing.
##
## @experimental
## [method request] and [method cancel] do nothing and do not report an error.

func id() -> StringName:
	return &"null"


func prompt_version() -> int:
	return 0


func locales() -> PackedStringArray:
	return PackedStringArray()


func request(_req: WyrdAIRequest) -> void:
	pass


func cancel(_request_id: int) -> void:
	pass
