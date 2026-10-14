#!/usr/bin/env bats
#
# hook: on_change runs once for a repository whose refs moved, with the
# mode and the path in its environment. A hook that fails warns; it
# cannot fail an operation that already succeeded.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	MARK="$BATS_TEST_TMPDIR/ran"
}

# hook_config COMMAND
# A config whose [DEFAULTS] on_change is COMMAND and which fetches.
hook_config() {
	printf '[DEFAULTS]\non_change = %s\n\n[FETCH]\npath = %s\n' \
		"$1" "$CLONE" > config.ini
}

@test "on_change runs when the repository changed" {
	hook_config "touch $MARK"
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=1"* ]]
	[ -f "$MARK" ]
}

@test "on_change stays quiet when nothing changed" {
	hook_config "touch $MARK"

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"unchanged=1"* ]]
	[ ! -f "$MARK" ]
}

@test "the hook is told the mode and the repository" {
	hook_config "env > $BATS_TEST_TMPDIR/hook-env"
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	grep -q "^AUTOGIT_MODE=FETCH$" "$BATS_TEST_TMPDIR/hook-env"
	grep -q "^AUTOGIT_REPO=$CLONE$" "$BATS_TEST_TMPDIR/hook-env"
}

@test "a hook that fails warns and leaves the run successful" {
	hook_config 'false'
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"on_change failed"* ]]
	[[ "$output" == *"FETCH: $CLONE - Success"* ]]
	[[ "$output" == *"failed=0"* ]]
}

@test "a repository's own on-change wins over [DEFAULTS]" {
	git -C "$CLONE" config autogit.on-change "touch $BATS_TEST_TMPDIR/mine"
	hook_config "touch $MARK"
	advance_remote up 'second'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ -f "$BATS_TEST_TMPDIR/mine" ]
	[ ! -f "$MARK" ]
}
