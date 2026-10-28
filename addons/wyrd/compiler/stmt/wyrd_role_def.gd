class_name WyrdRoleDef
extends WyrdStmtSpan

## One compiled role definition.
##
## @experimental
## Built from a top-level [code]role[/code] block, or from the same field
## strings [method WyrdRoles.define] accepts. [constant CANDIDATE] is the
## entity under test inside [member eligibility_text]. Omitted eligibility
## accepts every entity. [member strategy] [code]relation[/code] and
## [code]none[/code] run at vacate. Other stored strategies do not run yet.

const CANDIDATE := "candidate"

var id: String = ""
## Old role ids from a [code]was:[/code] list, with the token position of each.
var was_ids: PackedStringArray = PackedStringArray()
var was_lines: PackedInt32Array = PackedInt32Array()
var was_cols: PackedInt32Array = PackedInt32Array()
var scope: String = "world"
var scope_id: String = ""
var eligibility_text: String = ""
var eligibility: WyrdCompiledCondition = null
var default_holder: String = ""
var visibility: String = "public"
var succession_text: String = "none"
var strategy: String = "none"
var kinds: PackedStringArray = PackedStringArray()
var succession_arg: String = ""
var vacancy: String = "hold"
var hostile_threshold: int = -1


func to_runtime_spec() -> Dictionary:
	return {
		"default_holder": StringName(default_holder),
		"eligibility": eligibility_text,
		"eligibility_cond": eligibility,
		"kinds": kinds.duplicate(),
		"scope": StringName(scope),
		"scope_id": StringName(scope_id),
		"secret": visibility == "secret",
		"strategy": StringName(strategy),
		"succession": succession_text,
		"succession_arg": StringName(succession_arg),
		"threshold": hostile_threshold,
		"vacancy": StringName(vacancy),
		"visibility": StringName(visibility),
	}


static func compile_eligibility(
	text: String,
	schema: WyrdFactSchema,
	diagnostics: WyrdDiagnostics,
	source_path: String,
	line: int,
	col: int
) -> WyrdCompiledCondition:
	var body := text.strip_edges()
	if body.is_empty():
		return null
	var facts := schema if schema != null else WyrdFactSchema.new()
	return WyrdCondition.new().compile(
		body,
		facts,
		diagnostics,
		source_path,
		line,
		col,
		WyrdCondition.CONTEXT_WAIT,
		WyrdCondition.MINUTES_PER_DAY,
		null,
		true,
		&"",
		{},
		{CANDIDATE: WyrdSignatures.T_ENTITY}
	)


static func parse_succession(text: String) -> Dictionary:
	var body := text.strip_edges()
	var empty := PackedStringArray()
	if body.is_empty() or body == "none":
		return {"arg": "", "error": "", "kinds": empty, "ok": true, "strategy": "none"}
	if body == "election" or body == "host_decides":
		return {"arg": "", "error": "", "kinds": empty, "ok": true, "strategy": body}
	if body.begins_with("relation(") and body.ends_with(")"):
		return _relation(body, empty)
	if body.begins_with("faction_assigns(") and body.ends_with(")"):
		return _faction(body, empty)
	return {
		"arg": "",
		"error": "succession \"%s\" is not a role succession" % body,
		"kinds": empty,
		"ok": false,
		"strategy": "",
	}


static func parse_scope(text: String) -> Dictionary:
	var body := text.strip_edges()
	if body == "world":
		return {"error": "", "id": "", "ok": true, "scope": "world"}
	for name in ["place", "faction"]:
		var prefix := "%s(" % name
		if body.begins_with(prefix) and body.ends_with(")"):
			var inner := body.substr(prefix.length(), body.length() - prefix.length() - 1).strip_edges()
			if is_dotted_ident(inner):
				return {"error": "", "id": inner, "ok": true, "scope": name}
			break
	return {
		"error": "scope \"%s\" is not world, place(...), or faction(...)" % body,
		"id": "",
		"ok": false,
		"scope": "",
	}


static func parse_visibility(text: String) -> Dictionary:
	var body := text.strip_edges()
	if body == "public" or body == "secret":
		return {"error": "", "ok": true, "visibility": body}
	return {"error": "visibility \"%s\" is not public or secret" % body, "ok": false, "visibility": ""}


static func parse_vacancy(text: String) -> Dictionary:
	var body := text.strip_edges()
	if body == "hold" or body == "abolish":
		return {"error": "", "ok": true, "vacancy": body}
	return {"error": "vacancy \"%s\" is not hold or abolish" % body, "ok": false, "vacancy": ""}


static func parse_holder(text: String) -> Dictionary:
	var body := text.strip_edges()
	if is_dotted_ident(body):
		return {"error": "", "holder": body, "ok": true}
	return {"error": "default_holder \"%s\" is not an entity id" % body, "holder": "", "ok": false}


static func is_dotted_ident(text: String) -> bool:
	if text.is_empty():
		return false
	for part in text.split("."):
		if not is_ident(part):
			return false
	return true


static func is_ident(text: String) -> bool:
	if text.is_empty():
		return false
	var first := text[0]
	if not ((first >= "A" and first <= "Z") or (first >= "a" and first <= "z") or first == "_"):
		return false
	for i in text.length():
		var ch := text[i]
		var ok := (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"
		if not ok:
			return false
	return true


static func _relation(body: String, empty: PackedStringArray) -> Dictionary:
	var inner := body.substr("relation(".length(), body.length() - "relation(".length() - 1).strip_edges()
	if inner.is_empty():
		return {"arg": "", "error": "relation needs a kind", "kinds": empty, "ok": false, "strategy": ""}
	var kinds := PackedStringArray()
	for part in inner.split("|"):
		var kind := part.strip_edges()
		if not is_ident(kind):
			return {
				"arg": "",
				"error": "relation kind \"%s\" is not an identifier" % kind,
				"kinds": empty,
				"ok": false,
				"strategy": "",
			}
		kinds.append(kind)
	return {"arg": "", "error": "", "kinds": kinds, "ok": true, "strategy": "relation"}


static func _faction(body: String, empty: PackedStringArray) -> Dictionary:
	var prefix := "faction_assigns("
	var inner := body.substr(prefix.length(), body.length() - prefix.length() - 1).strip_edges()
	if not is_dotted_ident(inner):
		return {"arg": "", "error": "faction_assigns needs a faction id", "kinds": empty, "ok": false, "strategy": ""}
	return {"arg": inner, "error": "", "kinds": empty, "ok": true, "strategy": "faction_assigns"}
