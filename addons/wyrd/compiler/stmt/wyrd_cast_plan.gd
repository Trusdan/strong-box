class_name WyrdCastPlan
extends RefCounted

## How one cast slot or param splits its top-level [code]and[/code] clauses.
##
## @experimental
## Not exported, not saved, and not part of a golden or cross-reference dump.
## [member scan] uses the full candidate walk. Otherwise each clause is
## [code]scope[/code], [code]pin[/code], [code]local[/code], or [code]rest[/code].
## [member key] is the host filter plus the local clauses, so the same shape
## shares one cache. A second pin is stored as [code]rest[/code].

var scan: bool = false
var use_filter: bool = false
var kind: String = ""
var tag: String = ""
var scope: Array[WyrdCompiledCondition] = []
var pin: WyrdCompiledCondition = null
var local: Array[WyrdCompiledCondition] = []
var rest: Array[WyrdCompiledCondition] = []
var classes: PackedStringArray = PackedStringArray()
var key: String = ""


func filter_key() -> String:
	return WyrdCastPlan.make_filter_key(use_filter, kind, tag)


static func make_filter_key(filtered: bool, kind_name: String, tag_name: String) -> String:
	var flag := "0"
	if filtered:
		flag = "1"
	return "%s\t%s\t%s" % [flag, kind_name, tag_name]


static func make_key(
	filtered: bool,
	kind_name: String,
	tag_name: String,
	locals: Array[WyrdCompiledCondition]
) -> String:
	return "%s\t%s" % [make_filter_key(filtered, kind_name, tag_name), fingerprint(locals)]


static func fingerprint(locals: Array[WyrdCompiledCondition]) -> String:
	var parts := PackedStringArray()
	for cond in locals:
		if cond == null:
			parts.append("-")
			continue
		var ops := PackedStringArray()
		for op in cond.code:
			ops.append(str(int(op)))
		var consts := PackedStringArray()
		for item in cond.consts:
			consts.append(_token(item))
		parts.append("%s;%s" % [" ".join(ops), ",".join(consts)])
	return "|".join(parts)


static func _token(item: Variant) -> String:
	if item is bool:
		return "b:%s" % str(item)
	if item is int:
		return "i:%d" % int(item)
	if item is float:
		return "f:%s" % str(item)
	return "n:%s" % str(item)
