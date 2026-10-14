#!/usr/bin/env bats
#
# config: the INI shapes 1.0.0 accepted, now read by one awk program.
# Defect 8: [PULL] and [FETCH] share the parser instead of duplicating it.

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
}

@test "comments and blank lines are ignored" {
	cat > config.ini <<-INI
		; a semicolon comment
		# a hash comment

		[PULL]
		; another comment

		path = $CLONE
	INI

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE"* ]]
	[[ "$output" != *"comment"* ]]
}

@test "spaces around 'path =' are trimmed" {
	printf '[PULL]\n   path   =   %s   \n' "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE -"* ]]
}

@test "a bare absolute path is read as a path" {
	printf '[PULL]\n%s\n' "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE"* ]]
}

@test "a bare relative line is ignored, as in 1.0.0" {
	printf '[PULL]\nwork\n' > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" != *"PULL: "* ]]
}

@test "a relative value of 'path =' is used" {
	printf '[PULL]\npath = work\n' > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: work"* ]]
}

@test "section names are case insensitive" {
	printf '[pull]\npath = %s\n' "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE"* ]]
}

@test "an unknown section is ignored" {
	printf '[BOGUS]\npath = /nowhere-at-all\n' > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" != *"nowhere-at-all"* ]]
}

@test "one section may list several paths" {
	local second
	second="$(make_clone "$REMOTE" other)"
	printf '[PULL]\npath = %s\npath = %s\n' "$CLONE" "$second" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"PULL: $CLONE"* ]]
	[[ "$output" == *"PULL: $second"* ]]
}

@test "an inline comment after log_format is ignored" {
	# README documents "log_format = JSON  # Can be TXT or JSON".
	printf '[SETTINGS]\nlog_format = JSON  # Can be TXT or JSON\n' > config.ini
	printf '\n[PULL]\npath = %s\n' "$CLONE" >> config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | jq -e . > /dev/null
}

@test "[DEFAULTS] overrides a section's settings" {
	skip '[DEFAULTS] is roadmap item 3 (CLAUDE.md §5)'
}

@test "per-repo git config autogit.* is honoured" {
	skip 'per-repo config is roadmap item 3 (CLAUDE.md §5)'
}
