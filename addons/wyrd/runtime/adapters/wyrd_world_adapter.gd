class_name WyrdWorldAdapter
extends RefCounted

## Host view of entities. Wyrd does not walk the scene tree.
##
## Default bodies report that they are not implemented. A host, or the fake host, overrides them.

## Whether the host knows this entity. The default body reports that it is not implemented and returns false.
func exists(id: StringName) -> bool:
	push_error("not implemented: WyrdWorldAdapter.exists(%s)" % id)
	return false


## Kind of one entity. The default body reports that it is not implemented and returns an empty name.
func kind(id: StringName) -> StringName:
	push_error("not implemented: WyrdWorldAdapter.kind(%s)" % id)
	return &""


## Tags of one entity. The default body reports that it is not implemented and returns an empty list.
func tags(id: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdWorldAdapter.tags(%s)" % id)
	return PackedStringArray()


## One attribute of an entity. The default body reports that it is not implemented and returns null.
func attr(id: StringName, key: StringName) -> Variant:
	push_error("not implemented: WyrdWorldAdapter.attr(%s, %s)" % [id, key])
	return null


## Whether an entity is alive. The default body reports that it is not implemented and returns false.
func is_alive(id: StringName) -> bool:
	push_error("not implemented: WyrdWorldAdapter.is_alive(%s)" % id)
	return false


## Name the host shows for an entity. The default body reports that it is not implemented and returns an empty string.
func display_name(id: StringName) -> String:
	push_error("not implemented: WyrdWorldAdapter.display_name(%s)" % id)
	return ""


## Entity ids that belong to [param faction]. Order is not significant.
func members(faction: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdWorldAdapter.members(%s)" % faction)
	return PackedStringArray()


## Default is not protected. This is a default, not an unimplemented stub,
## so it does not [code]push_error[/code].
func is_protected(_id: StringName) -> bool:
	return false


## Default is inside every pack's bounds. This is a default, not an unimplemented
## stub, so it does not [code]push_error[/code].
func in_bounds(_id: StringName, _pack: String) -> bool:
	return true


## Groups this agent belongs to, in precedence order. The default is empty and
## does not [code]push_error[/code]: a host with no factions has no group beliefs.
## A membership change is not seen until the host emits [code]groups_changed[/code]
## or calls [method WyrdRuntime.invalidate_groups].
func groups_of(_agent: StringName) -> PackedStringArray:
	return PackedStringArray()


## Default is false. This is a default, not an unimplemented stub, so it does
## not [code]push_error[/code]. A host that returns true promises to call
## [method Wyrd.invalidate_world] whenever an entity is added or removed, or
## its kind, tags, liveness, attributes, or [method candidates] membership change.
func reports_changes() -> bool:
	return false


## Entity ids that match [param filter]. An empty kind and tag means every entity
## the host is willing to offer. Order is not significant. Role casts pass an
## empty filter. Object and item casts set [member WyrdEntityFilter.kind] and
## [member WyrdEntityFilter.tag]. Items use kind [code]item[/code]. When
## [method reports_changes] is true, Wyrd may reuse an earlier answer until the
## next [method Wyrd.invalidate_world].
func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
	var kind := ""
	var tag := ""
	if filter != null:
		kind = String(filter.kind)
		tag = String(filter.tag)
	push_error("not implemented: WyrdWorldAdapter.candidates(%s, %s)" % [kind, tag])
	return PackedStringArray()
