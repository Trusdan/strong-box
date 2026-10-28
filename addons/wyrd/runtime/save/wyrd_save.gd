class_name WyrdSave
extends RefCounted

## JSON-safe snapshot of one runtime. Schema 4 adds [code]generator[/code]
## when a generated quest instance exists. An optional [code]ai[/code] key holds
## validated cache rows when [member WyrdConfig.ai_save_cache] is true and the
## cache is not empty; an older loader ignores it, a malformed key warns
## [code]W_SAVE_AI[/code] and is ignored, and open requests are not saved. Schema 3 stores in-flight rumors,
## publish counters, and scheduler carry in [code]flight[/code] when any of
## that exists. Schema 2 fills belief bags. A schema 2 document has no
## [code]flight[/code] key and loads with empty in-flight state.
## Evidence deadlines, when any exist, ride in [code]facts.evidence[/code].
## Line-set draw state and director [code]seen[/code] / [code]last_minute[/code],
## when any of that exists, ride in [code]storylets[/code]. An unknown storylet
## id is kept in that bag and ignored. Bark speaker clocks, when any exist,
## ride in [code]bark_speakers[/code]. An unknown speaker id is kept. A missing
## [code]bark_speakers[/code] key clears those clocks and leaves storylet rows.
## Sequence progress, when any exists, rides in [code]sequences[/code]. An unknown
## sequence id is kept. A missing [code]sequences[/code] key clears that bag only.
## Unlocked topic ids, when any exist, ride in [code]topics[/code] as a sorted
## list. An unknown id is kept. A missing [code]topics[/code] key clears that set.
## Read flags and frozen copies, when any exist, ride in [code]documents[/code].
## Read flags are [code](reader, doc)[/code] pairs, not stored facts. A missing
## [code]documents[/code] key clears both lists. Unknown ids are kept and ignored.
## Quest region leaves ride inside the quest row and are omitted when empty.
## An older loader ignores those keys. The unlocked secrecy name is an ordinary
## world fact. The document has no secrecy key.
##
## @experimental
## [member migrations] is the ordered table from schema N to N+1. Step 0 fills
## [code]facts.believed[/code] and [code]facts.held[/code]. Step 1 leaves the
## document as it is. Step 2 adds an empty [code]generator[/code] object when
## the key is missing. It does not write [code]schema_version[/code] and it
## does not change [code]quests[/code]. The file's own version stays in place
## so [method _import_flight] still compares it with
## [constant FLIGHT_SINCE_SCHEMA]. A schema 2 file has no [code]flight[/code]
## key: token queues and the slice come back empty, and the dirty waits stay
## armed. A save from schema 3 on omits [code]flight[/code] only when that set
## was empty, so load clears the dirty waits. [constant FLIGHT_SINCE_SCHEMA]
## pins that rule, and a later schema bump leaves it in place.
## [code]generator[/code] holds instance counters and casts. It is omitted
## when there are no counters. A generated quest row adds [code]template[/code]
## and [code]n[/code]. A missing template keeps those rows, entries, and
## counters, and warns [code]W_SAVE_TEMPLATE[/code]. Schema 5 is refused.
## 64-bit values are lowercase hex. A scene must be closed. A manifest hash
## mismatch warns in a debug build and is silent in a release.
## After the shape check, [WyrdSaveMigrate] rewrites quest stages, role ids,
## deed verbs, and document ids through the content's alias tables. Empty
## tables leave the document unchanged. An old id whose new id is also saved
## is dropped with [code]W_SAVE_ALIAS[/code]. The load stays ok. The import
## phase does not refuse.

const SCHEMA_VERSION := 4
const FLIGHT_SINCE_SCHEMA := 3

static var migrations: Array = []


static func _static_init() -> void:
	migrations = [
		Callable(WyrdSave, &"_fill_belief_bags"),
		Callable(WyrdSave, &"_keep_document"),
		Callable(WyrdSave, &"_add_generator"),
	]


static func _fill_belief_bags(data: Dictionary) -> Dictionary:
	var facts := _dict(data.get("facts", {}))
	if not (facts.get("believed") is Dictionary):
		facts["believed"] = {}
	if not (facts.get("held") is Dictionary):
		facts["held"] = {}
	data["facts"] = facts
	return data


## Schema 2 documents have no [code]flight[/code] key. Leaving the document
## unchanged is the migration. Load treats the missing key as empty in-flight state.
static func _keep_document(data: Dictionary) -> Dictionary:
	return data


## Schema 3 documents have no [code]generator[/code] key. The empty object is
## the migration. This step does not write [code]schema_version[/code].
static func _add_generator(data: Dictionary) -> Dictionary:
	if not data.has("generator"):
		data["generator"] = {}
	return data


