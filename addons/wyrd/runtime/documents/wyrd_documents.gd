class_name WyrdDocuments
extends RefCounted

## Readable documents: open, frozen copies, and read flags.
##
## Read flags are a set of [code](reader, doc_id)[/code] pairs. They are not
## stored facts. [code]Wyrd.facts[/code], the fact schema, the [code]W_FACT_*[/code]
## lints, the facts export, and the snapshot [code]facts[/code] section do not
## see them. [method has_read] is the query. The save bag is [code]documents[/code].
## A copy stores page and paragraph visibility, each [code]{if}[/code] as a
## boolean in walk order, and each value with [method WyrdSave.pack_claim].
## It does not store rendered strings.

## Fires after a successful open, including whether this reader is new.
signal document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool)

## @experimental
var runtime: WyrdRuntime

var _read: Dictionary = {}
var _copies: Dictionary = {}
var _text: WyrdText = WyrdText.new()


## @experimental
func clear() -> void:
	_read.clear()
	_copies.clear()


## @experimental
func has_read(reader: StringName, doc_id: StringName) -> bool:
	return _read.has(_pair(reader, doc_id))


## @experimental
func has_copy(doc_id: StringName, copy_id: String) -> bool:
	return _copies.has(_copy_key(doc_id, copy_id))


## Opens a document for a reader and returns the view. Returns null when the document, reader, mode, secrecy, or frozen copy is refused.
func open(doc_id: StringName, copy_id: String, reader: StringName) -> WyrdDocumentView:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var document := _document(doc_id)
	if document == null:
		push_error("Wyrd.documents: unknown document \"%s\"" % String(doc_id))
		return null
	if not _reader_exists(reader):
		push_error("Wyrd.documents: unknown reader \"%s\"" % String(reader))
		return null
	if runtime != null:
		runtime.trace_add("open_document", {"copy": copy_id, "doc": String(doc_id), "reader": String(reader)})
	if document.mode != "live" and document.mode != "frozen":
		_warn("periodic")
		_trace_open(doc_id, copy_id, reader, false, false, "periodic")
		return null
	if not _secrecy_ok(document.secrecy):
		_warn("secrecy")
		_trace_secrecy(document, document.line_id, document.secrecy)
		_trace_open(doc_id, copy_id, reader, false, false, "secrecy")
		return null
	var record: Dictionary = {}
	if document.mode == "frozen":
		if not has_copy(doc_id, copy_id):
			_warn("no_copy")
			_trace_open(doc_id, copy_id, reader, false, false, "no_copy")
			return null
		record = _copies[_copy_key(doc_id, copy_id)]
	var first := not has_read(reader, doc_id)
	var view := _render(document, copy_id, reader, record, first)
	if first:
		_read[_pair(reader, doc_id)] = true
		if runtime != null:
			runtime.note_has_read()
	_run_effects(document, first)
	document_read.emit(doc_id, copy_id, reader, first)
	_trace_open(doc_id, copy_id, reader, first, true, "opened")
	return view


## Stores a frozen copy. Returns false for a missing document, a live document, an empty copy id, or a non-empty params dictionary.
func create_copy(doc_id: StringName, copy_id: String, params: Dictionary = {}, from_host: bool = true) -> bool:
	var _host_gate: Variant = runtime._host_enter() if runtime != null else null
	var source := "host" if from_host else "content"
	if copy_id.is_empty():
		push_error("Wyrd.documents: copy id is empty")
		return false
	var document := _document(doc_id)
	if document == null:
		push_error("Wyrd.documents: unknown document \"%s\"" % String(doc_id))
		return false
	if not params.is_empty():
		_warn("params")
		_trace_copy(doc_id, copy_id, source, false, "params")
		return false
	if from_host and runtime != null:
		runtime.trace_add("create_copy", {"copy": copy_id, "doc": String(doc_id)})
	if document.mode != "live" and document.mode != "frozen":
		_warn("periodic")
		_trace_copy(doc_id, copy_id, source, false, "periodic")
		return false
	if document.mode == "live":
		_warn("live")
		_trace_copy(doc_id, copy_id, source, false, "live")
		return false
	var key := _copy_key(doc_id, copy_id)
	if _copies.has(key):
		_trace_copy(doc_id, copy_id, source, false, "already")
		return true
	_copies[key] = _capture(document)
	_trace_copy(doc_id, copy_id, source, true, "created")
	return true


