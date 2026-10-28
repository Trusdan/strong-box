class_name WyrdDeprecations
extends RefCounted

## Ids that warn once at runtime.
##
## @experimental
## One row per id. [code]kind[/code] is [code]call[/code] or [code]keyword[/code].
## [code]diagnostic[/code] is the compiler code, or empty for a call.
## [method warn_once] pushes one warning per id and adds no trace row.

const TABLE := {
	"disabled_when": {
		"kind": "keyword",
		"replacement": "show_disabled_when",
		"since": "0.6.3-m8",
		"diagnostic": "W_DISABLED_WHEN_DEPRECATED",
	},
}


## Pushes [code]Wyrd: <id> is deprecated since <since>; use <replacement>[/code] the first time [param id] is seen in [param warned].
static func warn_once(id: String, warned: Dictionary, table: Dictionary = TABLE) -> bool:
	if id.is_empty() or warned.has(id) or not table.has(id):
		return false
	var row: Dictionary = table[id]
	warned[id] = true
	push_warning("Wyrd: %s is deprecated since %s; use %s" % [id, String(row["since"]), String(row["replacement"])])
	return true


## One warning per deprecated keyword id present in [param items], not one per use.
static func warn_keywords(items: Array, warned: Dictionary, table: Dictionary = TABLE) -> void:
	var by_code := {}
	for key in table.keys():
		var row: Dictionary = table[key]
		var code := String(row.get("diagnostic", ""))
		if code.is_empty():
			continue
		by_code[code] = String(key)
	var seen := {}
	for item in items:
		var code := String(item.code)
		if not by_code.has(code) or seen.has(by_code[code]):
			continue
		var id := String(by_code[code])
		seen[id] = true
		warn_once(id, warned, table)
