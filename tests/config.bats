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

@test "[DEFAULTS] supplies an option the repository does not set" {
	run_sourced "INI_STREAM=\"\$(printf 'DEFAULTS\\tssh_key\\t/from/defaults')\"
		printf 'key=%s\\n' \"\$(option_value ssh_key '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"key=/from/defaults"* ]]
}

@test "per-repo autogit.ssh-key beats [DEFAULTS] ssh_key" {
	git -C "$CLONE" config autogit.ssh-key /from/the/repo

	run_sourced "INI_STREAM=\"\$(printf 'DEFAULTS\\tssh_key\\t/from/defaults')\"
		printf 'key=%s\\n' \"\$(option_value ssh_key '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"key=/from/the/repo"* ]]
}

@test "an ssh_key becomes a GIT_SSH_COMMAND" {
	git -C "$CLONE" config autogit.ssh-key /keys/deploy

	run_sourced "printf 'cmd=%s\\n' \"\$(repo_ssh_command '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"cmd=ssh -i /keys/deploy -o IdentitiesOnly=yes"* ]]
}

@test "a repository with no ssh_key leaves the command alone" {
	run_sourced "printf 'cmd=[%s]\\n' \"\$(repo_ssh_command '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"cmd=[]"* ]]
}

@test "a per-repo timeout overrides the built-in one" {
	git -C "$CLONE" config autogit.timeout 7

	run_sourced "printf 'seconds=%s\\n' \"\$(repo_timeout '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"seconds=7"* ]]
}

@test "a nonsense timeout falls back to the built-in one" {
	git -C "$CLONE" config autogit.timeout later

	run_sourced "printf 'seconds=%s\\n' \"\$(repo_timeout '$CLONE')\""

	[ "$status" -eq 0 ]
	[[ "$output" == *"seconds=300"* ]]
}
