class_name WyrdStoryletIndex
extends RefCounted

## Sorted storylet ids for one pack, grouped by scope and speaker.
##
## @experimental
## Built at link. Not a save field. Each id is stored once, in the bucket of
## the last definition of that id. A bark row uses an empty scope id, because
## a bark query ignores the scope id. Speaker [code]any[/code] is its own
## bucket. A concrete query merges that speaker's bucket with the
## [code]any[/code] bucket. An empty query speaker, or [code]any[/code], merges
## every speaker bucket for the scope. [code]Any[/code] is a concrete speaker.
## [method text_bytes] is the UTF-8 size of the stored ids plus the bucket keys.

var _buckets: Dictionary = {}
var _id_count: int = 0
var _text_bytes: int = 0


func build(stories: Array) -> void:
	_buckets.clear()
	_id_count = 0
	_text_bytes = 0
	var latest: Dictionary = {}
	var order: Array[String] = []
	for item in stories:
		var story := item as WyrdStoryletDef
		if story == null or story.id.is_empty():
			continue
		if not latest.has(story.id):
			order.append(story.id)
		latest[story.id] = story
	var grouped: Dictionary = {}
	for id in order:
		var story: WyrdStoryletDef = latest[id]
		var scope_id := ""
		if story.scope_kind != &"bark":
			scope_id = story.scope_id
		var key := "%s\t%s\t%s" % [String(story.scope_kind), scope_id, story.speaker]
		var ids := PackedStringArray()
		if grouped.has(key):
			ids = grouped[key]
		ids.append(story.id)
		grouped[key] = ids
		_id_count += 1
		_text_bytes += story.id.to_utf8_buffer().size()
	for key in grouped.keys():
		var ids: PackedStringArray = grouped[key]
		ids.sort()
		_buckets[key] = ids
		_text_bytes += String(key).to_utf8_buffer().size()


func ids_for(kind: StringName, scope_id: String, speaker: String) -> PackedStringArray:
	var scope := scope_id
	if kind == &"bark":
		scope = ""
	var prefix := "%s\t%s\t" % [String(kind), scope]
	if speaker.is_empty() or speaker == "any":
		return _merge_prefix(prefix)
	return _merge_two(_bucket(prefix + speaker), _bucket(prefix + "any"))


func id_count() -> int:
	return _id_count


func bucket_count() -> int:
	return _buckets.size()


func text_bytes() -> int:
	return _text_bytes


func _bucket(key: String) -> PackedStringArray:
	if not _buckets.has(key):
		return PackedStringArray()
	return _buckets[key]


func _merge_prefix(prefix: String) -> PackedStringArray:
	var merged := PackedStringArray()
	for key in _buckets.keys():
		var name := String(key)
		if not name.begins_with(prefix):
			continue
		var bucket: PackedStringArray = _buckets[key]
		for item in bucket:
			merged.append(String(item))
	merged.sort()
	return merged


func _merge_two(left: PackedStringArray, right: PackedStringArray) -> PackedStringArray:
	var merged := PackedStringArray()
	for item in left:
		merged.append(String(item))
	for item in right:
		merged.append(String(item))
	merged.sort()
	return merged
