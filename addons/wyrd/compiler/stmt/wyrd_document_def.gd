class_name WyrdDocumentDef
extends WyrdStmtSpan

## One compiled document.
##
## @experimental
## A header with [code]publishes_by[/code], [code]every[/code], or [code]delay[/code]
## is the periodic issue. [member period_minutes] and [member delay_minutes] are
## game minutes. [member fragments] are the slant rules, in source order. The
## first fragment whose condition is true supplies [code]slant[/code].
## A header without those words is a readable document. [member mode] is
## [code]live[/code] or [code]frozen[/code], and [member period_minutes] stays 0
## so the publish queue skips it. [member pages] hold paragraph prose.
## [member on_first_read] and [member on_read] are the read effects.
## Read flags are not stored on this def and are not facts.

var id: String = ""
## Old document ids from a [code]was:[/code] list, with the token position of each.
var was_ids: PackedStringArray = PackedStringArray()
var was_lines: PackedInt32Array = PackedInt32Array()
var was_cols: PackedInt32Array = PackedInt32Array()
var title: String = ""
var group: String = ""
var period_minutes: int = 0
var delay_minutes: int = 0
var claim_key: String = ""
var fact_key: String = ""
var verb_filter: String = ""
var fragments: Array[Dictionary] = []
## [code]live[/code] or [code]frozen[/code] for a readable document. Empty for a periodic issue.
var mode: String = ""
var line_id: String = ""
var tags: PackedStringArray = PackedStringArray()
var secrecy: String = ""
var meta: Dictionary = {}
var pages: Array = []
var on_first_read: Array[WyrdEffectDef] = []
var on_read: Array[WyrdEffectDef] = []
