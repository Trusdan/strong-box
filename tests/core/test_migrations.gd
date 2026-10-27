extends GutTest

## StrongboxMigrations: ordered steps, refusals, no-op re-runs and chain validation.


## The worked example from the README: v1 had "hp", v2 renames it to "health",
## v3 adds "stamina" with a default.
func _example() -> StrongboxMigrations:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 3
	migrations.register(1, func(body: Dictionary) -> Dictionary:
		body["health"] = body.get("hp", 100)
		body.erase("hp")
		return body)
	migrations.register(2, func(body: Dictionary) -> Dictionary:
		body["stamina"] = body.get("stamina", 50)
		return body)
	return migrations


func test_steps_apply_in_order_and_input_is_unchanged() -> void:
	var v1: Dictionary = {"hp": 80, "room": "Cellar", "items": ["coin"]}
	var original: Dictionary = v1.duplicate(true)
	var result: StrongboxResult = _example().run(v1, 1)
	assert_true(result.ok, str(result))
	assert_eq(result.value["body"], {"health": 80, "room": "Cellar", "items": ["coin"], "stamina": 50})
	assert_eq(result.value["version"], 3)
	assert_eq(result.value["report"], [{"from": 1, "to": 2}, {"from": 2, "to": 3}])
	assert_eq(v1, original, "the input dictionary is unchanged, including nested values")
	var from_v2: StrongboxResult = _example().run({"health": 40}, 2)
	assert_eq(from_v2.value["body"], {"health": 40, "stamina": 50})
	assert_eq(from_v2.value["report"], [{"from": 2, "to": 3}])


func test_running_again_from_current_version_is_a_no_op() -> void:
	var migrations: StrongboxMigrations = _example()
	var upgraded: Dictionary = migrations.run({"hp": 10}, 1).value["body"]
	var again: StrongboxResult = migrations.run(upgraded, 3)
	assert_true(again.ok)
	assert_eq(again.value["body"], upgraded)
	assert_eq(again.value["report"], [])


func test_newer_save_is_refused() -> void:
	var result: StrongboxResult = _example().run({"health": 1}, 4)
	assert_eq(result.code, StrongboxMigrations.E_SCHEMA_TOO_NEW)
	assert_string_contains(result.message, "newer game version")


func test_too_old_save_is_refused() -> void:
	var migrations: StrongboxMigrations = _example()
	migrations.min_supported_version = 2
	var result: StrongboxResult = migrations.run({"hp": 1}, 1)
	assert_eq(result.code, StrongboxMigrations.E_SCHEMA_TOO_OLD)
	assert_string_contains(result.message, "too old")


func test_missing_step_is_a_gap() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 4
	migrations.register(1, func(body: Dictionary) -> Dictionary: return body)
	migrations.register(3, func(body: Dictionary) -> Dictionary: return body)
	var result: StrongboxResult = migrations.run({}, 1)
	assert_eq(result.code, StrongboxMigrations.E_SCHEMA_GAP)
	assert_string_contains(result.message, "2 to 3")


func test_step_returning_a_non_dictionary_fails_with_its_number() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 3
	migrations.register(1, func(body: Dictionary) -> Dictionary: return body)
	migrations.register(2, func(_body: Dictionary) -> Variant: return [1, 2])
	var result: StrongboxResult = migrations.run({}, 1)
	assert_eq(result.code, StrongboxMigrations.E_MIGRATION_FAILED)
	assert_string_contains(result.message, "schema 2 to 3")


func test_step_with_a_script_error_fails_with_its_number() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 2
	migrations.register(1, func(body: Dictionary) -> Dictionary:
		var missing: Dictionary = body["no_such_key"] # a runtime error, GDScript's "throw"
		return missing)
	var result: StrongboxResult = migrations.run({}, 1)
	assert_engine_error("no_such_key")
	assert_eq(result.code, StrongboxMigrations.E_MIGRATION_FAILED, "not a silent empty body")
	assert_string_contains(result.message, "schema 1 to 2")
	assert_string_contains(result.message, "no_such_key", false)


func test_step_that_only_warns_still_succeeds() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 2
	migrations.register(1, func(body: Dictionary) -> Dictionary:
		push_warning("stamina missing, used a default")
		body["stamina"] = 50
		return body)
	var result: StrongboxResult = migrations.run({"health": 10}, 1)
	assert_true(result.ok, "a warning is not a failure: %s" % result)
	assert_eq(result.value["body"], {"health": 10, "stamina": 50})


func test_step_that_pushes_an_error_fails() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	migrations.current_version = 2
	migrations.register(1, func(body: Dictionary) -> Dictionary:
		push_error("could not convert the inventory")
		return body)
	var result: StrongboxResult = migrations.run({"health": 10}, 1)
	assert_push_error("could not convert the inventory")
	assert_eq(result.code, StrongboxMigrations.E_MIGRATION_FAILED, "push_error is still a failure")


func test_register_refuses_duplicates_and_bad_input() -> void:
	var migrations: StrongboxMigrations = StrongboxMigrations.new()
	assert_true(migrations.register(1, func(body: Dictionary) -> Dictionary: return body).ok)
	assert_eq(migrations.register(1, func(body: Dictionary) -> Dictionary: return body).code, StrongboxMigrations.E_BAD_STEP)
	assert_eq(migrations.register(0, func(body: Dictionary) -> Dictionary: return body).code, StrongboxMigrations.E_BAD_STEP)
	assert_eq(migrations.register(2, Callable()).code, StrongboxMigrations.E_BAD_STEP)


func test_validate_chain_catches_gaps() -> void:
	assert_true(_example().validate_chain().ok)
	var gapped: StrongboxMigrations = StrongboxMigrations.new()
	gapped.current_version = 5
	gapped.register(2, func(body: Dictionary) -> Dictionary: return body)
	gapped.register(4, func(body: Dictionary) -> Dictionary: return body)
	var result: StrongboxResult = gapped.validate_chain()
	assert_eq(result.code, StrongboxMigrations.E_SCHEMA_GAP)
	assert_string_contains(result.message, "1, 3")
	gapped.min_supported_version = 4
	assert_true(gapped.validate_chain().ok, "steps below min_supported_version are not needed")
	gapped.min_supported_version = 6
	assert_eq(gapped.validate_chain().code, StrongboxMigrations.E_SCHEMA_GAP, "min above current is a setup error")
	var fresh: StrongboxMigrations = StrongboxMigrations.new()
	assert_true(fresh.validate_chain().ok, "version 1 with no steps is a valid chain")


func test_format_migrations_use_the_internal_table() -> void:
	var format: StrongboxMigrations = StrongboxMigrations.format_migrations()
	assert_eq(format.current_version, StrongboxEnvelope.FORMAT_VERSION)
	assert_true(format.validate_chain().ok, "format 1 needs no steps")
	assert_eq(format.run({"a": 1}, 1).value["report"], [])
	# Test hook: a future format step registered in the internal table is picked up.
	StrongboxMigrations._format_steps[1] = func(body: Dictionary) -> Dictionary:
		body["upgraded"] = true
		return body
	var hooked: StrongboxMigrations = StrongboxMigrations.format_migrations()
	hooked.current_version = 2
	assert_eq(hooked.run({"a": 1}, 1).value["body"], {"a": 1, "upgraded": true})
	StrongboxMigrations._format_steps.clear()
	assert_true(StrongboxMigrations._format_steps.is_empty())
