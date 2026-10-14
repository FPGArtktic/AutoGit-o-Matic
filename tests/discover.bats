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

@test "discovery descends more than one level by default" {
	local remote
	remote="$(make_remote up)"
	mkdir -p deep/nested
	git clone -q -- "$remote" deep/nested/repo
	pull_config "$BATS_TEST_TMPDIR/deep"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $BATS_TEST_TMPDIR/deep/nested/repo"* ]]
}

@test "discovery stops after five levels" {
	local remote
	remote="$(make_remote up)"
	mkdir -p one/two/three/four/five/six
	git clone -q -- "$remote" one/two/three/four/five/six/repo
	pull_config "$BATS_TEST_TMPDIR/one"

	run_tool --config config.ini --dry-run

	[[ "$output" == *"No Git repositories found"* ]]
}

@test "max_depth = 1 brings back the shallow scan of 1.0.0" {
	local remote
	remote="$(make_remote up)"
	mkdir -p deep/nested
	git clone -q -- "$remote" deep/nested/repo
	printf '[DEFAULTS]\nmax_depth = 1\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/deep" > config.ini

	run_tool --config config.ini --dry-run

	[[ "$output" == *"No Git repositories found"* ]]
}

@test "descent stops at a repository, so a nested one is not reported" {
	local remote
	remote="$(make_remote up)"
	mkdir -p many
	git clone -q -- "$remote" many/outer
	git clone -q -- "$remote" many/outer/vendor
	pull_config "$BATS_TEST_TMPDIR/many"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(pull_lines)" -eq 1 ]
	[[ "$output" == *"PULL: $BATS_TEST_TMPDIR/many/outer -"* ]]
	[[ "$output" != *"vendor"* ]]
}

@test "a repository excluded by a glob is left alone" {
	local remote
	remote="$(make_remote up)"
	mkdir -p many
	git clone -q -- "$remote" many/keep-me
	git clone -q -- "$remote" many/skip-me
	printf '[DEFAULTS]\nexclude = *skip-*\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/many" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $BATS_TEST_TMPDIR/many/keep-me"* ]]
	[[ "$output" != *"skip-me"* ]]
}

@test "several exclude globs are honoured" {
	local remote
	remote="$(make_remote up)"
	mkdir -p many
	git clone -q -- "$remote" many/alpha
	git clone -q -- "$remote" many/beta
	git clone -q -- "$remote" many/gamma
	printf '[DEFAULTS]\nexclude = */alpha,*/gamma\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/many" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ "$(pull_lines)" -eq 1 ]
	[[ "$output" == *"many/beta"* ]]
}

@test "max_depth bounds the scan" {
	local remote
	remote="$(make_remote up)"
	mkdir -p deep/nested
	git clone -q -- "$remote" deep/nested/repo
	printf '[DEFAULTS]\nmax_depth = 2\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/deep" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $BATS_TEST_TMPDIR/deep/nested/repo"* ]]
}

@test "max_depth 0 looks at the path and nowhere else" {
	local remote
	remote="$(make_remote up)"
	mkdir -p many
	git clone -q -- "$remote" many/first
	printf '[DEFAULTS]\nmax_depth = 0\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/many" > config.ini

	run_tool --config config.ini --dry-run

	[[ "$output" == *"No Git repositories found"* ]]
}

@test "an unreadable max_depth falls back to one level" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	mkdir -p many
	git clone -q -- "$remote" many/first
	printf '[DEFAULTS]\nmax_depth = soon\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/many" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"many/first"* ]]
}