## A [StringName] is [code]{"t": "symbol", "v": "..."}[/code].
## A float is [code]{"t": "float", "v": n}[/code] so [code]1.0[/code] stays a float.
## Bool, int, string, and null stay JSON values.
static func pack_claim(value: Variant) -> Variant:
	if value is StringName:
		return {"t": "symbol", "v": String(value)}
	if typeof(value) == TYPE_FLOAT:
		return {"t": "float", "v": value}
	return value


## Inverse of [method pack_claim]. A whole JSON number that was not tagged
## comes back as an int. A tagged float stays a float.
static func unpack_claim(value: Variant) -> Variant:
	if value is Dictionary:
		var row: Dictionary = value
		var tag := str(row.get("t", ""))
		if tag == "symbol":
			return StringName(str(row.get("v", "")))
		if tag == "float":
			return float(row.get("v", 0.0))
	if typeof(value) == TYPE_FLOAT and value == floor(value):
		if value >= -2147483648.0 and value <= 2147483647.0:
			return int(value)
	return value


static func capture(runtime: WyrdRuntime) -> Dictionary:
	var content := runtime.content()
	var packs: Array = []
	var language_version := 1
	if content != null:
		language_version = content.language_version
		packs.append({
			"hash": WyrdRng.format_u64(content.manifest_hash),
			"id": content.pack_id,
		})
	var data := {
		"content": {"packs": packs},
		"deeds": runtime.deeds.export_state(),
		"facts": runtime.facts.export_state(),
		"language_version": language_version,
		"minutes": runtime.play_minutes(),
		"provenance": runtime.effects.export_state(),
		"quests": runtime.quests.export_state(),
		"rng": runtime.export_rng(),
		"roles": runtime.roles.export_state(),
		"schema_version": SCHEMA_VERSION,
		"seed": WyrdRng.format_u64(runtime.game_seed()),
		"social": runtime.social.export_state(),
	}
	if runtime.storylets != null:
		var drawn := runtime.storylets.export_state()
		if not drawn.is_empty():
			data["storylets"] = drawn
		var speakers := runtime.storylets.export_speakers()
		if not speakers.is_empty():
			data["bark_speakers"] = speakers
	if runtime.sequences != null:
		var sequences := runtime.sequences.export_state()
		if not sequences.is_empty():
			data["sequences"] = sequences
	if runtime.topics != null:
		var topics := runtime.topics.export_state()
		if not topics.is_empty():
			var names: Array = []
			for topic in topics:
				names.append(String(topic))
			data["topics"] = names
	if runtime.documents != null:
		var documents := runtime.documents.export_state()
		if not documents.is_empty():
			data["documents"] = documents
	var flight := _capture_flight(runtime)
	if not flight.is_empty():
		data["flight"] = flight
	var generator := runtime.quests.export_generator()
	if not generator.is_empty():
		data["generator"] = generator
	if runtime.ai != null and runtime.config() != null and runtime.config().ai_save_cache and runtime.ai.cache_size() > 0:
		data["ai"] = runtime.ai.export_cache()
	return data


