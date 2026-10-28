class_name WyrdText
extends RefCounted

## Renders compiled prose and the default journal date.
##
## @experimental
## Interpolation runs at display time. A missing value renders as
## [code]{?<expr>}[/code], not an empty string. [code]0[/code] stays [code]0[/code].
## A [code]{holder(name)|variants}[/code] span is removed here. The runtime
## picks the variant line before render, or leaves this name-free text.
## A line with no spans is walked and then passed through
## [method TranslationServer.translate] with the line id as context.
## A line with spans looks up [method WyrdLineDef.template_of] the same way.
## A translated template is compiled, and it renders when its placeholders
## match. Otherwise the source line renders, Godot logs a warning, and a
## [code]text_translate ok=false[/code] trace row explains why.
## The default date is [code]day N, HH:MM[/code] from game minutes, day 1 at
## minute 0, 1440 minutes per day. A host formatter replaces it for new text.

var runtime: WyrdRuntime
## How many times a translated template was compiled. Not saved.
var compile_count: int = 0
var _collapsed: bool = false
var _cache: Dictionary = {}


func render(node: WyrdExprNode, line_id: String) -> String:
	var prepared := prepare_translation(node, line_id)
	if not bool(prepared["active"]):
		return _render_source(node, line_id)
	if prepared["node"] == null:
		trace_result(line_id, false, str(prepared["reason"]))
		return _render_source(node, line_id)
	trace_result(line_id, true, "translated")
	return _render_tree(prepared["node"])


## Cache lookup for a translated template. Does not trace.
## [code]active[/code] is false when the line has no spans or no translation.
func prepare_translation(node: WyrdExprNode, line_id: String) -> Dictionary:
	if not WyrdLineDef.has_spans(node):
		return {"active": false, "locale": "", "node": null, "reason": ""}
	var template := WyrdLineDef.template_of(node)
	var translated := String(TranslationServer.translate(template, StringName(line_id)))
	if translated == template:
		return {"active": false, "locale": "", "node": null, "reason": ""}
	var locale := TranslationServer.get_locale()
	var key := "%s\u001f%s" % [locale, line_id]
	var entry: Dictionary = _cache.get(key, {})
	if entry.is_empty() or str(entry.get("translated", "")) != translated:
		entry = _rebuild(node, translated, line_id, locale)
		_cache[key] = entry
	return {
		"active": true,
		"locale": locale,
		"node": entry.get("node", null),
		"reason": str(entry.get("reason", "")),
	}


## One warning per cache entry and reason. The trace row is separate.
func warn_once(line_id: String, reason: String) -> void:
	var locale := TranslationServer.get_locale()
	var key := "%s\u001f%s" % [locale, line_id]
	var entry: Dictionary = _cache.get(key, {})
	var warned: Dictionary = entry.get("warned", {})
	if bool(warned.get(reason, false)):
		return
	warned[reason] = true
	entry["warned"] = warned
	_cache[key] = entry
	_warn(line_id, locale, reason)


func trace_result(line_id: String, ok: bool, reason: String) -> void:
	_trace(line_id, TranslationServer.get_locale(), ok, reason)


static func game_date(minutes: int) -> String:
	var span := maxi(minutes, 0)
	var day := int(span / 1440) + 1
	var rest := span % 1440
	return "day %d, %02d:%02d" % [day, int(rest / 60), rest % 60]


func _walk(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"text":
		return node.text
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += _walk(kid)
		return built
	if node.kind == &"variants":
		_collapsed = true
		return ""
	if node.kind == &"value":
		return _insert(_eval(node.payload), node.payload)
	if node.kind == &"if":
		if _eval(node.payload) == true:
			return _walk(node.b)
		return _walk(node.c)
	return ""


func _eval(payload: Variant) -> Variant:
	if payload is WyrdCompiledCondition and runtime != null:
		return runtime.eval_value(payload)
	return null


func _insert(value: Variant, payload: Variant) -> String:
	if value == null:
		return _missing_marker(payload)
	return _show(value)


func _missing_marker(payload: Variant) -> String:
	var label := ""
	if payload is WyrdCompiledCondition:
		label = (payload as WyrdCompiledCondition).source_text.strip_edges()
	if label.is_empty():
		return "{?}"
	return "{?%s}" % label


func _show(value: Variant) -> String:
	if value == null:
		return _missing_marker(null)
	if value is bool:
		return "true" if value else "false"
	return str(value)


func _translate(message: String, line_id: String) -> String:
	if message.is_empty():
		return ""
	return String(TranslationServer.translate(message, StringName(line_id)))


func _render_source(node: WyrdExprNode, line_id: String) -> String:
	return _translate(_render_tree(node), line_id)


func _render_tree(node: WyrdExprNode) -> String:
	_collapsed = false
	var message := _walk(node)
	if _collapsed:
		while message.contains("  "):
			message = message.replace("  ", " ")
		message = message.strip_edges()
	return message


func _rebuild(node: WyrdExprNode, translated: String, line_id: String, locale: String) -> Dictionary:
	compile_count += 1
	var diagnostics := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize_prose(translated, diagnostics)
	var schema: WyrdFactSchema = null
	if runtime != null:
		schema = runtime.content_schema()
	var compiled := WyrdInterp.new().compile_line(
		tokens,
		schema,
		diagnostics,
		"",
		WyrdCondition.CONTEXT_STORYLET,
		WyrdCondition.MINUTES_PER_DAY,
		WyrdSignatures.new()
	)
	var reason := ""
	var built: WyrdExprNode = null
	if diagnostics.has_errors():
		reason = "compile_error"
	elif not _same_placeholders(node, compiled):
		reason = "placeholder_mismatch"
	else:
		reason = "translated"
		built = compiled
	var warned := {}
	if built == null:
		warned[reason] = true
		_warn(line_id, locale, reason)
	return {"node": built, "reason": reason, "translated": translated, "warned": warned}


func _same_placeholders(source: WyrdExprNode, translated: WyrdExprNode) -> bool:
	return _placeholder_counts(source) == _placeholder_counts(translated)


func _placeholder_counts(node: WyrdExprNode) -> Dictionary:
	var counts := {}
	_count_placeholders(node, counts)
	return counts


func _count_placeholders(node: WyrdExprNode, counts: Dictionary) -> void:
	if node == null:
		return
	if node.kind == &"value" or node.kind == &"if" or node.kind == &"variants":
		var text := ""
		if node.payload is WyrdCompiledCondition:
			text = (node.payload as WyrdCompiledCondition).source_text.strip_edges()
		var key := "%s\t%s" % [node.kind, text]
		counts[key] = int(counts.get(key, 0)) + 1
	if node.kind == &"if":
		_count_placeholders(node.b, counts)
		_count_placeholders(node.c, counts)
		return
	if node.kind == &"value" or node.kind == &"variants":
		return
	for kid in node.kids:
		_count_placeholders(kid, counts)


func _warn(line_id: String, locale: String, reason: String) -> void:
	push_warning("Wyrd: translation for %s (%s) ignored: %s" % [line_id, locale, reason])


func _trace(line_id: String, locale: String, ok: bool, reason: String) -> void:
	if runtime == null or runtime.trace == null or not runtime.trace.enabled:
		return
	var fields := {
		"key": line_id,
		"ok": ok,
		"path": locale,
		"reason": reason,
	}
	if not runtime._trace_allows(fields):
		return
	runtime.trace_add("text_translate", fields)
	var flag := "true" if ok else "false"
	print("wyrd text_translate line=%s locale=%s ok=%s reason=%s" % [line_id, locale, flag, reason])
