class_name WyrdElectionAdapter
extends RefCounted

## Host-run election. Wyrd does not pick the successor.
##
## [method start_election] runs after [signal WyrdRoles.election_needed].
## The host finishes the contest with [method WyrdRoles.assign].

## Asks the host to run an election. The default body reports that it is not implemented.
func start_election(role: StringName, departed: StringName) -> void:
	push_error("not implemented: WyrdElectionAdapter.start_election(%s, %s)" % [role, departed])
