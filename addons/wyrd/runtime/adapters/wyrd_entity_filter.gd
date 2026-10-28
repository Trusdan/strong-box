class_name WyrdEntityFilter
extends RefCounted

## Filter for a spatial query.
##
## [member tag] and [member kind] are empty when that field is unconstrained.
## Precision flags (precise versus coarse) are not part of this filter.
## A place's flag is [method WyrdSpatialAdapter.precision].

## Tag the query requires. Empty when the tag is unconstrained.
var tag: StringName = &""
## Kind the query requires. Empty when the kind is unconstrained.
var kind: StringName = &""


func _init(tag_name: StringName = &"", kind_name: StringName = &"") -> void:
	tag = tag_name
	kind = kind_name
