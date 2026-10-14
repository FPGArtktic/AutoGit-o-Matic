# AutoGit-o-Matic — development task runner.
#
# `just check` is the pre-commit gate (CLAUDE.md §6). Every recipe is a
# plain command you can type by hand; no shell logic lives in this file.
#
# Development dependencies, none of them needed at runtime:
#	shellcheck, checkbashisms, shfmt	lint
#	bats-core, jq				test
#	kcov					coverage
#	dash, busybox				test-all

set shell := ["sh", "-eu", "-c"]

# List the recipes.
default:
	@just --list

# Lint gate: all three tools must report nothing (CLAUDE.md §2.1).
lint:
	shellcheck --shell=sh --severity=style --enable=all autogit-o-matic.sh
	checkbashisms --force autogit-o-matic.sh
	shfmt -p -i 0 -d autogit-o-matic.sh

# Run the bats suite with the script executed by SHELL.
test shell="sh":
	AUTOGIT_SH="{{shell}}" bats --print-output-on-failure tests

# The four shells the script must pass under (CLAUDE.md §2.1).
test-all: (test "sh") (test "dash") (test "bash --posix") (test "busybox sh")

# Line coverage of the script: floor 80 %, target 85 % (CLAUDE.md §5).
# kcov cannot follow bats 1.13 or newer - the same suite reports about
# half the lines - so pass an older one to measure for real:
#   just coverage ~/tools/bats-1.12/bin/bats
coverage bats="bats":
	AUTOGIT_SH=bash kcov --include-path="$PWD/autogit-o-matic.sh" \
		--exclude-region=kcov-exclude-start:kcov-exclude-stop \
		--clean "$PWD/coverage" {{bats}} tests
	jq -r '"line coverage: \(.percent_covered) % (floor 80, target 85)"' coverage/bats/coverage.json
	jq -e '(.percent_covered | tonumber) >= 80' coverage/bats/coverage.json >/dev/null

# The pre-commit gate (CLAUDE.md §10).
check: lint test-all coverage