## Reads a deep copy. Runs migrations, alias rewrite, missing-stage moves, and
## every refusal on that copy. On success the dictionary holds [code]doc[/code],
## [code]streams[/code], and [code]report[/code]. A refusal holds [code]report[/code]
## only. The runtime is not changed.
static func check(runtime: WyrdRuntime, data: Dictionary) -> Dictionary:
	var report := WyrdLoadReport.new()
	var content := runtime.content()
	if content == null:
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "load content before loading a save", "content")
	# An older schema is copied in full before migrations rewrite it. A current
	# schema shares deed-row dictionaries: later steps only read them, or copy
	# the document before a rewrite, and the import keeps no row dictionary.
	var share_rows := _whole(data.get("schema_version", -1), -1) == SCHEMA_VERSION
	var working := _copy_for_check(data, share_rows)
	var version := _whole(working.get("schema_version", -1), -1)
	if version < 1:
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "save schema_version is missing", "schema_version")
	var guard := 0
	while version < SCHEMA_VERSION and guard < 8:
		if version - 1 >= migrations.size() or not _callable(migrations[version - 1]):
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "no migration from save schema %d" % version, "schema_version")
		var step: Callable = migrations[version - 1]
		var next: Variant = step.call(working)
		if not (next is Dictionary):
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "migration %d did not return a save" % version, "schema_version")
		working = next
		version += 1
		guard += 1
	if version != SCHEMA_VERSION:
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "no migration from save schema %d" % version, "schema_version")
	var seed_value: Variant = working.get("seed", "")
	if not (seed_value is String) and not (seed_value is StringName):
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "save field seed must be a string", "seed")
	var seed_row := WyrdRng.parse_u64(String(seed_value))
	if seed_row.is_empty():
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "save seed is not 16 hex digits", "seed")
	var packs: Array = []
	var listed: Variant = _dict(working.get("content", {})).get("packs", [])
	if listed is Array:
		packs = listed
	if not packs.is_empty() and packs[0] is Dictionary:
		var hash_value: Variant = (packs[0] as Dictionary).get("hash", "")
		if not (hash_value is String) and not (hash_value is StringName):
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "save field content.packs.0.hash must be a string", "content.packs.0.hash")
		var hash_row := WyrdRng.parse_u64(String(hash_value))
		if hash_row.is_empty():
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "content hash is not 16 hex digits", "content.packs.0.hash")
		if int(hash_row["n"]) != content.manifest_hash and OS.is_debug_build():
			report.diagnostics.add(
				WyrdDiagnostic.W_SAVE_MANIFEST,
				"content manifest hash differs from the save",
				"",
				1,
				1,
				WyrdDiagnostic.SEVERITY_WARNING
			)
			report.add_row("manifest", "", WyrdRng.format_u64(int(hash_row["n"])), WyrdRng.format_u64(content.manifest_hash), 0, "W_SAVE_MANIFEST")
	var built := {}
	var rng_value: Variant = working.get("rng", {})
	if working.has("rng") and not (rng_value is Dictionary):
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "save field rng must be a dictionary", "rng")
	var rng_data := _dict(rng_value)
	var stream_names: Array = rng_data.keys()
	stream_names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for stream_name in stream_names:
		var stream_id := "rng.%s" % String(stream_name)
		if not (rng_data[stream_name] is Dictionary):
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "RNG stream \"%s\" is not a state" % String(stream_name), stream_id)
		var restored := WyrdRng.from_state(rng_data[stream_name])
		if restored == null:
			return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, "RNG stream \"%s\" is not a state" % String(stream_name), stream_id)
		built[String(stream_name)] = restored
	var issues := check_shape(working, runtime.facts)
	if not issues.is_empty():
		var message := String(issues[0])
		return _refused(report, WyrdDiagnostic.E_SAVE_VERSION, message, _field_path(message))
	var migrated := WyrdSaveMigrate.apply_aliases(working, content.aliases)
	working = migrated["doc"]
	var item: Dictionary = {}
	var body: Dictionary = {}
	for note in migrated["diagnostics"]:
		item = note
		report.diagnostics.add(
			StringName(String(item.get("code", ""))),
			String(item.get("message", "")),
			"",
			1,
			1,
			WyrdDiagnostic.SEVERITY_WARNING
		)
	for added in migrated["rows"]:
		body = added
		report.add_row(
			String(body.get("kind", "")),
			String(body.get("id", "")),
			String(body.get("from", "")),
			String(body.get("to", "")),
			int(body.get("count", 0)),
			String(body.get("code", ""))
		)
	var resolved := WyrdSaveMigrate.resolve_stages(working, content)
	working = resolved["doc"]
	for note in resolved["diagnostics"]:
		item = note
		report.diagnostics.add(
			StringName(String(item.get("code", ""))),
			String(item.get("message", "")),
			"",
			1,
			1,
			WyrdDiagnostic.SEVERITY_WARNING
		)
	for added in resolved["rows"]:
		body = added
		report.add_row(
			String(body.get("kind", "")),
			String(body.get("id", "")),
			String(body.get("from", "")),
			String(body.get("to", "")),
			int(body.get("count", 0)),
			String(body.get("code", ""))
		)
	return {"doc": working, "report": report, "streams": built}


