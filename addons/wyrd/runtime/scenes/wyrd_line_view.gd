class_name WyrdLineView
extends RefCounted

## One line ready for the host to show.
##
## [member text] is always set. [member audio] comes from [code]line_audio[/code]
## and may be null. Audio never replaces the text and never advances the line.

## Line id shown to the host.
var id: String = ""
## Speaker entity id.
var speaker: StringName = &""
## Name shown for the speaker.
var display_name: String = ""
## Role ids this speaker holds. A scene line lists quest slots passed into
## that scene. A bark lists world role bindings. Sorted.
## The host formats a name-plus-role label from these ids.
var roles: PackedStringArray = PackedStringArray()
## Line text. Always set.
var text: String = ""
## [code]authored[/code] or [code]ai[/code]. When it is [code]ai[/code], only
## [member text] differs from the authored line.
var text_source: StringName = &"authored"
## Tags on the shown line.
var tags: PackedStringArray = PackedStringArray()
## Audio for the line, or null. Audio does not replace the text and does not advance the line.
var audio: Variant = null
