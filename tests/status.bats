#!/usr/bin/env bats
#
# status: --status reports what every configured repository looks like
# and changes nothing - no fetch, no refs, not even a lock.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	printf '[FETCH]\npath = %s\n' "$CLONE" > config.ini
	LOCK="$(lock_dir_for "$BATS_TEST_TMPDIR/config.ini")"
	rm -rf -- "$LOCK"
}

teardown() {
	if [ -n "${LOCK:-}" ]; then
		rm -rf -- "$LOCK"
	fi
}

@test "--status reports the mode, the branch and the distance" {
	advance_remote up 'second'
	git -C "$CLONE" fetch -q origin

	run_tool --config config.ini --status

	[ "$status" -eq 0 ]
	[[ "$output" == *"FETCH"* ]]
	[[ "$output" == *"$CLONE"* ]]
	[[ "$output" == *"master"* ]]
	[[ "$output" == *"ahead=0 behind=1"* ]]
	[[ "$output" == *"dirty=no"* ]]
}

@test "--status changes nothing at all" {
	local before
	advance_remote up 'second'
	before="$(refs_of "$CLONE")"

	run_tool --config config.ini --status

	[ "$status" -eq 0 ]
	[ "$(refs_of "$CLONE")" = "$before" ]
	[ ! -d "$LOCK" ]
	[[ "$output" != *"SUMMARY"* ]]
}

@test "--status reports a dirty work tree" {
	printf 'uncommitted\n' >> "$CLONE/file"

	run_tool --config config.ini --status

	[ "$status" -eq 0 ]
	[[ "$output" == *"dirty=yes"* ]]
}

@test "--status says dashes for a branch that tracks nothing" {
	git -C "$CLONE" checkout -q --no-track -b loner

	run_tool --config config.ini --status

	[ "$status" -eq 0 ]
	[[ "$output" == *"loner"* ]]
	[[ "$output" == *"ahead=- behind=-"* ]]
}

@test "--status runs while another run holds the lock" {
	mkdir -p -- "$LOCK"
	printf '%s\n' "$$" > "$LOCK/pid"

	run_tool --config config.ini --status

	[ "$status" -eq 0 ]
	[[ "$output" == *"$CLONE"* ]]
}
