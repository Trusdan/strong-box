class_name WyrdFactSchema
extends RefCounted

## Plain fact schema for one file.
##
## @experimental
## A key is declared once. A stored key and a resolved key that unify are
## [code]E_FACTS_DUPLICATE[/code], including a concrete key under a [code]{id}[/code] pattern.

var entries: Array[WyrdFact] = []
var _exact: Dictionary = {}
var _indexed: int = -1


func add(fact: WyrdFact, diagnostics: WyrdDiagnostics, source_path: String) -> void:
	for prior in entries:
		if _conflicts(prior, fact):
			diagnostics.add(
				WyrdDiagnostic.E_FACTS_DUPLICATE,
				_message(prior, fact),
				source_path,
				fact.line,
				fact.col
			)
			break
	entries.append(fact)


## Concrete key first, then a [code]{id}[/code] pattern of the same length.
## A query segment written as [code]{id}[/code] matches only a pattern wildcard.
## The first entry that overlaps [param fact], or null. Does not add a diagnostic.
func conflict(fact: WyrdFact) -> WyrdFact:
	for prior in entries:
		if _conflicts(prior, fact):
			return prior
	return null


func lookup(segments: PackedStringArray) -> WyrdFact:
	if segments.is_empty():
		return null
	_reindex()
	var wildcard := false
	for segment in segments:
		if segment.begins_with("{"):
			wildcard = true
			break
	if not wildcard:
		var key := ".".join(segments)
		if _exact.has(key):
			return _exact[key] as WyrdFact
	for fact in entries:
		if _pattern_match(fact, segments):
			return fact
	return null


func _reindex() -> void:
	if _indexed == entries.size():
		return
	_exact.clear()
	for fact in entries:
		if not fact.is_pattern() and not fact.key.is_empty():
			_exact[fact.key] = fact
	_indexed = entries.size()


func _pattern_match(fact: WyrdFact, segments: PackedStringArray) -> bool:
	if not fact.is_pattern() or fact.segments.size() != segments.size():
		return false
	for i in segments.size():
		var have := fact.segments[i]
		var want := segments[i]
		if have.begins_with("{"):
			continue
		if want.begins_with("{") or have != want:
			return false
	return true


func _conflicts(prior: WyrdFact, fact: WyrdFact) -> bool:
	if prior.segments.size() != fact.segments.size() or prior.segments.is_empty():
		return false
	for i in prior.segments.size():
		var left := prior.segments[i]
		var right := fact.segments[i]
		if left.begins_with("{") or right.begins_with("{"):
			continue
		if left != right:
			return false
	return true


func _message(prior: WyrdFact, fact: WyrdFact) -> String:
	if prior.key == fact.key:
		if prior.origin != fact.origin:
			return "fact key \"%s\" is both stored and resolved" % fact.key
		return "duplicate fact key \"%s\"" % fact.key
	if prior.origin != fact.origin:
		return "fact keys \"%s\" and \"%s\" are both stored and resolved" % [prior.key, fact.key]
	return "fact keys \"%s\" and \"%s\" overlap" % [prior.key, fact.key]