## @experimental
func export_state() -> Dictionary:
	var reads: Array = []
	for key in _read.keys():
		var parts := String(key).split("\t", false, 1)
		reads.append({"doc": parts[1] if parts.size() > 1 else "", "reader": parts[0]})
	reads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s\t%s" % [str(a["reader"]), str(a["doc"])]
		var right := "%s\t%s" % [str(b["reader"]), str(b["doc"])]
		return left < right
	)
	var copies: Array = []
	for key in _copies.keys():
		var parts := String(key).split("\t", false, 1)
		copies.append({
			"copy": parts[1] if parts.size() > 1 else "",
			"doc": parts[0],
			"record": (_copies[key] as Dictionary).duplicate(true),
		})
	copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s\t%s" % [str(a["doc"]), str(a["copy"])]
		var right := "%s\t%s" % [str(b["doc"]), str(b["copy"])]
		return left < right
	)
	if reads.is_empty() and copies.is_empty():
		return {}
	return {"copies": copies, "read": reads}


## @experimental
func stored_doc_ids() -> PackedStringArray:
	var found := {}
	for key in _read.keys():
		var read_parts := String(key).split("\t", false, 1)
		if read_parts.size() > 1 and read_parts[1] != "":
			found[read_parts[1]] = true
	for key in _copies.keys():
		var copy_parts := String(key).split("\t", false, 1)
		if not copy_parts.is_empty() and copy_parts[0] != "":
			found[copy_parts[0]] = true
	var names: Array = found.keys()
	names.sort()
	var out := PackedStringArray()
	for id in names:
		out.append(String(id))
	return out


## @experimental
func import_state(data: Dictionary) -> void:
	clear()
	var reads: Variant = data.get("read", [])
	if reads is Array:
		for item in reads:
			if not (item is Dictionary):
				continue
			var row: Dictionary = item
			_read[_pair(StringName(str(row.get("reader", ""))), StringName(str(row.get("doc", ""))))] = true
	var copies: Variant = data.get("copies", [])
	if copies is Array:
		for item in copies:
			if not (item is Dictionary):
				continue
			var row: Dictionary = item
			var record: Dictionary = {}
			if row.get("record") is Dictionary:
				record = (row.get("record") as Dictionary).duplicate(true)
			_copies[_copy_key(StringName(str(row.get("doc", ""))), str(row.get("copy", "")))] = record
	if runtime != null and not _read.is_empty():
		runtime.note_has_read()


func _document(doc_id: StringName) -> WyrdDocumentDef:
	if runtime == null or runtime.content() == null:
		return null
	var found: Variant = runtime.content().documents.get(String(doc_id))
	return found as WyrdDocumentDef


func _reader_exists(reader: StringName) -> bool:
	if reader == &"" or runtime == null:
		return false
	var world := runtime.adapter(WyrdWorldAdapter)
	if not (world is WyrdWorldAdapter):
		return false
	return (world as WyrdWorldAdapter).exists(reader)


func _secrecy_ok(tier: String) -> bool:
	if tier.is_empty() or runtime == null:
		return true
	return runtime.secrecy_allows(tier)


func _render(document: WyrdDocumentDef, copy_id: String, reader: StringName, record: Dictionary, first: bool) -> WyrdDocumentView:
	var view := WyrdDocumentView.new()
	view.id = StringName(document.id)
	view.copy_id = copy_id
	view.reader = reader
	view.frozen = document.mode == "frozen"
	view.first_time = first
	view.tags = document.tags.duplicate()
	view.meta = document.meta.duplicate(true)
	view.title = _translate(document.title, document.line_id)
	var frozen := document.mode == "frozen"
	var page_no := 0
	for page in document.pages:
		page_no += 1
		var paragraphs: Array = page.get("paragraphs", [])
		var shown: Array = []
		var page_open := true
		if frozen and not paragraphs.is_empty():
			var head: Variant = record.get(_para_key(paragraphs[0], page_no, 1), null)
			if head is Dictionary and not bool((head as Dictionary).get("page", true)):
				page_open = false
		if not frozen:
			page_open = _flag(page.get("condition"))
		if not page_open:
			continue
		var para_no := 0
		for paragraph in paragraphs:
			para_no += 1
			var line_id := str(paragraph.get("line_id", ""))
			var key := _para_key(paragraph, page_no, para_no)
			if not _secrecy_ok(str(paragraph.get("secrecy", ""))):
				_trace_secrecy(document, line_id, str(paragraph.get("secrecy", "")))
				continue
			var text := ""
			var visible := true
			if frozen:
				var row: Variant = record.get(key, null)
				if not (row is Dictionary) or not _shape_ok(paragraph.get("prose"), row):
					_trace_stale(document, copy_id, line_id)
					visible = _flag(paragraph.get("condition"))
					text = _live_text(paragraph)
				else:
					var stored: Dictionary = row
					visible = bool(stored.get("show", false))
					if visible:
						text = _play_text(paragraph, stored)
			else:
				visible = _flag(paragraph.get("condition"))
				if visible:
					text = _live_text(paragraph)
			if not visible:
				continue
			shown.append({"id": line_id, "text": text})
		if not shown.is_empty():
			view.pages.append(shown)
	return view


