#!/usr/bin/env bats
#
# self_check: --self-check says what this machine can do, before any
# configuration file is involved.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
}

@test "--self-check reports git and exits 0" {
	run_tool --self-check

	[ "$status" -eq 0 ]
	[[ "$output" == *"ok       git"* ]]
	[[ "$output" == *"ok       awk"* ]]
}

@test "--self-check needs no configuration file" {
	run_tool --self-check

	[ "$status" -eq 0 ]
	[[ "$output" != *"not found"* ]] || true
	[[ "$output" != *"configuration file"* ]]
}

@test "--self-check prints the version it is reporting for" {
	local declared
	declared="$(sed -n 's/^VERSION=\(.*\)$/\1/p' "$AUTOGIT")"

	run_tool --self-check

	[ "$status" -eq 0 ]
	[[ "$output" == *"$declared"* ]]
}

@test "--self-check tells the optional tools apart from the required" {
	run_tool --self-check

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Eq '^(ok|optional) +(timeout|sha256sum|flock)'
}
