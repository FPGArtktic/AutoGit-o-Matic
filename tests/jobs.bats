#!/usr/bin/env bats
#
# jobs: --jobs N works on several repositories at once. The log has to
# stay line-complete and the tally has to add up, which is why the
# tally lives in a file instead of a shell variable.

load helper.sh

setup() {
	local i
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	mkdir -p many
	for i in 1 2 3 4 5 6; do
		git clone -q -- "$REMOTE" "many/repo$i"
	done
	printf '[FETCH]\npath = %s\n' "$BATS_TEST_TMPDIR/many" > config.ini
}

# fetch_lines
# How many repository lines the last run printed.
fetch_lines() {
	printf '%s\n' "$output" | grep -c 'FETCH: ' || true
}

@test "--jobs 4 processes every repository" {
	run_tool --config config.ini --jobs 4 --dry-run

	[ "$status" -eq 0 ]
	[ "$(fetch_lines)" -eq 6 ]
}

@test "--jobs 1 processes every repository too" {
	run_tool --config config.ini --jobs 1 --dry-run

	[ "$status" -eq 0 ]
	[ "$(fetch_lines)" -eq 6 ]
}

@test "every line stays whole under --jobs" {
	local stray
	advance_remote up 'second'

	run_tool_stdout --config config.ini --jobs 6

	[ "$status" -eq 0 ]
	stray="$(printf '%s\n' "$output" |
		grep -vcE '^\[[0-9-]{10} [0-9:]{8}\] (FETCH|SUMMARY): ' || true)"
	[ "$stray" -eq 0 ]
}

@test "the tally adds up under --jobs" {
	advance_remote up 'second'

	run_tool --config config.ini --jobs 3

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=6 unchanged=0 skipped=0 failed=0"* ]]
}

@test "--jobs 0 is a usage error" {
	run_tool --config config.ini --jobs 0

	[ "$status" -eq 1 ]
	[[ "$output" == *"positive number"* ]]
}

@test "--jobs without a number is a usage error" {
	run_tool --config config.ini --jobs later

	[ "$status" -eq 1 ]
	[[ "$output" == *"positive number"* ]]
}