func _capture(document: WyrdDocumentDef) -> Dictionary:
	var record := {}
	var page_no := 0
	for page in document.pages:
		page_no += 1
		var page_open := _flag(page.get("condition"))
		var para_no := 0
		for paragraph in page.get("paragraphs", []):
			para_no += 1
			var key := _para_key(paragraph, page_no, para_no)
			var walked := _walk_record(paragraph.get("prose") as WyrdExprNode)
			record[key] = {
				"ifs": walked["ifs"],
				"page": page_open,
				"show": _flag(paragraph.get("condition")),
				"values": walked["values"],
			}
	return record


func _shape_ok(prose: Variant, row: Dictionary) -> bool:
	var ifs: Variant = row.get("ifs", [])
	var values: Variant = row.get("values", [])
	if not (ifs is Array) or not (values is Array):
		return false
	var cursor := {"bad": false, "ifs": 0, "values": 0}
	_shape_walk(prose as WyrdExprNode, ifs, values, cursor)
	return not bool(cursor["bad"]) and int(cursor["ifs"]) == (ifs as Array).size() and int(cursor["values"]) == (values as Array).size()


func _shape_walk(node: WyrdExprNode, ifs: Array, values: Array, cursor: Dictionary) -> void:
	if node == null or bool(cursor["bad"]):
		return
	if node.kind == &"if":
		var at := int(cursor["ifs"])
		if at >= ifs.size():
			cursor["bad"] = true
			return
		cursor["ifs"] = at + 1
		_shape_walk(node.b if bool(ifs[at]) else node.c, ifs, values, cursor)
		return
	if node.kind == &"value":
		var at := int(cursor["values"])
		if at >= values.size():
			cursor["bad"] = true
			return
		cursor["values"] = at + 1
		return
	if node.kind == &"prose":
		for kid in node.kids:
			_shape_walk(kid, ifs, values, cursor)
		return
	_shape_walk(node.a, ifs, values, cursor)
	_shape_walk(node.b, ifs, values, cursor)
	_shape_walk(node.c, ifs, values, cursor)
	for kid in node.kids:
		_shape_walk(kid, ifs, values, cursor)


func _walk_record(node: WyrdExprNode) -> Dictionary:
	var ifs: Array = []
	var values: Array = []
	_record_walk(node, ifs, values)
	return {"ifs": ifs, "values": values}


func _record_walk(node: WyrdExprNode, ifs: Array, values: Array) -> void:
	if node == null:
		return
	if node.kind == &"if":
		var take: bool = _eval(node.payload) == true
		ifs.append(take)
		_record_walk(node.b if take else node.c, ifs, values)
		return
	if node.kind == &"value":
		values.append(WyrdSave.pack_claim(_eval(node.payload)))
		return
	if node.kind == &"prose":
		for kid in node.kids:
			_record_walk(kid, ifs, values)
		return
	_record_walk(node.a, ifs, values)
	_record_walk(node.b, ifs, values)
	_record_walk(node.c, ifs, values)
	for kid in node.kids:
		_record_walk(kid, ifs, values)


func _play_text(paragraph: Dictionary, row: Dictionary) -> String:
	var prose := paragraph.get("prose") as WyrdExprNode
	var line_id := str(paragraph.get("line_id", ""))
	if runtime != null:
		_text.runtime = runtime
	var prepared := _text.prepare_translation(prose, line_id)
	if not bool(prepared["active"]):
		return _translate(_play_recorded(prose, row), line_id)
	if prepared["node"] == null:
		_text.trace_result(line_id, false, str(prepared["reason"]))
		return _translate(_play_recorded(prose, row), line_id)
	var bound := _play_named(prose, prepared["node"] as WyrdExprNode, row)
	if not bool(bound["ok"]):
		_text.warn_once(line_id, "frozen_shape")
		_text.trace_result(line_id, false, "frozen_shape")
		return _translate(_play_recorded(prose, row), line_id)
	_text.trace_result(line_id, true, "translated")
	return str(bound["text"])


