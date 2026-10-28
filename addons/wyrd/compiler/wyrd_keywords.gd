class_name WyrdKeywords
extends RefCounted

## Keyword lists for the VS Code grammar.
##
## @experimental
## The parser and the statement compiler keep their own compares. This file is
## the list the TextMate grammar mirrors, group by group. It does not change
## what the compiler accepts.


const HEADER: PackedStringArray = ["language"]
const BLOCKS: PackedStringArray = ["facts", "events", "quest", "scene", "role", "storylet", "sequence", "document", "template"]
const RESERVED: PackedStringArray = ["document", "publishes_by", "tier", "await_host", "believe", "declare", "forget", "learn", "retract"]
const TYPES: PackedStringArray = ["bool", "int", "float", "symbol"]
const FIELDS: PackedStringArray = [
	"default_holder",
	"eligibility",
	"scope",
	"succession",
	"vacancy",
	"visibility",
	"ai_context",
	"cooldown",
	"priority",
	"secrecy",
	"speaker",
	"speaker_cooldown",
	"weight",
	"when",
	"fragment",
	"text",
	"meta",
	"page",
	"on_read",
	"on_first_read",
	"claim",
	"fact",
	"verb",
	"publishes_by",
	"every",
	"delay",
	"stored",
	"source",
	"recap",
	"invalidate",
	"doc",
	"slot",
	"on_empty",
	"on_missing_stage",
	"start",
	"requires",
	"stage",
	"waits_until",
	"journal",
	"variant",
	"await_host",
	"on",
	"region",
	"redirect",
	"on_abort",
	"on_fail",
	"check",
	"disabled_when",
	"show_disabled_when",
	"ordered",
	"any",
	"where",
	"leaves",
	"decays",
	"mode",
	"live",
	"frozen",
	"cast",
	"locked_at",
	"lines",
	"within",
	"reset",
	"with",
	"topic",
	"quest",
	"role",
	"baseline",
	"copy",
	"deed",
	"to",
	"by",
	"of",
	"beat",
	"event",
	"witnesses",
	"actor",
	"magnitude",
	"memorable",
	"place",
	"statement",
	"tags",
	"target",
	"auto",
	"slant",
	"param",
	"max_active",
	"assumes",
	"allow_protected",
	"on_deed",
	"expires",
	"was",
]
const EFFECTS: PackedStringArray = [
	"set",
	"inc",
	"record",
	"unlock",
	"lock",
	"do",
	"outcome",
	"believe",
	"unbelieve",
	"declare",
	"retract",
	"learn",
	"forget",
	"start",
	"advance",
	"assign",
	"vacate",
	"adjust",
	"create",
]
const STATES: PackedStringArray = ["default", "successor", "empty", "hostile", "locked_gone", "contested", "unwilling", "barred"]
const OUTCOMES: PackedStringArray = ["route_closed", "done", "failed"]
const OPERATORS: PackedStringArray = ["and", "or", "not", "in"]
const CONDITIONAL: PackedStringArray = ["if", "else", "end"]
const BOOLEANS: PackedStringArray = ["true", "false"]


static func groups() -> Dictionary:
	return {
		"header": HEADER,
		"blocks": BLOCKS,
		"reserved": RESERVED,
		"types": TYPES,
		"fields": FIELDS,
		"effects": EFFECTS,
		"states": STATES,
		"outcomes": OUTCOMES,
		"operators": OPERATORS,
		"conditional": CONDITIONAL,
		"booleans": BOOLEANS,
	}


static func scopes() -> Dictionary:
	return {
		"header": "keyword.other.header.wyrd",
		"blocks": "keyword.other.block.wyrd",
		"reserved": "keyword.other.reserved.wyrd",
		"types": "storage.type.wyrd",
		"fields": "keyword.other.wyrd",
		"effects": "keyword.other.wyrd",
		"states": "keyword.control.wyrd",
		"outcomes": "keyword.control.wyrd",
		"operators": "keyword.operator.wyrd",
		"conditional": "keyword.control.conditional.wyrd",
		"booleans": "constant.language.wyrd",
	}