## Imports a document that [method check] already accepted. Does not refuse.
static func import_checked(runtime: WyrdRuntime, doc: Dictionary, streams: Dictionary, report: WyrdLoadReport) -> void:
	var content := runtime.content()
	var seed_row := WyrdRng.parse_u64(String(doc.get("seed", "")))
	var seed_n := 0
	if not seed_row.is_empty():
		seed_n = int(seed_row["n"])
	runtime.restore_clock(seed_n, _whole(doc.get("minutes", 0), 0))
	runtime.facts.import_state(_dict(doc.get("facts", {})))
	runtime.deeds.import_state(_dict(doc.get("deeds", {})))
	runtime.social.import_state(_dict(doc.get("social", {})))
	runtime.roles.import_state(_dict(doc.get("roles", {})))
	var generator := {}
	if doc.get("generator") is Dictionary:
		generator = doc.get("generator")
	runtime.quests.import_generator(generator, report)
	runtime.quests.import_state(_dict(doc.get("quests", {})))
	runtime.effects.import_state(_dict(doc.get("provenance", {})))
	runtime.install_rng(streams)
	if runtime.storylets != null:
		if doc.has("storylets"):
			runtime.storylets.import_state(_dict(doc.get("storylets", {})))
		else:
			runtime.storylets.clear_draws()
		if doc.has("bark_speakers"):
			runtime.storylets.import_speakers(_dict(doc.get("bark_speakers", {})))
		else:
			runtime.storylets.clear_speakers()
	if runtime.sequences != null:
		if doc.has("sequences"):
			runtime.sequences.import_state(_dict(doc.get("sequences", {})))
		else:
			runtime.sequences.clear()
	if runtime.topics != null:
		if doc.has("topics") and doc.get("topics") is Array:
			runtime.topics.import_state(doc.get("topics"))
		else:
			runtime.topics.clear()
	if runtime.documents != null:
		if doc.has("documents") and doc.get("documents") is Dictionary:
			runtime.documents.import_state(doc.get("documents"))
		else:
			runtime.documents.clear()
	if runtime.ai != null:
		runtime.ai.import_cache(doc.get("ai"), doc.has("ai"), report)
	_import_flight(runtime, doc, report)
	_note_kept(runtime, report)
	report.ok = true
	if content != null:
		report.manifest_hash = content.manifest_hash


## Check, then import. [method WyrdRuntime.load_state] calls the two steps itself
## so a refusal happens before the runtime drops its caches.
static func apply(runtime: WyrdRuntime, data: Dictionary) -> WyrdLoadReport:
	var prepared := check(runtime, data)
	var report: WyrdLoadReport = prepared["report"]
	if prepared.has("doc"):
		import_checked(runtime, prepared["doc"], prepared["streams"], report)
	report.sort_rows()
	return report


## Present keys whose type the importers do not accept. A missing key is not an issue.
## A whole-number float counts as an int. [code]ai[/code] is not checked.
static func check_shape(doc: Dictionary, facts: WyrdFactStore = null) -> Array:
	var issue := _shape_node("", doc, _root_spec(), facts)
	if issue.is_empty():
		return []
	return [String(issue.get("message", ""))]


static func _refused(report: WyrdLoadReport, code: StringName, message: String, id: String) -> Dictionary:
	report.diagnostics.add(code, message, "", 1, 1)
	report.add_row("refused", id, "", "", 0, String(code))
	return {"report": report}


static func _field_path(message: String) -> String:
	var prefix := "save field "
	var marker := " must be "
	if not message.begins_with(prefix):
		return "save"
	var at := message.find(marker)
	if at < prefix.length():
		return "save"
	return message.substr(prefix.length(), at - prefix.length())


static func _note_kept(runtime: WyrdRuntime, report: WyrdLoadReport) -> void:
	var content := runtime.content()
	if content == null:
		return
	if runtime.storylets != null:
		for id in runtime.storylets.ignored_ids():
			report.add_row("kept", String(id), "storylet", "", 1, "")
	if runtime.sequences != null:
		for id in runtime.sequences.stored_ids():
			if not content.sequences.has(String(id)):
				report.add_row("kept", String(id), "sequence", "", 1, "")
	if runtime.topics != null:
		for id in runtime.topics.export_state():
			if not content.topic_ids.has(String(id)):
				report.add_row("kept", String(id), "topic", "", 1, "")
	if runtime.documents != null:
		for id in runtime.documents.stored_doc_ids():
			if not content.documents.has(String(id)):
				report.add_row("kept", String(id), "document", "", 1, "")
	if runtime.quests != null:
		for id in runtime.quests.kept_quest_ids():
			report.add_row("kept", String(id), "quest", "", 1, "")
	if runtime.roles != null:
		for id in runtime.roles.present_role_ids():
			var role_id := String(id)
			if content.roles.has(role_id):
				continue
			if runtime.roles.is_host_defined(role_id):
				continue
			report.add_row("kept", role_id, "role", "", 1, "")


