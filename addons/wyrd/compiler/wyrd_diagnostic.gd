class_name WyrdDiagnostic
extends RefCounted

## One compiler diagnostic.
##
## @experimental
## [member code] is a [StringName] such as [code]E_HEADER_MISSING[/code].
## Formatted lines look like [code]path:line:col: error[CODE]: message[/code].
## [code]warning[/code] and [code]info[/code] use the same shape.

const SEVERITY_ERROR: StringName = &"error"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_INFO: StringName = &"info"

const E_HEADER_MISSING: StringName = &"E_HEADER_MISSING"
const E_HEADER_INVALID: StringName = &"E_HEADER_INVALID"
const E_TAB_INDENT: StringName = &"E_TAB_INDENT"
const E_INDENT_WIDTH: StringName = &"E_INDENT_WIDTH"
const E_INDENT_JUMP: StringName = &"E_INDENT_JUMP"
const E_RESERVED_WORD: StringName = &"E_RESERVED_WORD"
const E_UNTERMINATED_STRING: StringName = &"E_UNTERMINATED_STRING"
const E_BAD_ESCAPE: StringName = &"E_BAD_ESCAPE"
const E_LINE_TAG_POSITION: StringName = &"E_LINE_TAG_POSITION"
const E_LINE_TAG_FORMAT: StringName = &"E_LINE_TAG_FORMAT"
const E_UNEXPECTED_TOKEN: StringName = &"E_UNEXPECTED_TOKEN"
const E_FACTS_SYNTAX: StringName = &"E_FACTS_SYNTAX"
const E_FACTS_DUPLICATE: StringName = &"E_FACTS_DUPLICATE"
const E_EXPR_SYNTAX: StringName = &"E_EXPR_SYNTAX"
const E_EXPR_UNEXPECTED: StringName = &"E_EXPR_UNEXPECTED"
const E_EXPR_UNIT: StringName = &"E_EXPR_UNIT"
const E_EXPR_ARG_ORDER: StringName = &"E_EXPR_ARG_ORDER"
const E_INTERP_UNBALANCED: StringName = &"E_INTERP_UNBALANCED"
const E_UNKNOWN_FACT: StringName = &"E_UNKNOWN_FACT"
const E_UNKNOWN_FUNCTION: StringName = &"E_UNKNOWN_FUNCTION"
const E_KNOWN_REMOVED: StringName = &"E_KNOWN_REMOVED"
const E_ARG_TYPE: StringName = &"E_ARG_TYPE"
const E_ARG_NAME: StringName = &"E_ARG_NAME"
const E_OP_TYPE: StringName = &"E_OP_TYPE"
const E_NOT_BOOL: StringName = &"E_NOT_BOOL"
const E_CHANCE_CONTEXT: StringName = &"E_CHANCE_CONTEXT"
const E_SPATIAL_CONTEXT: StringName = &"E_SPATIAL_CONTEXT"
const E_RESOLVER_INVALIDATION: StringName = &"E_RESOLVER_INVALIDATION"
const E_RESOLVER_NO_INVALIDATE: StringName = &"E_RESOLVER_NO_INVALIDATE"
const E_WAIT_RESOLVER_MODE: StringName = &"E_WAIT_RESOLVER_MODE"
const E_EVENT_DUPLICATE: StringName = &"E_EVENT_DUPLICATE"
const E_EVENT_UNKNOWN: StringName = &"E_EVENT_UNKNOWN"
const E_EVENT_ARG: StringName = &"E_EVENT_ARG"
const E_EVENT_TYPE: StringName = &"E_EVENT_TYPE"
const E_SLOT_DUPLICATE: StringName = &"E_SLOT_DUPLICATE"
const E_STAGE_DUPLICATE: StringName = &"E_STAGE_DUPLICATE"
const E_SLOT_UNKNOWN: StringName = &"E_SLOT_UNKNOWN"
const E_SLOT_STATE: StringName = &"E_SLOT_STATE"
const E_OBJECT_SUCCESSION: StringName = &"E_OBJECT_SUCCESSION"
const E_LOCKED_AT_STAGE: StringName = &"E_LOCKED_AT_STAGE"
const E_STAGE_UNKNOWN: StringName = &"E_STAGE_UNKNOWN"
const E_STMT_UNKNOWN: StringName = &"E_STMT_UNKNOWN"
const E_LABEL_UNKNOWN: StringName = &"E_LABEL_UNKNOWN"
const E_LABEL_DUPLICATE: StringName = &"E_LABEL_DUPLICATE"
const E_CHOICE_SYNTAX: StringName = &"E_CHOICE_SYNTAX"
const E_CHECK_SYNTAX: StringName = &"E_CHECK_SYNTAX"
const E_SKILL_UNKNOWN: StringName = &"E_SKILL_UNKNOWN"
const E_SPEAKER_SHAPE: StringName = &"E_SPEAKER_SHAPE"
const E_WRITE_RESOLVED: StringName = &"E_WRITE_RESOLVED"
const E_WRITE_TYPE: StringName = &"E_WRITE_TYPE"
const E_EFFECT_NOT_IN_SLICE: StringName = &"E_EFFECT_NOT_IN_SLICE"
const E_NO_SET_DISPOSITION: StringName = &"E_NO_SET_DISPOSITION"
const E_LINE_ID_MISSING: StringName = &"E_LINE_ID_MISSING"
const E_LINE_ID_DUPLICATE: StringName = &"E_LINE_ID_DUPLICATE"
const E_VOICED_VARIABLE: StringName = &"E_VOICED_VARIABLE"
const E_AI_LINE: StringName = &"E_AI_LINE"
const E_AI_CONTEXT_UNKNOWN: StringName = &"E_AI_CONTEXT_UNKNOWN"
const E_VARIANT_SYNTAX: StringName = &"E_VARIANT_SYNTAX"
const E_FACT_REDECLARED: StringName = &"E_FACT_REDECLARED"
const E_QUEST_DUPLICATE: StringName = &"E_QUEST_DUPLICATE"
const E_QUEST_UNKNOWN: StringName = &"E_QUEST_UNKNOWN"
const E_TEMPLATE_SYNTAX: StringName = &"E_TEMPLATE_SYNTAX"
const E_TEMPLATE_REF: StringName = &"E_TEMPLATE_REF"
const E_TEMPLATE_UNKNOWN: StringName = &"E_TEMPLATE_UNKNOWN"
const E_ROLE_SYNTAX: StringName = &"E_ROLE_SYNTAX"
const E_ROLE_DUPLICATE: StringName = &"E_ROLE_DUPLICATE"
const E_SCENE_DUPLICATE: StringName = &"E_SCENE_DUPLICATE"
const E_SCENE_UNKNOWN: StringName = &"E_SCENE_UNKNOWN"
const E_STORYLET_SYNTAX: StringName = &"E_STORYLET_SYNTAX"
const E_STORYLET_DUPLICATE: StringName = &"E_STORYLET_DUPLICATE"
const E_SEQUENCE_SYNTAX: StringName = &"E_SEQUENCE_SYNTAX"
const E_SEQUENCE_DUPLICATE: StringName = &"E_SEQUENCE_DUPLICATE"
const E_DOCUMENT_SYNTAX: StringName = &"E_DOCUMENT_SYNTAX"
const E_DOCUMENT_DUPLICATE: StringName = &"E_DOCUMENT_DUPLICATE"
const E_DOCUMENT_UNKNOWN: StringName = &"E_DOCUMENT_UNKNOWN"
const E_DOCUMENT_NOT_FROZEN: StringName = &"E_DOCUMENT_NOT_FROZEN"
const E_SPEAKER_UNBOUND: StringName = &"E_SPEAKER_UNBOUND"
const E_COMMAND_UNKNOWN: StringName = &"E_COMMAND_UNKNOWN"
const E_COMMANDS_FILE: StringName = &"E_COMMANDS_FILE"
const W_SCENE_UNUSED: StringName = &"W_SCENE_UNUSED"
const W_SLOT_UNUSED: StringName = &"W_SLOT_UNUSED"
const W_EMPTY_UNCOVERED: StringName = &"W_EMPTY_UNCOVERED"
const W_LOCKED_GONE_UNCOVERED: StringName = &"W_LOCKED_GONE_UNCOVERED"
const W_SLOT_COND_ALWAYS: StringName = &"W_SLOT_COND_ALWAYS"
const W_SLOT_COND_NEVER: StringName = &"W_SLOT_COND_NEVER"
const W_ROUTE_CLOSED: StringName = &"W_ROUTE_CLOSED"
const W_PACK_UNKNOWN: StringName = &"W_PACK_UNKNOWN"
const W_ROLE_UNKNOWN: StringName = &"W_ROLE_UNKNOWN"
const W_TOPIC_NO_STORYLET: StringName = &"W_TOPIC_NO_STORYLET"
const W_FACT_NEVER_READ: StringName = &"W_FACT_NEVER_READ"
const W_FACT_NEVER_SET: StringName = &"W_FACT_NEVER_SET"
const W_FACT_UNUSED: StringName = &"W_FACT_UNUSED"
const W_RECAP_UNMARKED: StringName = &"W_RECAP_UNMARKED"
const W_INTERP_UNSET: StringName = &"W_INTERP_UNSET"
const W_SECRECY_LEAK: StringName = &"W_SECRECY_LEAK"
const W_AI_CONTEXT_RESOLVED_PER_QUERY: StringName = &"W_AI_CONTEXT_RESOLVED_PER_QUERY"
const W_STAGE_UNREACHABLE: StringName = &"W_STAGE_UNREACHABLE"
const W_HOLDER_UNGUARDED: StringName = &"W_HOLDER_UNGUARDED"
const W_DISABLED_WHEN_DEPRECATED: StringName = &"W_DISABLED_WHEN_DEPRECATED"
const W_STALE_BELIEF: StringName = &"W_STALE_BELIEF"
const W_CLAIM: StringName = &"W_CLAIM"
const E_FACT_LEAK: StringName = &"E_FACT_LEAK"
const I_COMMANDS_SKIPPED: StringName = &"I_COMMANDS_SKIPPED"
const I_STORYLET_SCORE: StringName = &"I_STORYLET_SCORE"
const I_TEMPLATE_SCORE: StringName = &"I_TEMPLATE_SCORE"
const W_STORYLET_TIE: StringName = &"W_STORYLET_TIE"
const W_TEMPLATE_TIE: StringName = &"W_TEMPLATE_TIE"
const W_TEMPLATE_TIER_UNKNOWN: StringName = &"W_TEMPLATE_TIER_UNKNOWN"
const W_TEMPLATE_TIER_ORDER: StringName = &"W_TEMPLATE_TIER_ORDER"
const W_SUBSTATE_DEPTH: StringName = &"W_SUBSTATE_DEPTH"
const E_SAVE_OPEN: StringName = &"E_SAVE_OPEN"
const E_SAVE_POLICY: StringName = &"E_SAVE_POLICY"
const E_SAVE_VERSION: StringName = &"E_SAVE_VERSION"
const W_SAVE_MANIFEST: StringName = &"W_SAVE_MANIFEST"
const W_SAVE_TEMPLATE: StringName = &"W_SAVE_TEMPLATE"
const W_SAVE_AI: StringName = &"W_SAVE_AI"
const E_ALIAS_CONFLICT: StringName = &"E_ALIAS_CONFLICT"
const E_ALIAS_DUPLICATE: StringName = &"E_ALIAS_DUPLICATE"
const E_ALIAS_CYCLE: StringName = &"E_ALIAS_CYCLE"
const W_SAVE_ALIAS: StringName = &"W_SAVE_ALIAS"
const E_MISSING_STAGE_TARGET: StringName = &"E_MISSING_STAGE_TARGET"
const W_SAVE_STAGE: StringName = &"W_SAVE_STAGE"

var severity: StringName = SEVERITY_ERROR
var code: StringName = &""
var message: String = ""
var path: String = ""
var line: int = 1
var col: int = 1


func _init(
	diagnostic_severity: StringName = SEVERITY_ERROR,
	diagnostic_code: StringName = &"",
	diagnostic_message: String = "",
	diagnostic_path: String = "",
	diagnostic_line: int = 1,
	diagnostic_col: int = 1
) -> void:
	severity = diagnostic_severity
	code = diagnostic_code
	message = diagnostic_message
	path = diagnostic_path
	line = diagnostic_line
	col = diagnostic_col


func format_line() -> String:
	return "%s:%d:%d: %s[%s]: %s" % [path, line, col, severity, code, message]
