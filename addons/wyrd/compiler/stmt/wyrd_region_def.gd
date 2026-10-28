class_name WyrdRegionDef
extends WyrdStmtSpan

## One parallel region inside a stage.
##
## @experimental
## [member stages] run one at a time. Regions of the same parent run together.
## A transition names a sibling stage in this region.

var id: String = ""
var stages: Array[WyrdStageDef] = []
