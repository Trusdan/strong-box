class_name StrongboxPersistComponent
extends Node

## Marks its parent node as saved by Strongbox.
##
## @experimental
## Add it as a child of any node to opt that node in. If the parent does not implement
## [code]persist_capture()[/code] and [code]persist_restore()[/code], the properties named in
## [member properties] are saved and restored instead. All logic lives in
## [StrongboxRegistry]; this node only holds settings.

## An explicit stable id. When empty, the parent's node path inside the scene is used.
@export var persist_id: StringName = &""
## Parent properties to save when the parent does not implement the capture and restore methods.
@export var properties: PackedStringArray = PackedStringArray()
