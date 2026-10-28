class_name WyrdRumorPolicy
extends RefCounted

## One rumor rule. The host registers it from code. It is not saved.
##
## @experimental
## [member kinds] are directed relationship kinds. [member max_hops] is how many
## steps the claim may travel from an origin. An empty [member verbs] list
## matches every deed verb. [member pass_chance] is the seeded chance that a
## hop is offered. [code]1[/code] always offers it. [code]0[/code] never does.
## [member mutations] is an array of dictionaries. Each one has [code]field[/code]
## (the claim fact key), [code]to[/code] (a callable or [code]drop[/code]), and
## [code]keep_chance_fn[/code]. There is no [code].wyrd[/code] syntax for a policy.


var id: StringName = &""
var kinds: PackedStringArray = PackedStringArray()
var max_hops: int = 1
var verbs: PackedStringArray = PackedStringArray()
var pass_chance: float = 1.0
## Each item is [code]{field, to, keep_chance_fn}[/code]. Not saved.
var mutations: Array = []