static func _root_spec() -> Dictionary:
	return {
		"kind": "dict",
		"fields": {
			"bark_speakers": {"kind": "dict", "wild": {"kind": "loose_dict", "fields": {"cooldown": "int", "last_minute": "int"}}},
			"content": {"kind": "dict", "fields": {"packs": {"kind": "array", "of": {"kind": "dict", "fields": {"hash": "string", "id": "string"}}}}},
			"deeds": {"kind": "dict", "fields": {"next": "int", "rows": {"kind": "array", "of": _deed_row_spec()}}},
			"documents": {"kind": "dict", "fields": {
				"copies": {"kind": "array", "of": {"kind": "dict", "fields": {"copy": "string", "doc": "string", "record": "skip"}}},
				"read": {"kind": "array", "of": {"kind": "dict", "fields": {"doc": "string", "reader": "string"}}},
			}},
			"facts": {"kind": "dict", "fields": {
				"believed": {"kind": "dict", "wild": {"kind": "fact_map"}},
				"evidence": {"kind": "array", "of": "evidence"},
				"held": {"kind": "dict", "wild": {"kind": "fact_map"}},
				"known": {"kind": "dict", "wild": {"kind": "fact_map"}},
				"world": {"kind": "fact_map"},
			}},
			"flight": _flight_spec(),
			"generator": _generator_spec(),
			"language_version": "int",
			"minutes": "int",
			"provenance": {"kind": "dict", "wild": {"kind": "dict", "fields": {"choice": "string", "scene": "string", "time": "int"}}},
			"quests": {"kind": "dict", "wild": _quest_row_spec()},
			"rng": {"kind": "dict", "wild": {"kind": "dict", "wild": "skip"}},
			"roles": _roles_spec(),
			"schema_version": "int",
			"seed": "string",
			"sequences": {"kind": "dict", "wild": {"kind": "loose_dict", "fields": {"count": "int", "done": "bool", "matched": {"kind": "array", "of": "int"}, "started": "int"}}},
			"social": {"kind": "dict", "fields": {
				"baselines": {"kind": "array", "of": {"kind": "dict", "fields": {"axis": "string", "source": "string", "target": "string", "value": "number"}}},
				"kinds": {"kind": "array", "of": {"kind": "dict", "fields": {"kind": "string", "source": "string", "target": "string"}}},
			}},
			"storylets": {"kind": "dict", "wild": {"kind": "dict", "fields": {"cursor": "int", "cycle": "int", "last_minute": "int", "order": {"kind": "array", "of": "string"}, "seen": "int"}}},
			"topics": {"kind": "array", "of": "string"},
		},
	}


static func _quest_row_spec() -> Dictionary:
	return {
		"kind": "dict",
		"fields": {
			"entered": "bool",
			"held_empty": "bool",
			"host_fields": {"kind": "array", "of": "string"},
			"host_returns": {"kind": "dict", "wild": "skip"},
			"host_screen": "string",
			"journal": {"kind": "array", "of": {"kind": "dict", "fields": {"date": "string", "id": "string", "minutes": "int", "text": "string"}}},
			"n": "int",
			"offered": "string",
			"outcomes": {"kind": "dict", "wild": "string"},
			"regions": "region_map",
			"scene_done": "bool",
			"slots": {"kind": "array", "of": "string"},
			"stage": "string",
			"status": "string",
			"step_at": "int",
			"template": "string",
			"trail": {"kind": "array", "of": "string"},
			"variant": "string",
			"waiting": "string",
		},
	}


static func _region_row_spec() -> Dictionary:
	return {
		"kind": "dict",
		"fields": {
			"entered": "bool",
			"regions": "region_map",
			"stage": "string",
			"step_at": "int",
		},
	}


static func _deed_row_spec() -> Dictionary:
	return {
		"kind": "dict",
		"fields": {
			"actor": "string",
			"believers": {"kind": "array", "of": {"kind": "dict", "fields": {"t": "int", "who": "string"}}},
			"id": "int",
			"magnitude": "number",
			"memorable": "bool",
			"perception": {"kind": "array", "of": "string"},
			"place": "string",
			"t": "int",
			"tags": {"kind": "array", "of": "string"},
			"target": "string",
			"verb": "string",
			"visibility": "string",
			"witnesses": {"kind": "array", "of": "string"},
		},
	}


static func _roles_spec() -> Dictionary:
	var binding := {
		"kind": "dict",
		"fields": {
			"history": {"kind": "array", "of": {"kind": "dict", "fields": {"holder": "string", "reason": "string", "since": "int", "status": "string", "until": "int"}}},
			"holder": "string",
			"since": "int",
			"status": "string",
		},
	}
	var definition := {
		"kind": "dict",
		"fields": {
			"default_holder": "string",
			"eligibility": "string",
			"kinds": {"kind": "array", "of": "string"},
			"scope": "string",
			"scope_id": "string",
			"secret": "bool",
			"strategy": "string",
			"succession": "string",
			"succession_arg": "string",
			"threshold": "int",
			"vacancy": "string",
			"visibility": "string",
		},
	}
	var cast := {"kind": "dict", "fields": {"holder": "string", "owner": "string", "status": "string"}}
	return {
		"kind": "dict",
		"fields": {
			"abolished": {"kind": "array", "of": "string"},
			"bindings": {"kind": "dict", "wild": binding},
			"defs": {"kind": "dict", "wild": definition},
			"frozen": {"kind": "dict", "wild": {"kind": "dict", "wild": cast}},
			"pending": {"kind": "dict", "wild": {"kind": "dict", "fields": {"departed": "string", "since": "int"}}},
			"told": {"kind": "dict", "wild": {"kind": "array", "of": "string"}},
		},
	}


