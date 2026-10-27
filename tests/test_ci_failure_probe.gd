extends GutTest

## TEMPORARY: proves CI fails when a test fails. Reverted in the next commit.


func test_deliberate_failure() -> void:
	assert_eq(1, 2, "deliberate failure")
