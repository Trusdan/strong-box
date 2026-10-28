extends Node

## Test helper: a stand-in for the Wyrd facade with the three stable calls the bridge uses.

## A stand-in for one Wyrd diagnostic.
class FakeDiagnostic extends RefCounted:
	var code: StringName
	var severity: StringName

	func _init(diagnostic_code: StringName, diagnostic_severity: StringName) -> void:
		code = diagnostic_code
		severity = diagnostic_severity


## A stand-in for Wyrd's diagnostics list.
class FakeDiagnostics extends RefCounted:
	var items: Array = []


## A stand-in for a Wyrd load report.
class FakeReport extends RefCounted:
	var ok: bool = true
	var rows: Array = []
	var diagnostics: FakeDiagnostics = FakeDiagnostics.new()

	func error_count() -> int:
		var count: int = 0
		for item: FakeDiagnostic in diagnostics.items:
			if item.severity == &"error":
				count += 1
		return count


## True while a dialogue scene is "open".
var scene_open: bool = false
## What save_state() returns.
var state: Dictionary = {}
## The report load_state() returns next.
var next_report: FakeReport = FakeReport.new()
## Every Dictionary passed to load_state(), in order.
var loaded: Array[Dictionary] = []
## How many times save_state() was called.
var save_calls: int = 0
## Called on every load_state(), so a test can record the order of restores.
var on_load: Callable


## Builds a report from diagnostic codes, [code]{code: severity}[/code].
static func report(ok: bool, diagnostics: Dictionary) -> FakeReport:
	var made: FakeReport = FakeReport.new()
	made.ok = ok
	for diagnostic_code: StringName in diagnostics:
		made.diagnostics.items.append(FakeDiagnostic.new(diagnostic_code, diagnostics[diagnostic_code]))
	return made


func can_save() -> bool:
	return not scene_open


func save_state() -> Dictionary:
	save_calls += 1
	return {} if scene_open else state.duplicate(true)


func load_state(data: Dictionary) -> FakeReport:
	loaded.append(data)
	if on_load.is_valid():
		on_load.call()
	return next_report
