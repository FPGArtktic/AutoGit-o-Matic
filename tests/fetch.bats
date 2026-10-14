#!/usr/bin/env bats
#
# fetch: prune and tags, and the credential prompt that used to hang a
# cron run (defect 5).

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	printf '[FETCH]\npath = %s\n' "$CLONE" > config.ini
}

@test "fetch brings new commits into the clone" {
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"FETCH: $CLONE - Success"* ]]
	[ "$(git -C "$CLONE" rev-parse origin/master)" = \
		"$(git -C "$REMOTE" rev-parse master)" ]
}

@test "fetch prunes a branch deleted on the remote" {
	git -C "$BATS_TEST_TMPDIR/work-up" push -q "$REMOTE" \
		master:refs/heads/gone
	git -C "$CLONE" fetch -q origin
	git -C "$CLONE" rev-parse --verify origin/gone
	git -C "$REMOTE" update-ref -d refs/heads/gone

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	run git -C "$CLONE" rev-parse --verify origin/gone
	[ "$status" -ne 0 ]
}

@test "fetch brings new tags" {
	git -C "$BATS_TEST_TMPDIR/work-up" tag v1
	git -C "$BATS_TEST_TMPDIR/work-up" push -q "$REMOTE" v1

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	git -C "$CLONE" rev-parse --verify v1
}

@test "an unreachable remote is reported, and the run still ends" {
	git -C "$CLONE" remote set-url origin "$BATS_TEST_TMPDIR/gone.git"

	run_tool --config config.ini

	[[ "$output" == *"ERROR:"* ]]
	[[ "$output" == *"$CLONE"* ]]
}

@test "git never gets a chance to prompt for credentials" {
	run_sourced 'printf "prompt=%s\n" "${GIT_TERMINAL_PROMPT}"'

	[ "$status" -eq 0 ]
	[[ "$output" == *"prompt=0"* ]]
}

@test "a git call still runs when timeout(1) is missing" {
	run_sourced "printf 'bare=%s\\n' \"\$(TIMEOUT_CMD= git_run '$CLONE' \
		rev-parse --is-bare-repository)\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"bare=false"* ]]
}

@test "a failed repository makes the run exit 2" {
	skip 'the exit-code contract is not implemented yet (CLAUDE.md §3.5)'
}
