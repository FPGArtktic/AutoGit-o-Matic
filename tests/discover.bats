#!/usr/bin/env bats
#
# discover: what counts as a repository. Regression tests for defect 2
# (paths containing spaces) and defect 7 (worktrees, bare mirrors).

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
}

# pull_config PATH...
# Write config.ini with a [PULL] section listing each PATH.
pull_config() {
	printf '[PULL]\n' > config.ini
	local path
	for path in "$@"; do
		printf 'path = %s\n' "$path" >> config.ini
	done
}

# pull_lines
# Print the PULL log lines of the last run.
pull_lines() {
	printf '%s\n' "$output" | grep -c 'PULL: ' || true
}

@test "a path that is a repository is processed as itself" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	pull_config "$clone"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(pull_lines)" -eq 1 ]
	[[ "$output" == *"PULL: $clone"* ]]
}

@test "a directory of repositories processes each repository" {
	local remote
	remote="$(make_remote up)"
	mkdir -p many/plain
	git clone -q -- "$remote" many/first
	git clone -q -- "$remote" many/second
	: > many/loose-file
	pull_config "$BATS_TEST_TMPDIR/many"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(pull_lines)" -eq 2 ]
}

@test "a bare mirror is a repository" {
	local remote
	remote="$(make_remote up)"
	printf '[FETCH]\npath = %s\n' "$remote" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"FETCH: $remote"* ]]
}

@test "a linked worktree is a repository" {
	local remote clone linked
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	linked="$BATS_TEST_TMPDIR/linked"
	git -C "$clone" worktree add -q "$linked" -b side
	[ -f "$linked/.git" ]
	pull_config "$linked"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $linked"* ]]
}

@test "a path containing spaces is one repository, not several words" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" 'work tree with spaces')"
	pull_config "$clone"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(pull_lines)" -eq 1 ]
	[[ "$output" == *"PULL: $clone"* ]]
	[[ "$output" != *"No Git repositories found"* ]]
}

@test "discovery goes one level down, no further" {
	local remote
	remote="$(make_remote up)"
	mkdir -p deep/nested
	git clone -q -- "$remote" deep/nested/repo
	pull_config "$BATS_TEST_TMPDIR/deep"

	run_tool --config config.ini --dry-run

	[[ "$output" == *"No Git repositories found"* ]]
}

@test "a repository excluded by a glob is left alone" {
	skip 'exclude globs arrive with v0.3.0 (CLAUDE.md §5)'
}

@test "max_depth bounds the scan" {
	skip 'max_depth arrives with v0.3.0 (CLAUDE.md §5)'
}
