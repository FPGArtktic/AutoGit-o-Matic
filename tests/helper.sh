# tests/helper.sh — fixtures shared by every .bats file.
#
# The harness runs under bash; the script under test is always executed
# by $AUTOGIT_SH (default sh), never by its own shebang (CLAUDE.md §5).
# Nothing here touches the network or the developer's git config.

# run_tool_stdout passes a flag to run, which bats 1.5 introduced.
bats_require_minimum_version 1.5.0

AUTOGIT_SH="${AUTOGIT_SH:-sh}"
AUTOGIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# $AUTOGIT may point elsewhere, which is how a regression test gets run
# against an older copy of the script to show that it fails there.
AUTOGIT="${AUTOGIT:-$AUTOGIT_ROOT/autogit-o-matic.sh}"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=autogit
export GIT_AUTHOR_EMAIL=autogit@example.invalid
export GIT_COMMITTER_NAME=autogit
export GIT_COMMITTER_EMAIL=autogit@example.invalid

# make_remote NAME
# Create a bare NAME.git with one commit on master, plus the work tree
# advance_remote pushes from; print the bare repository's path.
make_remote() {
	local name="${1:?make_remote: NAME required}"
	local work="$BATS_TEST_TMPDIR/work-$name"
	local bare="$BATS_TEST_TMPDIR/$name.git"

	git -c init.defaultBranch=master init -q -- "$work"
	printf 'one\n' > "$work/file"
	git -C "$work" add -- file
	git -C "$work" commit -qm 'initial'
	git clone -q --bare -- "$work" "$bare"
	printf '%s\n' "$bare"
}

# make_clone REMOTE NAME
# Clone REMOTE into NAME inside the test tmpdir; print the clone's path.
make_clone() {
	local remote="${1:?make_clone: REMOTE required}"
	local name="${2:?make_clone: NAME required}"
	local clone="$BATS_TEST_TMPDIR/$name"

	git clone -q -- "$remote" "$clone"
	printf '%s\n' "$clone"
}

# advance_remote NAME MESSAGE
# Put one new commit on NAME.git's master, so a fetch has work to do.
advance_remote() {
	local name="${1:?advance_remote: NAME required}"
	local message="${2:?advance_remote: MESSAGE required}"
	local work="$BATS_TEST_TMPDIR/work-$name"

	printf '%s\n' "$message" >> "$work/file"
	git -C "$work" add -- file
	git -C "$work" commit -qm "$message"
	git -C "$work" push -q "$BATS_TEST_TMPDIR/$name.git" master
}

# refs_of REPO
# Print every object id reachable from REPO's refs, for before/after
# comparison in --dry-run tests.
refs_of() {
	git -C "${1:?refs_of: REPO required}" rev-parse --all
}

# run_tool ARGS...
# Run the script under $AUTOGIT_SH via bats' run; sets $status/$output.
run_tool() {
	# Unquoted on purpose: $AUTOGIT_SH may be two words, such as
	# "bash --posix" or "busybox sh" (CLAUDE.md §5).
	# shellcheck disable=SC2086
	run $AUTOGIT_SH "$AUTOGIT" "$@"
}

# run_sourced CODE
# Source the script with AUTOGIT_LIB=1 under $AUTOGIT_SH, then run CODE,
# so a test can reach one function instead of a whole run.
run_sourced() {
	# Unquoted on purpose, as in run_tool.
	# shellcheck disable=SC2086
	run $AUTOGIT_SH -c "AUTOGIT_LIB=1 . '${AUTOGIT}'
${1}"
}

# run_tool_stdout ARGS...
# Like run_tool, but $output holds stdout alone, for the tests that
# read the log stream itself and must not see a warning on stderr.
run_tool_stdout() {
	# Unquoted on purpose, as in run_tool.
	# shellcheck disable=SC2086
	run --separate-stderr $AUTOGIT_SH "$AUTOGIT" "$@"
}

# lock_dir_for CONFIG
# Print the lock directory the script derives from CONFIG's path.
lock_dir_for() {
	local config="${1:?lock_dir_for: CONFIG required}" sum
	sum="$(printf '%s' "$config" | cksum)"
	printf '%s/autogit-o-matic-%s.lock\n' "${TMPDIR:-/tmp}" "${sum%% *}"
}
