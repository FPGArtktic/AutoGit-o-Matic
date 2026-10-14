#!/usr/bin/env bats
#
# bundle: an incremental git bundle per repository, for carrying to a
# machine with no network. The state of what has been exported lives in
# the repository it describes, under $GIT_DIR/autogit.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
	BUNDLES="$BATS_TEST_TMPDIR/bundles"
	printf '[DEFAULTS]\nbundle_dir = %s\n\n[BUNDLE]\npath = %s\n' \
		"$BUNDLES" "$CLONE" > config.ini
}

# only_bundle
# Print the single bundle file in the bundle directory.
only_bundle() {
	find "$BUNDLES" -name '*.bundle' | head -n 1
}

@test "the first run writes a bundle and a manifest" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"BUNDLE: $CLONE - Success"* ]]
	[[ "$output" == *"bundled "* ]]
	[ -n "$(only_bundle)" ]
	grep -q '\.bundle$' "$BUNDLES/SHA256SUMS"
}

@test "the bundle carries the repository into a fresh clone" {
	local restored
	run_tool --config config.ini
	[ "$status" -eq 0 ]
	restored="$BATS_TEST_TMPDIR/restored"

	git clone -q -- "$(only_bundle)" "$restored"

	[ "$(git -C "$restored" rev-parse master)" = \
		"$(git -C "$CLONE" rev-parse master)" ]
}

@test "a second run with nothing new writes no second bundle" {
	run_tool --config config.ini
	[ "$status" -eq 0 ]

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing new to bundle"* ]]
	[ "$(find "$BUNDLES" -name '*.bundle' | wc -l)" -eq 1 ]
}

@test "a new commit produces a second, incremental bundle" {
	local first second candidate
	run_tool --config config.ini
	first="$(only_bundle)"
	advance_remote up 'second'
	git -C "$CLONE" fetch -q origin
	git -C "$CLONE" merge -q --ff-only origin/master

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ "$(find "$BUNDLES" -name '*.bundle' | wc -l)" -eq 2 ]
	# Both bundles can carry the same timestamp, and the checksum that
	# follows it does not sort by age, so pick the one that is not the
	# first rather than trusting the order.
	for candidate in "$BUNDLES"/*.bundle; do
		if [ "$candidate" != "$first" ]; then
			second="$candidate"
		fi
	done
	[ -n "$second" ]

	# The second bundle is incremental, so it cannot stand on its own:
	# cloning it without the first one's objects has to fail.
	run git clone -q -- "$second" "$BATS_TEST_TMPDIR/incomplete"
	[ "$status" -ne 0 ]
}

@test "the exported tips are recorded inside the repository" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[ -f "$CLONE/.git/autogit/bundle-tips" ]
	grep -q 'refs/heads/master' "$CLONE/.git/autogit/bundle-tips"
}

@test "no bundle_dir is a skip, not a failure" {
	printf '[BUNDLE]\npath = %s\n' "$CLONE" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped"* ]]
	[[ "$output" == *"no bundle_dir"* ]]
}

@test "--dry-run writes no bundle at all" {
	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"Would write a bundle"* ]]
	[ ! -d "$BUNDLES" ]
}

@test "a fresh bundle counts as updated in the summary" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=1"* ]]
}
