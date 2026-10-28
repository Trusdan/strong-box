class_name WyrdLineDef
extends WyrdStmtSpan

## One spoken line or journal entry.
##
## @experimental
## [member kind] is [code]spoken[/code], [code]journal[/code], [code]storylet[/code],
## or [code]variant[/code].
## [member tags] holds names from [code]#tag:[/code]. [code]voiced[/code] is the
## recording tag. [member variant_slot] is the [code]holder()[/code] argument on
## this line. [member variants] are the pre-written holder lines. [member holder]
## is set on a variant line. [member scene_id] is empty on a journal entry.

var line_id: String = ""
## Source file. Stamped when the pack is loaded. Not a save field.
var source_path: String = ""
var speaker: String = ""
var kind: StringName = &"spoken"
var prose: WyrdExprNode = null
var condition: WyrdCompiledCondition = null
var condition_text: String = ""
var tags: PackedStringArray = PackedStringArray()
## Name from [code]#secrecy:[/code]. Empty inherits the storylet, or stays open.
var secrecy: String = ""
var scene_id: String = ""
var variant_slot: String = ""
var holder: String = ""
var variants: Array = []


## True when [member tags] contains [code]ai[/code].
func is_ai() -> bool:
	return tags.has("ai")


## True when the prose inserts a value or a conditional fragment.
## A [code]{holder(name)|variants}[/code] span is not variable text.
static func has_variable_text(node: WyrdExprNode) -> bool:
	if node == null:
		return false
	if node.kind == &"value" or node.kind == &"if":
		return true
	if node.kind == &"variants":
		return false
	if has_variable_text(node.b) or has_variable_text(node.c):
		return true
	for kid in node.kids:
		if has_variable_text(kid):
			return true
	return false


## True when the tree has a value, an [code]{if}[/code], or a variants span.
static func has_spans(node: WyrdExprNode) -> bool:
	if node == null:
		return false
	if node.kind == &"value" or node.kind == &"if" or node.kind == &"variants":
		return true
	if has_spans(node.b) or has_spans(node.c):
		return true
	for kid in node.kids:
		if has_spans(kid):
			return true
	return false


## [method source_of], with each literal [code]{[/code] written back as [code]{{[/code].
## A tree with no spans returns [method source_of] unchanged.
static func template_of(node: WyrdExprNode) -> String:
	if not has_spans(node):
		return source_of(node)
	return _template(node)


static func _template(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"text":
		return node.text.replace("{", "{{")
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += _template(kid)
		return built
	if node.kind == &"value":
		return "{%s}" % _payload_text(node)
	if node.kind == &"variants":
		return "{%s|variants}" % _payload_text(node)
	if node.kind == &"if":
		var then_text := _template(node.b)
		var else_text := _template(node.c)
		if else_text.is_empty():
			return "{if %s}%s{end}" % [_payload_text(node), then_text]
		return "{if %s}%s{else}%s{end}" % [_payload_text(node), then_text, else_text]
	var built := ""
	for kid in node.kids:
		built += _template(kid)
	return built


static func collect_variants(node: WyrdExprNode, into: Array) -> void:
	if node == null:
		return
	if node.kind == &"variants":
		into.append(node)
		return
	collect_variants(node.b, into)
	collect_variants(node.c, into)
	for kid in node.kids:
		collect_variants(kid, into)


## The slot or role name inside [code]holder(name)[/code], or empty.
static func holder_slot(node: WyrdExprNode) -> String:
	var text := _payload_text(node).replace(" ", "").replace("\t", "")
	if text.length() < 9 or not text.begins_with("holder(") or not text.ends_with(")"):
		return ""
	var name := text.substr(7, text.length() - 8)
	if not _plain_ident(name):
		return ""
	return name


## Source prose with interpolation spans put back, for a recording script.
static func source_of(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"text":
		return node.text
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += source_of(kid)
		return built
	if node.kind == &"value":
		return "{%s}" % _payload_text(node)
	if node.kind == &"variants":
		return "{%s|variants}" % _payload_text(node)
	if node.kind == &"if":
		var then_text := source_of(node.b)
		var else_text := source_of(node.c)
		if else_text.is_empty():
			return "{if %s}%s{end}" % [_payload_text(node), then_text]
		return "{if %s}%s{else}%s{end}" % [_payload_text(node), then_text, else_text]
	var built := ""
	for kid in node.kids:
		built += source_of(kid)
	return built


static func _payload_text(node: WyrdExprNode) -> String:
	if node != null and node.payload is WyrdCompiledCondition:
		return (node.payload as WyrdCompiledCondition).source_text.strip_edges()
	return ""


static func _plain_ident(name: String) -> bool:
	if name.is_empty():
		return false
	for i in name.length():
		var code := name.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
		if i == 0 and digit:
			return false
		if not digit and not letter:
			return false
	return true
