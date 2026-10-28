class_name WyrdTemplateDef
extends WyrdQuestDef

## One compiled quest template. Instances are [code]<id>#<n>[/code].
##
## @experimental
## The body reuses quest slots, [code]on_empty[/code], [code]on_missing_stage[/code], [code]requires[/code], and stages.
## There is no [code]start[/code]. [member when_cond] is a storylet condition.
## [member assumes] is a wait condition. A bare slot or param name in an entity
## argument, or compared with an entity, compiles as [code]holder(<name>)[/code].
## An empty tier overlaps every tier. A range overlaps every tier. Two single
## names overlap only when they are equal. [member weight] does not break a tie.

var params: Array[WyrdParamDef] = []
var when_cond: WyrdCompiledCondition = null
var when_text: String = ""
## Top-level [code]and[/code] pieces of [member when_text], in source order.
var clauses: Array[WyrdCompiledCondition] = []
var clause_text: PackedStringArray = PackedStringArray()
var specificity: int = 0
var priority: int = 0
var weight: int = 1
var max_active: int = 1
## Empty [member tier_low] and [member tier_high] with [member tier_range] false is any tier.
var tier_low: String = ""
var tier_high: String = ""
var tier_range: bool = false
var assumes: WyrdCompiledCondition = null
var assumes_text: String = ""
## One source text per top-level [code]and[/code] part, before holder rewriting.
var assumption_texts: PackedStringArray = PackedStringArray()
## Compiled [code]and[/code] parts after holder rewriting. Validators eval these.
var assumption_conds: Array[WyrdCompiledCondition] = []
var allow_protected: bool = false
## Minutes after creation before an instance is abandoned. 0 never expires.
var expires_minutes: int = 0
## [code]on_deed[/code] hooks, in source order. One verb at most once.
var deed_hooks: Array[WyrdDeedHookDef] = []


## Missing tiers overlap everything. A range overlaps anything. Two names overlap only if equal.
static func tiers_overlap(left: WyrdTemplateDef, right: WyrdTemplateDef) -> bool:
	if left == null or right == null:
		return false
	if _tier_missing(left) or _tier_missing(right):
		return true
	if left.tier_range or right.tier_range:
		return true
	return left.tier_low == right.tier_low


static func _tier_missing(template: WyrdTemplateDef) -> bool:
	return template.tier_low.is_empty() and template.tier_high.is_empty() and not template.tier_range
