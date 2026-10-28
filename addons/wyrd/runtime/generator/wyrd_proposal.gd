class_name WyrdProposal
extends RefCounted

## One unsaved pick, cast, and bind result.
##
## [member id] is [code]p<seq>[/code]. The sequence resets on a new game and on
## load. [member casts] maps a cast slot to the picked entity. [member params]
## maps a param to [code]{entity, kind}[/code], plus [code]owner[/code] for an
## item and [code]place[/code] for an item or object when a spatial adapter is
## registered. The payload is not readable by content.

## Proposal id, p followed by a sequence number. The sequence resets on a new game and on load.
var id: String = ""
## Source name from the queued offer.
var source: String = ""
## Key from the queued offer.
var key: String = ""
## Pressure tier from the queued offer. Empty when the offer set none.
var tier: String = ""
## host for a host offer, or deed for a deed hook.
var origin: String = ""
## Chosen template id.
var template: String = ""
## Instance id, the template id plus a counter.
var instance: String = ""
## Cast slot mapped to the picked entity.
var casts: Dictionary = {}
## Param name mapped to the bound value.
var params: Dictionary = {}
## Copied offer payload. Content cannot read it.
var payload: Dictionary = {}
## Counter value [method WyrdGenerator.accept] requires. Not saved.
var expected_counter: int = 0
## True after a successful accept. A second accept returns [code]accepted[/code].
var used: bool = false
