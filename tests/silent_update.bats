#!/usr/bin/env bats
#
# silent_update: fetch, then move a branch with `git branch -f` only
# when that is a fast-forward and nobody has the branch checked out.
# The work tree is never touched.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	printf '[SILENT_UPDATE]\npath = %s\n' "$CLONE" > config.ini
}

@test "a branch nobody has checked out is fast-forwarded" {
	local before_master before_file
	git -C "$CLONE" branch dev origin/master
	advance_remote up 'second'
	before_master="$(git -C "$CLONE" rev-parse master)"
	before_file="$(cat "$CLONE/file")"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"SILENT_UPDATE: $CLONE - Success"* ]]
	[[ "$output" == *"moved: dev"* ]]
	[ "$(git -C "$CLONE" rev-parse dev)" = \
		"$(git -C "$CLONE" rev-parse origin/master)" ]
	[ "$(git -C "$CLONE" rev-parse master)" = "$before_master" ]
	[ "$(cat "$CLONE/file")" = "$before_file" ]
}

@test "the checked out branch is never moved" {
	local before
	advance_remote up 'second'
	before="$(git -C "$CLONE" rev-parse master)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(git -C "$CLONE" rev-parse master)" = "$before" ]
	[[ "$output" == *"nothing to fast-forward"* ]]
}

@test "a branch checked out in a linked worktree is left alone" {
	local before
	git -C "$CLONE" branch side origin/master
	git -C "$CLONE" worktree add -q "$BATS_TEST_TMPDIR/linked" side
	advance_remote up 'second'
	before="$(git -C "$CLONE" rev-parse side)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(git -C "$CLONE" rev-parse side)" = "$before" ]
	[[ "$output" != *"moved: side"* ]]
}

@test "a diverged branch is left where it is" {
	local before
	git -C "$CLONE" branch dev origin/master
	git -C "$CLONE" checkout -q dev
	printf 'local side\n' >> "$CLONE/file"
	git -C "$CLONE" commit -qam 'local side'
	git -C "$CLONE" checkout -q master
	advance_remote up 'remote side'
	before="$(git -C "$CLONE" rev-parse dev)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(git -C "$CLONE" rev-parse dev)" = "$before" ]
	[[ "$output" == *"nothing to fast-forward"* ]]
}

@test "a branch ahead of its upstream is left alone" {
	local before
	git -C "$CLONE" branch dev origin/master
	git -C "$CLONE" checkout -q dev
	printf 'ahead\n' >> "$CLONE/file"
	git -C "$CLONE" commit -qam 'ahead'
	git -C "$CLONE" checkout -q master
	before="$(git -C "$CLONE" rev-parse dev)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(git -C "$CLONE" rev-parse dev)" = "$before" ]
}

@test "a branch that tracks nothing is left alone" {
	local before
	git -C "$CLONE" branch --no-track loner master
	advance_remote up 'second'
	before="$(git -C "$CLONE" rev-parse loner)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(git -C "$CLONE" rev-parse loner)" = "$before" ]
	[[ "$output" == *"nothing to fast-forward"* ]]
}

@test "a branch already at its upstream is not reported as moved" {
	git -C "$CLONE" branch dev origin/master

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to fast-forward"* ]]
}

@test "an unreachable remote is reported, and no branch moves" {
	local before
	git -C "$CLONE" branch dev origin/master
	git -C "$CLONE" remote set-url origin "$BATS_TEST_TMPDIR/gone.git"
	before="$(refs_of "$CLONE")"

	run_tool --config config.ini

	[[ "$output" == *"ERROR:"* ]]
	[[ "$output" == *"$CLONE"* ]]
	[ "$(refs_of "$CLONE")" = "$before" ]
}

@test "a bare repository is skipped, not failed" {
	printf '[SILENT_UPDATE]\npath = %s\n' "$REMOTE" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped"* ]]
	[[ "$output" == *"bare repository"* ]]
}

@test "--dry-run leaves every ref where it was" {
	local before
	git -C "$CLONE" branch dev origin/master
	advance_remote up 'second'
	before="$(refs_of "$CLONE")"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(refs_of "$CLONE")" = "$before" ]
	[[ "$output" == *"Would fetch and fast-forward"* ]]
}

@test "the section runs alongside [PULL] and [FETCH]" {
	local other
	other="$(make_clone "$REMOTE" second)"
	printf '[FETCH]\npath = %s\n\n[SILENT_UPDATE]\npath = %s\n' \
		"$other" "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"FETCH: $other"* ]]
	[[ "$output" == *"SILENT_UPDATE: $CLONE"* ]]
}
