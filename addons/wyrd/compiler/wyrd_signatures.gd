class_name WyrdSignatures
extends RefCounted

## Typed signatures for condition built-ins, plus host pure functions.
##
## @experimental
## [method register] matches the compiler side of [code]Wyrd.register_function[/code]:
## a name, positional parameters, and a return type. There is no callable here.
## [code]knows[/code] reads what an agent knows. [code]known[/code] was removed;
## compiling it reports [code]E_KNOWN_REMOVED[/code]. [code]believes[/code] is the
## truthy belief. [code]belief[/code] reads the value; its declared return is only
## the fallback for a dynamic key, and the checker uses the fact's type.
## [code]conflicted[/code] is the WFR9 group-position check. The M4 slot state
## stays [code]contested[/code]. [code]perceived[/code] returns the latest
## [code]saw[/code], [code]heard[/code], or [code]inferred[/code] mode, or null.

const T_BOOL: StringName = &"bool"
const T_INT: StringName = &"int"
const T_FLOAT: StringName = &"float"
const T_SYMBOL: StringName = &"symbol"
const T_ENTITY: StringName = &"entity"
const T_DURATION: StringName = &"duration"
const T_DISTANCE: StringName = &"distance"
const T_SET: StringName = &"set"
const T_FACT_KEY: StringName = &"fact_key"

const _BUILTINS: PackedStringArray = [
	"has(holder:entity, item_or_tag:symbol)->bool",
	"count(holder:entity, item_or_tag:symbol)->int",
	"owner_of(item:entity)->entity",
	"nearby(center:entity, radius:distance, tag:symbol)->int",
	"can_perceive(a:entity, b:entity)->bool",
	"can_reach(a:entity, place:entity)->bool",
	"alive(id:entity)->bool",
	"active_count(template:symbol)->int",
	"exists(id:entity)->bool",
	"kind(id:entity)->symbol",
	"has_tag(id:entity, tag:symbol)->bool",
	"attr(id:entity, key:symbol)->symbol",
	"display_name(id:entity)->symbol",
	"rel(a:entity, b:entity, kind:symbol)->bool",
	"path_exists(a:entity, b:entity, kinds:set, max_hops:int)->bool",
	"affinity(a:entity, b:entity)->float",
	"axis(a:entity, b:entity, name:symbol)->float",
	"disposition(a:entity, b:entity)->int",
	"reputation(subject:entity, group:entity)->float",
	"deed_score(actor:entity, verb:symbol?, against:entity?, place:entity?, within:duration?, tags:set?)->float",
	"deed_count(actor:entity, verb:symbol?, against:entity?, place:entity?, within:duration?, tags:set?)->int",
	"perceived(agent:entity, verb:symbol)->symbol",
	"role(id:entity)->symbol",
	"holder(slot_or_role:symbol)->entity",
	"has_read(reader:entity, doc:symbol)->bool",
	"filled(slot_or_role:symbol)->bool",
	"slot_state(slot:symbol)->symbol",
	"outcome(quest:symbol, branch:symbol)->symbol",
	"progress(id:symbol)->int",
	"done(id:symbol)->bool",
	"knows(agent:entity, key:fact_key)->bool",
	"believes(agent:entity, key:fact_key)->bool",
	"belief(agent:entity, key:fact_key)->symbol",
	"conflicted(agent:entity, key:fact_key)->bool",
	"held(group:entity, key:fact_key)->bool",
	"quest(id:symbol)->symbol",
	"stage(id:symbol)->symbol",
	"seen(storylet:symbol)->bool",
	"chance(p:float)->bool",
]

var _funs: Dictionary = {}


func _init() -> void:
	for spec in _BUILTINS:
		var parsed := _parse_spec(spec)
		_funs[parsed["name"]] = parsed


func register(name: StringName, params: Array, return_type: StringName) -> bool:
	if _funs.has(name):
		return false
	var rows: Array = []
	for param in params:
		var row: Dictionary = param
		rows.append({
			"name": StringName(row["name"]),
			"optional": bool(row.get("optional", false)),
			"type": StringName(row["type"]),
		})
	_funs[name] = {
		"milestone": "",
		"name": name,
		"params": rows,
		"return": return_type,
	}
	return true


func signature(name: StringName) -> Dictionary:
	if not _funs.has(name):
		return {}
	return _funs[name]


func milestone(name: StringName) -> String:
	var found := signature(name)
	if found.is_empty():
		return ""
	return String(found["milestone"])


func _parse_spec(spec: String) -> Dictionary:
	var milestone_name := ""
	var at := spec.find("@")
	if at >= 0:
		milestone_name = spec.substr(at + 1)
		spec = spec.substr(0, at)
	var arrow := spec.find("->")
	var ret := StringName(spec.substr(arrow + 2))
	var head := spec.substr(0, arrow)
	var paren := head.find("(")
	var fname := StringName(head.substr(0, paren))
	var inside := head.substr(paren + 1, head.length() - paren - 2)
	var params: Array = []
	if not inside.is_empty():
		for part in inside.split(","):
			var piece := part.strip_edges()
			var optional := piece.ends_with("?")
			if optional:
				piece = piece.substr(0, piece.length() - 1)
			var colon := piece.find(":")
			params.append({
				"name": StringName(piece.substr(0, colon)),
				"optional": optional,
				"type": StringName(piece.substr(colon + 1)),
			})
	return {"milestone": milestone_name, "name": fname, "params": params, "return": ret}
