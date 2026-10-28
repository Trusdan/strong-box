class_name WyrdDocumentView
extends RefCounted

## One opened readable document.
##
## [member pages] leaves out a page that has no visible paragraph. Each page is
## an array of [code]{id, text}[/code]. [member title] and each paragraph are
## translated with the line id, the same way dialogue is.

## Document id.
var id: StringName = &""
## Frozen copy id passed to open.
var copy_id: String = ""
## Entity that opened the document.
var reader: StringName = &""
## Translated document title.
var title: String = ""
## True when the document mode is frozen.
var frozen: bool = false
## True when this reader has not opened the document before.
var first_time: bool = false
## Document tags.
var tags: PackedStringArray = PackedStringArray()
## Document metadata.
var meta: Dictionary = {}
## Visible pages. Each page is an array of id and text. A page with no visible paragraph is left out.
var pages: Array = []
