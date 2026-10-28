class_name WyrdAIProvider
extends RefCounted

## Host hook for an AI answer.
##
## [method request] returns at once. The answer comes later, on the main thread,
## through [method WyrdAIRequest.reply] or [method WyrdAI.deliver].
## A provider never waits. The core has no network code.
## Unimplemented methods [code]push_error[/code] and return a typed fallback.

## Provider id. The default body reports that it is not implemented and returns an empty name.
func id() -> StringName:
	push_error("not implemented: WyrdAIProvider.id()")
	return &""


## Prompt version. The default body reports that it is not implemented and returns 0.
func prompt_version() -> int:
	push_error("not implemented: WyrdAIProvider.prompt_version()")
	return 0


## Locales this provider can answer. The default body reports that it is not implemented and returns an empty list.
func locales() -> PackedStringArray:
	push_error("not implemented: WyrdAIProvider.locales()")
	return PackedStringArray()


## Starts one request and returns at once. The default body reports that it is not implemented.
func request(_req: WyrdAIRequest) -> void:
	push_error("not implemented: WyrdAIProvider.request()")


## Drops one request. The default body reports that it is not implemented.
func cancel(_request_id: int) -> void:
	push_error("not implemented: WyrdAIProvider.cancel()")
