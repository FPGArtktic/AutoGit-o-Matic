#!/usr/bin/env bats
#
# cli: the flags v1.0.0 shipped. CLAUDE.md §2.2 freezes them, so this
# file is the backward-compatibility suite the POSIX rewrite must keep
# passing, under every shell in `just test-all`.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
}

@test "--help prints usage and exits 0" {
	run_tool --help

	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
	[[ "$output" == *"AutoGit-o-Matic"* ]]
}

@test "--help documents every flag v1.0.0 accepts" {
	run_tool --help

	[ "$status" -eq 0 ]
	for flag in --config --dry-run --verbose -v --log-file --help; do
		[[ "$output" == *"$flag"* ]]
	done
}

@test "an unknown flag exits 1 and names the flag" {
	run_tool --no-such-flag

	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option"* ]]
	[[ "$output" == *"--no-such-flag"* ]]
	[[ "$output" == *"Usage:"* ]]
}

@test "a missing configuration file exits 1" {
	run_tool --config "$BATS_TEST_TMPDIR/absent.ini"

	[ "$status" -eq 1 ]
	[[ "$output" == *"not found"* ]]
}

@test "--config reads the file it is given" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	printf '[PULL]\npath = %s\n' "$clone" > elsewhere.ini

	run_tool --config elsewhere.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"$clone"* ]]
}

@test "a bare path in a section is read like 'path ='" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	printf '[PULL]\n%s\n' "$clone" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"$clone"* ]]
}

@test "-v is an alias for --verbose" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	printf '[PULL]\npath = %s\n' "$clone" > config.ini

	run_tool --config config.ini --dry-run -v
	local short="$output"
	run_tool --config config.ini --dry-run --verbose

	[ "$status" -eq 0 ]
	[[ "$short" == *"[INFO]"* ]]
	[[ "$output" == *"[INFO]"* ]]
}

@test "--dry-run leaves git rev-parse --all identical" {
	local remote clone before after
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	advance_remote up 'second'
	printf '[PULL]\npath = %s\n' "$clone" > config.ini

	before="$(refs_of "$clone")"
	run_tool --config config.ini --dry-run
	after="$(refs_of "$clone")"

	[ "$status" -eq 0 ]
	[ "$before" = "$after" ]
	[[ "$output" == *"Dry Run"* ]]
}

@test "--log-file collects the lines it reports on stdout" {
	local remote clone
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	printf '[PULL]\npath = %s\n' "$clone" > config.ini

	run_tool --config config.ini --dry-run --log-file run.log

	[ "$status" -eq 0 ]
	[ -f run.log ]
	grep -q -- "$clone" run.log
}

@test "--config without a value exits 1" {
	run_tool --config

	[ "$status" -eq 1 ]
	[[ "$output" == *"needs a file"* ]]
}

@test "--log-file without a value exits 1" {
	run_tool --log-file

	[ "$status" -eq 1 ]
	[[ "$output" == *"needs a file"* ]]
}

@test "--version prints the VERSION constant and nothing else" {
	local declared
	declared="$(sed -n 's/^VERSION=\(.*\)$/\1/p' "$AUTOGIT")"

	run_tool --version

	[ "$status" -eq 0 ]
	[ -n "$declared" ]
	[ "$output" = "$declared" ]
}

@test "a configuration file beside the script is found under --verbose" {
	local bin remote clone
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin" "$BATS_TEST_TMPDIR/elsewhere"
	cp "$AUTOGIT" "$bin/autogit-o-matic.sh"
	remote="$(make_remote up)"
	clone="$(make_clone "$remote" work)"
	printf '[PULL]\npath = %s\n' "$clone" > "$bin/autogit-o-matic.ini"
	cd "$BATS_TEST_TMPDIR/elsewhere" || return 1

	# Defect 1: 1.0.0 called verbose_log here, before defining it.
	# shellcheck disable=SC2086  # $AUTOGIT_SH may be two words
	run $AUTOGIT_SH "$bin/autogit-o-matic.sh" --verbose --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"[INFO] Using configuration file:"* ]]
	[[ "$output" == *"PULL: $clone"* ]]
	[[ "$output" != *"not found"* ]]
}

@test "[FETCH] and [PULL] are both honoured in one run" {
	local remote pull_clone fetch_clone
	remote="$(make_remote up)"
	pull_clone="$(make_clone "$remote" pulled)"
	fetch_clone="$(make_clone "$remote" fetched)"
	printf '[PULL]\npath = %s\n\n[FETCH]\npath = %s\n' \
		"$pull_clone" "$fetch_clone" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $pull_clone"* ]]
	[[ "$output" == *"FETCH: $fetch_clone"* ]]
}