static func _generator_spec() -> Dictionary:
	var cast := {"kind": "dict", "fields": {"holder": "string", "owner": "string", "status": "string"}}
	return {
		"kind": "dict",
		"fields": {
			"counters": {"kind": "dict", "wild": "int"},
			"instances": {"kind": "dict", "wild": {"kind": "dict", "fields": {
				"casts": {"kind": "dict", "wild": cast},
				"created": "int",
				"params": {"kind": "dict", "wild": "param"},
			}}},
		},
	}


static func _flight_spec() -> Dictionary:
	var job := {
		"kind": "dict",
		"fields": {
			"chance": "number",
			"deed": "string",
			"key": "string",
			"kinds": {"kind": "array", "of": "string"},
			"max_hops": "int",
			"policy": "string",
			"value": "skip",
			"verb": "string",
		},
	}
	var reach := {
		"kind": "dict",
		"fields": {
			"born": "int",
			"deed": "string",
			"key": "string",
			"level": "int",
			"pending": "int",
			"place": "string",
			"policy": "string",
			"value": "skip",
			"verb": "string",
		},
	}
	var people := {"kind": "dict", "fields": {"deed": "string", "who": {"kind": "array", "of": "string"}}}
	var pair := {"kind": "dict", "fields": {"deed": "string", "who": "string"}}
	var held := {"kind": "dict", "fields": {"deed": "string", "value": "skip", "who": "string"}}
	return {
		"kind": "dict",
		"fields": {
			"publish": {"kind": "dict", "fields": {
				"beliefs": {"kind": "array", "of": {"kind": "dict", "fields": {"deed": "int", "t": "int", "who": "string"}}},
				"claim": {"kind": "dict", "fields": {"source": "string", "value": "string"}},
				"counters": {"kind": "dict", "wild": "int"},
				"covered": {"kind": "dict", "wild": "int"},
				"cursor": "string",
				"queued": {"kind": "array", "of": "string"},
			}},
			"rumor": {"kind": "dict", "fields": {
				"drawn": {"kind": "array", "of": "string"},
				"gone": {"kind": "array", "of": pair},
				"held": {"kind": "array", "of": held},
				"jobs": {"kind": "array", "of": job},
				"queued": {"kind": "array", "of": people},
				"reach": {"kind": "array", "of": reach},
				"seen": {"kind": "array", "of": people},
			}},
			"scheduler": {"kind": "dict", "fields": {
				"cache_refresh": {"kind": "array", "of": "string"},
				"publish": {"kind": "array", "of": "string"},
				"rumor": {"kind": "array", "of": "string"},
				"slice": "int",
				"waits": {"kind": "array", "of": "int"},
			}},
		},
	}


static func _shape_node(path: String, value: Variant, spec: Variant, facts: WyrdFactStore) -> Dictionary:
	if spec is String:
		return _shape_atom(path, value, String(spec), facts)
	if spec is Dictionary:
		var kind := String((spec as Dictionary).get("kind", ""))
		if kind == "dict":
			return _shape_dict(path, value, spec, facts)
		if kind == "loose_dict":
			if not (value is Dictionary):
				return {}
			return _shape_dict(path, value, spec, facts)
		if kind == "array":
			return _shape_array(path, value, spec, facts)
		if kind == "fact_map":
			return _shape_fact_map(path, value, facts)
	return {}


static func _shape_atom(path: String, value: Variant, kind: String, facts: WyrdFactStore) -> Dictionary:
	if kind == "skip":
		return {}
	if kind == "string":
		if value is String or value is StringName:
			return {}
		return _bad(path, "string")
	if kind == "int":
		if _is_whole(value):
			return {}
		return _bad(path, "int")
	if kind == "bool":
		if typeof(value) == TYPE_BOOL:
			return {}
		return _bad(path, "bool")
	if kind == "number":
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return {}
		return _bad(path, "number")
	if kind == "region_map":
		return _shape_dict(path, value, {"kind": "dict", "wild": _region_row_spec()}, facts)
	if kind == "evidence":
		return _shape_evidence(path, value, facts)
	if kind == "param":
		return _shape_param(path, value, facts)
	return {}


