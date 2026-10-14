#!/usr/bin/env bats
#
# mirror: clone --mirror the first time, remote update --prune after
# that, and follow the submodules .gitmodules names - including the
# relative URLs, which resolve against the source.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	SUB="$(make_remote sub)"
	SUPER="$BATS_TEST_TMPDIR/super.git"
	WORK="$BATS_TEST_TMPDIR/super-work"
	MIRRORS="$BATS_TEST_TMPDIR/mirrors"

	# A superproject whose submodule URL is relative, which is what
	# makes it worth testing: ../sub.git only means something next to
	# the superproject's own location.
	git -c init.defaultBranch=master init -q --bare "$SUPER"
	git clone -q -- "$SUPER" "$WORK"
	printf 'super\n' > "$WORK/file"
	git -C "$WORK" add -- file
	git -C "$WORK" commit -qm 'initial'
	git -C "$WORK" -c protocol.file.allow=always submodule add -q \
		../sub.git sub
	git -C "$WORK" commit -qm 'add the submodule'
	git -C "$WORK" push -q origin master

	printf '[DEFAULTS]\nmirror_dir = %s\n\n[MIRROR]\npath = %s\n' \
		"$MIRRORS" "$SUPER" > config.ini
}

@test "the first run clones a mirror" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"MIRROR: $SUPER - Success"* ]]
	[ -d "$MIRRORS/super.git" ]
	[ "$(git -C "$MIRRORS/super.git" rev-parse --is-bare-repository)" = true ]
	[ "$(git -C "$MIRRORS/super.git" rev-parse master)" = \
		"$(git -C "$SUPER" rev-parse master)" ]
}

@test "the second run updates the mirror instead of cloning again" {
	run_tool --config config.ini
	[ "$status" -eq 0 ]
	printf 'more\n' >> "$WORK/file"
	git -C "$WORK" commit -qam 'second'
	git -C "$WORK" push -q origin master

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" != *"ERROR"* ]]
	[[ "$output" == *"updated=1"* ]]
	[ "$(git -C "$MIRRORS/super.git" rev-parse master)" = \
		"$(git -C "$SUPER" rev-parse master)" ]
}

@test "a new ref appears in the mirror" {
	run_tool --config config.ini
	git -C "$WORK" push -q origin master:refs/heads/topic

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	git -C "$MIRRORS/super.git" rev-parse --verify topic
}

@test "a ref deleted on the source is pruned from the mirror" {
	git -C "$WORK" push -q origin master:refs/heads/gone
	run_tool --config config.ini
	git -C "$MIRRORS/super.git" rev-parse --verify gone
	git -C "$SUPER" update-ref -d refs/heads/gone

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	run git -C "$MIRRORS/super.git" rev-parse --verify gone
	[ "$status" -ne 0 ]
}

@test "a submodule from .gitmodules is mirrored as well" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"submodule"* ]]
	[ -d "$MIRRORS/sub.git" ]
	[ "$(git -C "$MIRRORS/sub.git" rev-parse master)" = \
		"$(git -C "$SUB" rev-parse master)" ]
}

@test "a source that is not there is reported as a failure" {
	printf '[DEFAULTS]\nmirror_dir = %s\n\n[MIRROR]\npath = %s\n' \
		"$MIRRORS" "$BATS_TEST_TMPDIR/absent.git" > config.ini

	run_tool --config config.ini

	[[ "$output" == *"ERROR:"* ]]
	[[ "$output" == *"failed=1"* ]]
	[ ! -d "$MIRRORS/absent.git" ]
}

@test "no mirror_dir is a skip, not a failure" {
	printf '[MIRROR]\npath = %s\n' "$SUPER" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped"* ]]
	[[ "$output" == *"no mirror_dir"* ]]
	[ ! -d "$MIRRORS" ]
}

@test "--dry-run creates no mirror at all" {
	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"Would clone or update the mirror"* ]]
	[ ! -d "$MIRRORS" ]
}

@test "a fresh mirror counts as updated in the summary" {
	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"updated=1"* ]]
}

@test "fsck = yes keeps a healthy mirror successful" {
	printf '[DEFAULTS]\nmirror_dir = %s\nfsck = yes\n\n[MIRROR]\npath = %s\n' \
		"$MIRRORS" "$SUPER" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Success"* ]]
	[ -d "$MIRRORS/super.git" ]
}

@test "verify_tags = yes passes when no tag is signed" {
	git -C "$WORK" tag plain
	git -C "$WORK" push -q origin plain
	printf '[DEFAULTS]\nmirror_dir = %s\nverify_tags = yes\n\n[MIRROR]\npath = %s\n' \
		"$MIRRORS" "$SUPER" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"Success"* ]]
}

@test "a relative URL resolves against the source, however deep" {
	run_sourced "printf 'one=%s\ntwo=%s\nabs=%s\n' \
		\"\$(resolve_url /srv/git/group/super.git ../sub.git)\" \
		\"\$(resolve_url /srv/git/group/super.git ../../other/sub.git)\" \
		\"\$(resolve_url /srv/git/group/super.git https://host/x.git)\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"one=/srv/git/group/sub.git"* ]]
	[[ "$output" == *"two=/srv/git/other/sub.git"* ]]
	[[ "$output" == *"abs=https://host/x.git"* ]]
}
