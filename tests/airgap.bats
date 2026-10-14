#!/usr/bin/env bats
#
# airgap: the whole point of MIRROR and BUNDLE together - three
# repositories leave one machine and have to arrive on another with no
# network, as repositories a person can clone and pull from.

load helper.sh

setup() {
	local name
	cd "$BATS_TEST_TMPDIR" || return 1
	TRANSFER="$BATS_TEST_TMPDIR/transfer"
	for name in project library internal; do
		make_remote "$name" > /dev/null
	done
	printf '[DEFAULTS]\nmirror_dir = %s/mirrors\n\n[MIRROR]\n' \
		"$TRANSFER" > config.ini
	for name in project library internal; do
		printf 'source = %s\n' "$BATS_TEST_TMPDIR/$name.git" \
			>> config.ini
	done
}

@test "three repositories mirror in one run" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=3 unchanged=0 skipped=0 failed=0"* ]]
	[ -d "$TRANSFER/mirrors/project.git" ]
	[ -d "$TRANSFER/mirrors/library.git" ]
	[ -d "$TRANSFER/mirrors/internal.git" ]
}

@test "every mirror clones into a working repository" {
	local name
	run_tool --config config.ini
	[ "$status" -eq 0 ]

	for name in project library internal; do
		git clone -q -- "$TRANSFER/mirrors/$name.git" "restored-$name"
		[ "$(git -C "restored-$name" rev-parse master)" = \
			"$(git -C "$BATS_TEST_TMPDIR/$name.git" rev-parse master)" ]
	done
}

@test "a second run moves nothing when the sources stand still" {
	run_tool --config config.ini
	[ "$status" -eq 0 ]

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=0 unchanged=3 skipped=0 failed=0"* ]]
}

@test "only the repository that moved is counted as updated" {
	run_tool --config config.ini
	[ "$status" -eq 0 ]
	advance_remote library 'a change worth carrying'

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=1 unchanged=2"* ]]
	[ "$(git -C "$TRANSFER/mirrors/library.git" rev-parse master)" = \
		"$(git -C "$BATS_TEST_TMPDIR/library.git" rev-parse master)" ]
}

@test "bundles of three repositories carry a checkable manifest" {
	local name
	printf '[DEFAULTS]\nbundle_dir = %s/bundles\n\n[BUNDLE]\n' \
		"$TRANSFER" > config.ini
	for name in project library internal; do
		printf 'source = %s\n' "$BATS_TEST_TMPDIR/$name.git" \
			>> config.ini
	done

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=3"* ]]
	[ "$(find "$TRANSFER/bundles" -name '*.bundle' | wc -l)" -eq 3 ]
	[ "$(wc -l < "$TRANSFER/bundles/SHA256SUMS")" -eq 3 ]
	(cd "$TRANSFER/bundles" && sha256sum -c SHA256SUMS > /dev/null)
}

@test "a bundle restores a repository on the other side" {
	local bundle
	printf '[DEFAULTS]\nbundle_dir = %s/bundles\n\n[BUNDLE]\nsource = %s\n' \
		"$TRANSFER" "$BATS_TEST_TMPDIR/project.git" > config.ini
	run_tool --config config.ini
	[ "$status" -eq 0 ]
	bundle="$(find "$TRANSFER/bundles" -name 'project-*.bundle' | head -n 1)"

	git clone -q -- "$bundle" arrived

	[ "$(git -C arrived rev-parse master)" = \
		"$(git -C "$BATS_TEST_TMPDIR/project.git" rev-parse master)" ]
}
