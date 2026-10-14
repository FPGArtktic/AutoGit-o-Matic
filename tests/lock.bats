#!/usr/bin/env bats
#
# lock: overlapping cron runs were defect 4. The lock is a directory,
# because mkdir is atomic everywhere POSIX reaches.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	printf '[PULL]\npath = %s\n' "$CLONE" > config.ini
	LOCK="$(lock_dir_for "$BATS_TEST_TMPDIR/config.ini")"
	rm -rf -- "$LOCK"
}

teardown() {
	if [ -n "${LOCK:-}" ]; then
		rm -rf -- "$LOCK"
	fi
}

@test "releasing an empty lock path is a no-op" {
	run_sourced 'lock_release ""; printf "released=%s\n" "$?"'

	[ "$status" -eq 0 ]
	[[ "$output" == *"released=0"* ]]
}

@test "a second run exits 3 while a live run holds the lock" {
	mkdir -p -- "$LOCK"
	printf '%s\n' "$$" > "$LOCK/pid"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 3 ]
	[[ "$output" == *"another run holds"* ]]
	[ -d "$LOCK" ]
}

@test "a lock left by a dead process is reclaimed" {
	local dead
	sh -c 'exit 0' &
	dead="$!"
	wait "$dead" 2> /dev/null || true
	mkdir -p -- "$LOCK"
	printf '%s\n' "$dead" > "$LOCK/pid"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"reclaiming the stale lock"* ]]
	[[ "$output" == *"PULL: $CLONE"* ]]
}

@test "a lock with no pid in it counts as stale" {
	mkdir -p -- "$LOCK"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE"* ]]
}

@test "the lock is gone once the run ends" {
	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ ! -d "$LOCK" ]
}

@test "a second run in a row is not blocked by the first" {
	run_tool --config config.ini --dry-run
	[ "$status" -eq 0 ]

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" != *"another run holds"* ]]
	[ ! -d "$LOCK" ]
}

@test "two configurations do not lock each other out" {
	cp -- config.ini other.ini
	mkdir -p -- "$LOCK"
	printf '%s\n' "$$" > "$LOCK/pid"

	run_tool --config other.ini --dry-run

	[ "$status" -eq 0 ]
	rm -rf -- "$(lock_dir_for "$BATS_TEST_TMPDIR/other.ini")"
}