func _play_recorded(prose: WyrdExprNode, row: Dictionary) -> String:
	var cursor := {"ifs": 0, "values": 0}
	return _play_walk(prose, row.get("ifs", []), row.get("values", []), cursor)


func _play_named(source: WyrdExprNode, translated: WyrdExprNode, row: Dictionary) -> Dictionary:
	var if_queues := {}
	var value_queues := {}
	var cursor := {"ifs": 0, "values": 0}
	_queue_walk(source, row.get("ifs", []), row.get("values", []), cursor, if_queues, value_queues)
	var failed := {"bad": false, "collapsed": false}
	var built := _named_walk(translated, if_queues, value_queues, failed)
	if bool(failed["bad"]):
		return {"ok": false, "text": ""}
	if bool(failed["collapsed"]):
		while built.contains("  "):
			built = built.replace("  ", " ")
		built = built.strip_edges()
	return {"ok": true, "text": built}


func _queue_walk(node: WyrdExprNode, ifs: Array, values: Array, cursor: Dictionary, if_queues: Dictionary, value_queues: Dictionary) -> void:
	if node == null:
		return
	if node.kind == &"if":
		var at := int(cursor["ifs"])
		cursor["ifs"] = at + 1
		var take := bool(ifs[at]) if at < ifs.size() else false
		var name := _span_name(node)
		var queue: Array = if_queues.get(name, [])
		queue.append(take)
		if_queues[name] = queue
		_queue_walk(node.b if take else node.c, ifs, values, cursor, if_queues, value_queues)
		return
	if node.kind == &"value":
		var at := int(cursor["values"])
		cursor["values"] = at + 1
		var packed: Variant = values[at] if at < values.size() else null
		var name := _span_name(node)
		var queue: Array = value_queues.get(name, [])
		queue.append(packed)
		value_queues[name] = queue
		return
	if node.kind == &"prose":
		for kid in node.kids:
			_queue_walk(kid, ifs, values, cursor, if_queues, value_queues)
		return
	_queue_walk(node.b, ifs, values, cursor, if_queues, value_queues)
	_queue_walk(node.c, ifs, values, cursor, if_queues, value_queues)
	for kid in node.kids:
		_queue_walk(kid, ifs, values, cursor, if_queues, value_queues)


func _named_walk(node: WyrdExprNode, if_queues: Dictionary, value_queues: Dictionary, failed: Dictionary) -> String:
	if node == null or bool(failed["bad"]):
		return ""
	if node.kind == &"text":
		return node.text
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += _named_walk(kid, if_queues, value_queues, failed)
		return built
	if node.kind == &"variants":
		failed["collapsed"] = true
		return ""
	if node.kind == &"if":
		var name := _span_name(node)
		var queue: Array = if_queues.get(name, [])
		if queue.is_empty():
			failed["bad"] = true
			return ""
		var take := bool(queue.pop_front())
		if_queues[name] = queue
		return _named_walk(node.b if take else node.c, if_queues, value_queues, failed)
	if node.kind == &"value":
		var name := _span_name(node)
		var queue: Array = value_queues.get(name, [])
		if queue.is_empty():
			failed["bad"] = true
			return ""
		var packed: Variant = queue.pop_front()
		value_queues[name] = queue
		return _show(_unpack(packed), node.payload)
	return ""


func _span_name(node: WyrdExprNode) -> String:
	if node != null and node.payload is WyrdCompiledCondition:
		return (node.payload as WyrdCompiledCondition).source_text.strip_edges()
	return ""


func _play_walk(node: WyrdExprNode, ifs: Array, values: Array, cursor: Dictionary) -> String:
	if node == null:
		return ""
	if node.kind == &"text":
		return node.text
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += _play_walk(kid, ifs, values, cursor)
		return built
	if node.kind == &"if":
		var at := int(cursor["ifs"])
		cursor["ifs"] = at + 1
		var take := bool(ifs[at]) if at < ifs.size() else false
		return _play_walk(node.b if take else node.c, ifs, values, cursor)
	if node.kind == &"value":
		var at := int(cursor["values"])
		cursor["values"] = at + 1
		var packed: Variant = values[at] if at < values.size() else null
		return _show(_unpack(packed), node.payload)
	return ""


