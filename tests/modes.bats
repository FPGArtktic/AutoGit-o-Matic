#!/usr/bin/env bats
#
# modes: the dispatch that replaced the duplicated [PULL] and [FETCH]
# handling (defect 8). A new mode is one arm in run_mode.

load helper.sh

@test "run_mode refuses a mode it does not know" {
	run_sourced 'run_mode BOGUS /tmp; printf "status=%s\n" "$?"'

	[ "$status" -eq 0 ]
	[[ "$output" == *"unknown mode: BOGUS"* ]]
	[[ "$output" == *"status=2"* ]]
}
