class_name WyrdInventoryAdapter
extends RefCounted

## Host view of carried items.
##
## [param filter] on [method items] is a tag. An empty tag asks for every item that holder carries.
## [method count] takes either an item id or a tag. Default bodies are not implemented.

## How many of an item or tag a holder carries. The default body reports that it is not implemented and returns 0.
func count(holder: StringName, item_or_tag: StringName) -> int:
	push_error("not implemented: WyrdInventoryAdapter.count(%s, %s)" % [holder, item_or_tag])
	return 0


## Item ids a holder carries. The filter is a tag, and an empty tag asks for every item. The default body reports that it is not implemented and returns an empty list.
func items(holder: StringName, filter: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdInventoryAdapter.items(%s, %s)" % [holder, filter])
	return PackedStringArray()


## Holder of one item. The default body reports that it is not implemented and returns an empty name.
func owner_of(item: StringName) -> StringName:
	push_error("not implemented: WyrdInventoryAdapter.owner_of(%s)" % item)
	return &""