func _live_text(paragraph: Dictionary) -> String:
	if runtime != null:
		_text.runtime = runtime
	return _text.render(paragraph.get("prose") as WyrdExprNode, str(paragraph.get("line_id", "")))


func _flag(cond: Variant) -> bool:
	if cond == null or runtime == null:
		return true
	if cond is WyrdCompiledCondition:
		return runtime.eval_bool(cond)
	return true


func _eval(payload: Variant) -> Variant:
	if payload is WyrdCompiledCondition and runtime != null:
		return runtime.eval_value(payload)
	return null


func _show(value: Variant, payload: Variant) -> String:
	if value == null:
		var label := ""
		if payload is WyrdCompiledCondition:
			label = (payload as WyrdCompiledCondition).source_text.strip_edges()
		if label.is_empty():
			return "{?}"
		return "{?%s}" % label
	if value is bool:
		return "true" if value else "false"
	return str(value)


func _unpack(value: Variant) -> Variant:
	return WyrdSave.unpack_claim(value)


func _translate(message: String, line_id: String) -> String:
	if message.is_empty():
		return ""
	return String(TranslationServer.translate(message, StringName(line_id)))


func _run_effects(document: WyrdDocumentDef, first: bool) -> void:
	if runtime == null or runtime.effects == null:
		return
	var rows: Array = []
	if first:
		for effect in document.on_first_read:
			rows.append(effect)
	for effect in document.on_read:
		rows.append(effect)
	if rows.is_empty():
		return
	var saved_quest := runtime.effects.quest_id
	var saved_scene := runtime.effects.scene_id
	var saved_choice := runtime.effects.choice_id
	runtime.effects.quest_id = ""
	runtime.effects.scene_id = "document:%s" % document.id
	runtime.effects.choice_id = ""
	for row in rows:
		var effect := row as WyrdEffectDef
		if effect == null:
			continue
		runtime.trace_effect_run("document", document.id, String(effect.kind))
		runtime.effects.run_one(effect)
	runtime.effects.quest_id = saved_quest
	runtime.effects.scene_id = saved_scene
	runtime.effects.choice_id = saved_choice


func _para_key(paragraph: Dictionary, page_no: int, para_no: int) -> String:
	var line_id := str(paragraph.get("line_id", ""))
	if not line_id.is_empty():
		return line_id
	return "p%d.%d" % [page_no, para_no]


func _trace_secrecy(document: WyrdDocumentDef, line_id: String, tier: String) -> void:
	if runtime == null:
		return
	runtime.trace_secrecy(document.id, line_id, tier, runtime.secrecy_unlocked_name())


func _trace_open(doc_id: StringName, copy_id: String, reader: StringName, first: bool, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	var first_flag := "true" if first else "false"
	var ok_flag := "true" if ok else "false"
	runtime._trace_quest_line({
		"copy": copy_id,
		"document": String(doc_id),
		"first": first_flag,
		"key": String(doc_id),
		"ok": ok_flag,
		"path": copy_id,
		"reader": String(reader),
		"reason": reason,
		"who": String(reader),
	}, "document_open", "wyrd document_open document=%s copy=%s reader=%s first=%s ok=%s reason=%s" % [
		String(doc_id), copy_id, String(reader), first_flag, ok_flag, reason,
	])


func _trace_copy(doc_id: StringName, copy_id: String, source: String, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	var ok_flag := "true" if ok else "false"
	runtime._trace_quest_line({
		"copy": copy_id,
		"document": String(doc_id),
		"key": String(doc_id),
		"ok": ok_flag,
		"path": copy_id,
		"reason": reason,
		"source": source,
	}, "document_copy", "wyrd document_copy document=%s copy=%s source=%s ok=%s reason=%s" % [
		String(doc_id), copy_id, source, ok_flag, reason,
	])


func _trace_stale(document: WyrdDocumentDef, copy_id: String, line_id: String) -> void:
	if runtime == null:
		return
	runtime._trace_quest_line({
		"copy": copy_id,
		"document": document.id,
		"key": document.id,
		"line": line_id,
		"path": copy_id,
	}, "document_stale", "wyrd document_stale document=%s copy=%s line=%s" % [document.id, copy_id, line_id])


func _warn(reason: String) -> void:
	push_warning("Wyrd.documents: %s" % reason)


func _pair(reader: StringName, doc_id: StringName) -> String:
	return "%s\t%s" % [String(reader), String(doc_id)]


func _copy_key(doc_id: StringName, copy_id: String) -> String:
	return "%s\t%s" % [String(doc_id), copy_id]