static func _shape_dict(path: String, value: Variant, spec: Dictionary, facts: WyrdFactStore) -> Dictionary:
	if not (value is Dictionary):
		return _bad(path, "dictionary")
	var body: Dictionary = value
	var fields: Dictionary = {}
	if spec.get("fields") is Dictionary:
		fields = spec["fields"]
	var names: Array = body.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for key in names:
		var child := _join(path, String(key))
		var next: Variant = null
		var named := String(key)
		if fields.has(named):
			next = fields[named]
		elif fields.has(key):
			next = fields[key]
		elif spec.has("wild"):
			next = spec["wild"]
		else:
			continue
		var issue := _shape_node(child, body[key], next, facts)
		if not issue.is_empty():
			return issue
	return {}


static func _shape_array(path: String, value: Variant, spec: Dictionary, facts: WyrdFactStore) -> Dictionary:
	if not (value is Array):
		return _bad(path, "array")
	var rows: Array = value
	# A valid deed log skips the per-field sort. Any reject falls through so the
	# first message stays the sorted generic walk.
	if path == "deeds.rows" and _deed_rows_ok(rows):
		return {}
	var of: Variant = spec.get("of", "skip")
	for index in rows.size():
		var issue := _shape_node("%s.%d" % [path, index], rows[index], of, facts)
		if not issue.is_empty():
			return issue
	return {}


static func _deed_rows_ok(rows: Array) -> bool:
	for item in rows:
		if not (item is Dictionary) or not _deed_row_ok(item):
			return false
	return true


static func _deed_row_ok(row: Dictionary) -> bool:
	for key in row.keys():
		var name := String(key)
		var value: Variant = row[key]
		if name == "actor" or name == "place" or name == "target" or name == "verb" or name == "visibility":
			if not _is_string(value):
				return false
		elif name == "id" or name == "t":
			if not _is_whole(value):
				return false
		elif name == "magnitude":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
		elif name == "memorable":
			if typeof(value) != TYPE_BOOL:
				return false
		elif name == "perception" or name == "tags" or name == "witnesses":
			if not _string_list_ok(value):
				return false
		elif name == "believers":
			if not _believers_ok(value):
				return false
	return true


static func _copy_for_check(data: Dictionary, share_deed_rows: bool) -> Dictionary:
	if not share_deed_rows:
		return data.duplicate(true)
	var deeds_value: Variant = data.get("deeds", null)
	if not (deeds_value is Dictionary):
		return data.duplicate(true)
	var deeds: Dictionary = deeds_value
	var rows_value: Variant = deeds.get("rows", null)
	if not (rows_value is Array):
		return data.duplicate(true)
	var working: Dictionary = {}
	for key in data.keys():
		if String(key) == "deeds":
			var copied: Dictionary = {}
			for deed_key in deeds.keys():
				if String(deed_key) == "rows":
					copied[deed_key] = (rows_value as Array).duplicate(false)
				else:
					copied[deed_key] = _deep_value(deeds[deed_key])
			working[key] = copied
		else:
			working[key] = _deep_value(data[key])
	return working


static func _deep_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


