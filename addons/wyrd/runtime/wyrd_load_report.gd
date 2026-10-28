class_name WyrdLoadReport
extends RefCounted

## Result of loading a content manifest. Named in the save/load design.
##
## [member ok] is false when the compiler reported any error. Warnings stay in
## [member diagnostics] and do not refuse the load. [member manifest_hash] is 0
## when the load was refused. [member rows] is empty for a content load.
## [method WyrdRuntime.load_state] adds one row per diagnostic, plus [code]kept[/code]
## rows for saved ids the pack does not declare and the runtime keeps. Each row
## has [code]kind[/code], [code]id[/code], [code]from[/code], [code]to[/code],
## [code]count[/code], and [code]code[/code]. Unused text is empty and an unused
## count is 0. Rows are sorted by kind, then id, then code.

## False when the compiler reported any error.
var ok: bool = false
## Compiler diagnostics for this load.
var diagnostics: WyrdDiagnostics
## Content hash. Zero when the load was refused.
var manifest_hash: int = 0
## Load rows. Empty for a content load.
var rows: Array = []


func _init() -> void:
	diagnostics = WyrdDiagnostics.new()


## Appends one row with kind, id, from, to, count, and code.
func add_row(kind: String, id: String, from_value: String, to_value: String, count: int, code: String) -> void:
	rows.append({
		"code": code,
		"count": count,
		"from": from_value,
		"id": id,
		"kind": kind,
		"to": to_value,
	})


## Sorts rows by kind, then id, then code.
func sort_rows() -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var kind_a := String(a.get("kind", ""))
		var kind_b := String(b.get("kind", ""))
		if kind_a != kind_b:
			return kind_a < kind_b
		var id_a := String(a.get("id", ""))
		var id_b := String(b.get("id", ""))
		if id_a != id_b:
			return id_a < id_b
		return String(a.get("code", "")) < String(b.get("code", ""))
	)


## Number of error diagnostics. Zero when diagnostics is missing.
func error_count() -> int:
	var count := 0
	if diagnostics == null:
		return 0
	for item in diagnostics.items:
		if item.severity == WyrdDiagnostic.SEVERITY_ERROR:
			count += 1
	return count
