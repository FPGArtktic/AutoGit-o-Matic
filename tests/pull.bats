#!/usr/bin/env bats
#
# pull: --ff-only, so an unattended run cannot invent a merge commit
# (defect 6), and the dirty work tree that must be skipped.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	printf '[PULL]\npath = %s\n' "$CLONE" > config.ini
}

@test "a fast-forward pull moves the branch" {
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE - Success"* ]]
	[ "$(git -C "$CLONE" rev-parse HEAD)" = \
		"$(git -C "$REMOTE" rev-parse master)" ]
}

@test "a diverged branch is reported, never merged" {
	local before
	advance_remote up 'remote side'
	printf 'local side\n' >> "$CLONE/file"
	git -C "$CLONE" add -- file
	git -C "$CLONE" commit -qm 'local side'
	before="$(git -C "$CLONE" rev-parse HEAD)"

	run_tool --config config.ini

	[[ "$output" == *"ERROR:"* ]]
	[ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
	[ "$(git -C "$CLONE" rev-list --count --merges HEAD)" -eq 0 ]
}

@test "a dirty work tree is skipped with a warning" {
	local before
	advance_remote up 'second'
	printf 'uncommitted\n' >> "$CLONE/file"
	before="$(git -C "$CLONE" rev-parse HEAD)"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"WARN: $CLONE - Skipped"* ]]
	[[ "$output" == *"working tree is dirty"* ]]
	[ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
}

@test "a bare repository is skipped, not failed" {
	printf '[PULL]\npath = %s\n' "$REMOTE" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped"* ]]
	[[ "$output" == *"bare repository"* ]]
}

@test "an untracked file does not block a pull" {
	advance_remote up 'second'
	printf 'scratch\n' > "$CLONE/untracked"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Success"* ]]
}