static func _string_list_ok(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in value:
		if not _is_string(item):
			return false
	return true


static func _believers_ok(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in value:
		if not (item is Dictionary) or not _believer_ok(item):
			return false
	return true


static func _believer_ok(row: Dictionary) -> bool:
	for key in row.keys():
		var name := String(key)
		var value: Variant = row[key]
		if name == "t":
			if not _is_whole(value):
				return false
		elif name == "who":
			if not _is_string(value):
				return false
	return true


static func _is_string(value: Variant) -> bool:
	return value is String or value is StringName


static func _shape_fact_map(path: String, value: Variant, facts: WyrdFactStore) -> Dictionary:
	if not (value is Dictionary):
		return _bad(path, "dictionary")
	var body: Dictionary = value
	var names: Array = body.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for key in names:
		var text := String(key)
		if facts == null:
			continue
		var word := facts.saved_type_issue(text, body[key])
		if word != "":
			return _bad(_join(path, text), word)
	return {}


static func _shape_evidence(path: String, value: Variant, facts: WyrdFactStore) -> Dictionary:
	if not (value is Dictionary):
		return _bad(path, "dictionary")
	var row: Dictionary = value
	var issue := _shape_dict(path, row, {"kind": "dict", "fields": {
		"actor": "string",
		"event": "string",
		"key": "string",
		"place": "string",
		"target": "string",
		"until": "int",
	}}, facts)
	if not issue.is_empty():
		return issue
	if row.has("value") and facts != null:
		var key := ""
		if row.get("key") is String or row.get("key") is StringName:
			key = String(row.get("key"))
		var word := facts.saved_type_issue(key, row["value"])
		if word != "":
			return _bad(_join(path, "value"), word)
	return {}


static func _shape_param(path: String, value: Variant, facts: WyrdFactStore) -> Dictionary:
	if value is String or value is StringName:
		return {}
	if not (value is Dictionary):
		return {"message": "save field %s must be a string or a dictionary" % _shown(path), "path": _shown(path)}
	return _shape_dict(path, value, {"kind": "dict", "fields": {"entity": "string", "kind": "string", "owner": "string", "place": "string"}}, facts)


static func _bad(path: String, word: String) -> Dictionary:
	var article := "a"
	if word == "int" or word == "array":
		article = "an"
	var shown := _shown(path)
	return {"message": "save field %s must be %s %s" % [shown, article, word], "path": shown}


static func _shown(path: String) -> String:
	if path == "":
		return "save"
	return path


static func _join(path: String, key: String) -> String:
	if path == "":
		return key
	return "%s.%s" % [path, key]


static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	if is_nan(value) or is_inf(value):
		return false
	return value == floor(value)


static func _capture_flight(runtime: WyrdRuntime) -> Dictionary:
	var out := {}
	if runtime.publish != null:
		var publish := runtime.publish.export_state()
		if not publish.is_empty():
			out["publish"] = publish
	if runtime.rumors != null:
		var rumor := runtime.rumors.export_state()
		if not rumor.is_empty():
			out["rumor"] = rumor
	var scheduler := {}
	if runtime.scheduler() != null:
		scheduler = runtime.scheduler().export_carry()
	var slice := runtime.slice_remainder_units()
	if slice != 0:
		var ordered := {}
		if scheduler.has("cache_refresh"):
			ordered["cache_refresh"] = scheduler["cache_refresh"]
		if scheduler.has("publish"):
			ordered["publish"] = scheduler["publish"]
		if scheduler.has("rumor"):
			ordered["rumor"] = scheduler["rumor"]
		ordered["slice"] = slice
		if scheduler.has("waits"):
			ordered["waits"] = scheduler["waits"]
		scheduler = ordered
	if not scheduler.is_empty():
		out["scheduler"] = scheduler
	return out


static func _import_flight(runtime: WyrdRuntime, data: Dictionary, report: WyrdLoadReport) -> void:
	if not data.has("flight"):
		runtime.set_slice_remainder(0)
		if runtime.scheduler() != null:
			runtime.scheduler().clear_carry()
			if _whole(data.get("schema_version", -1), -1) >= FLIGHT_SINCE_SCHEMA:
				runtime.scheduler().clear_dirty()
		if runtime.rumors != null:
			runtime.rumors.clear_flight()
		if runtime.publish != null:
			runtime.publish.clear()
		return
	var flight := _dict(data.get("flight", {}))
	var dropped := {}
	if runtime.rumors != null:
		for row in runtime.rumors.import_state(_dict(flight.get("rumor", {}))):
			var policy_id := str(row.get("policy", ""))
			var deed_id := str(row.get("deed", ""))
			dropped[deed_id] = true
			report.diagnostics.add(
				WyrdDiagnostic.E_SAVE_POLICY,
				WyrdRumor.missing_policy_message(policy_id, deed_id),
				"",
				1,
				1
			)
			report.add_row("policy", deed_id, "", "", 0, "E_SAVE_POLICY")
	if runtime.publish != null:
		runtime.publish.import_state(_dict(flight.get("publish", {})))
	var scheduler := _dict(flight.get("scheduler", {}))
	if not dropped.is_empty():
		scheduler = _without_rumor_deeds(scheduler, dropped)
	if runtime.scheduler() != null:
		runtime.scheduler().import_carry(scheduler)
	runtime.set_slice_remainder(_whole(scheduler.get("slice", 0), 0))


## Drops rumor tokens whose deed was refused. Other queues stay in order.
static func _without_rumor_deeds(scheduler: Dictionary, dropped: Dictionary) -> Dictionary:
	var raw: Variant = scheduler.get("rumor", [])
	if not (raw is Array):
		return scheduler
	var kept: Array = []
	for item in raw:
		var token := text_of(item, "")
		if dropped.has(_rumor_token_deed(token)):
			continue
		kept.append(token)
	var out := scheduler.duplicate()
	if kept.is_empty():
		out.erase("rumor")
	else:
		out["rumor"] = kept
	return out


static func _rumor_token_deed(token: String) -> String:
	var parts := token.split("\t")
	if parts.size() >= 2 and parts[0] == "reach":
		return parts[1]
	if parts.is_empty():
		return ""
	return parts[0]


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _whole(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


## [method String] for a string, [StringName], int, float, or bool. Other types return [param fallback].
static func text_of(value: Variant, fallback: String) -> String:
	if value is String or value is StringName:
		return String(value)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL:
		return str(value)
	return fallback


static func flag_of(value: Variant, fallback: bool) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return fallback


static func number_of(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


static func _callable(value: Variant) -> bool:
	return value is Callable and (value as Callable).is_valid()
