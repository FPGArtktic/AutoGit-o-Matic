#!/usr/bin/env bats
#
# log: the line formats v1.0.0 shipped, which CLAUDE.md §2.2 freezes.
# JSON lines must validate with `jq -e .` (CLAUDE.md §3.5).

load helper.sh

setup() {
	cd "$BATS_TEST_TMPDIR" || return 1
	REMOTE="$(make_remote up)"
	CLONE="$(make_clone "$REMOTE" work)"
}

# json_config PATH
# Write config.ini: JSON log format, PATH in the [PULL] section.
json_config() {
	printf '[SETTINGS]\nlog_format = JSON\n\n[PULL]\npath = %s\n' \
		"$1" > config.ini
}

# write_section_config FORMAT
# A config whose [SETTINGS] log_format is FORMAT and which pulls $CLONE.
write_section_config() {
	printf '[SETTINGS]\nlog_format = %s\n\n[PULL]\npath = %s\n' \
		"$1" "$CLONE" > config.ini
}

@test "TXT is the default format and carries a timestamp" {
	printf '[PULL]\npath = %s\n' "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Eq \
		'^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PULL: '
}

@test "log_format = JSON makes every line validate with jq" {
	write_section_config JSON

	run_tool_stdout --config config.ini --dry-run

	[ "$status" -eq 0 ]
	[ -n "$output" ]
	while IFS= read -r line; do
		printf '%s\n' "$line" | jq -e . > /dev/null
	done <<< "$output"
}

@test "a JSON line carries timestamp, type, path and status" {
	write_section_config JSON

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | head -n 1 | jq -e \
		'has("timestamp") and has("type") and has("path") and has("status")' \
		> /dev/null
	[ "$(printf '%s\n' "$output" | head -n 1 | jq -r .type)" = PULL ]
	[ "$(printf '%s\n' "$output" | head -n 1 | jq -r .path)" = "$CLONE" ]
}

@test "log_format is case insensitive" {
	write_section_config json

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | head -n 1 | jq -e . > /dev/null
}

@test "an unknown log_format falls back to TXT" {
	write_section_config yaml

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Eq '^\[.*\] PULL: '
}

@test "a path holding no repository is reported as ERROR" {
	mkdir -p barren
	printf '[PULL]\npath = %s\n' "$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini --dry-run

	[[ "$output" == *"ERROR:"* ]]
	[[ "$output" == *"$BATS_TEST_TMPDIR/barren"* ]]
}

@test "a line with no message carries no parentheses" {
	run_sourced "log PULL /some/repo Success ''"

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Eq \
		'^\[[0-9-]{10} [0-9:]{8}\] PULL: /some/repo - Success$'
}

@test "a double quote in a path stays valid JSON" {
	local quoted
	quoted="$(make_clone "$REMOTE" 'quo"ted')"
	json_config "$quoted"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | jq -e . > /dev/null
	[ "$(printf '%s\n' "$output" | head -n 1 | jq -r .path)" = "$quoted" ]
}

@test "a backslash in a path stays valid JSON" {
	local slashed
	slashed="$(make_clone "$REMOTE" 'back\slash')"
	json_config "$slashed"

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | jq -e . > /dev/null
	[ "$(printf '%s\n' "$output" | head -n 1 | jq -r .path)" = "$slashed" ]
}

@test "git output containing a quote stays valid JSON" {
	# Defect 8.3: 1.0.0 pasted git's output into JSON unescaped.
	git -C "$CLONE" remote set-url origin "$BATS_TEST_TMPDIR/go\"ne.git"
	printf '[SETTINGS]\nlog_format = JSON\n\n[FETCH]\npath = %s\n' \
		"$CLONE" > config.ini

	run_tool_stdout --config config.ini

	printf '%s\n' "$output" | jq -e . > /dev/null
	[[ "$(printf '%s\n' "$output" | head -n 1 | jq -r .message)" == *'go"ne'* ]]
}

@test "every run ends with one summary line" {
	printf '[PULL]\npath = %s\n' "$CLONE" > config.ini

	run_tool --config config.ini --dry-run

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | tail -n 1 | grep -Eq \
		'^\[.*\] SUMMARY: updated=0 unchanged=1 skipped=0 failed=0 duration=[0-9]+s$'
	[ "$(printf '%s\n' "$output" | grep -c 'SUMMARY:')" -eq 1 ]
}

@test "the summary counts updated, unchanged, skipped and failed" {
	local second
	second="$(make_clone "$REMOTE" other)"
	advance_remote up 'second'
	printf 'uncommitted\n' >> "$second/file"
	mkdir -p barren
	printf '[PULL]\npath = %s\npath = %s\npath = %s\n' \
		"$CLONE" "$second" "$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini

	[[ "$output" == *"updated=1 unchanged=0 skipped=1 failed=1"* ]]
}

@test "the summary in JSON is one record of its own" {
	local summary
	write_section_config JSON

	run_tool_stdout --config config.ini --dry-run

	[ "$status" -eq 0 ]
	summary="$(printf '%s\n' "$output" | tail -n 1)"
	[ "$(printf '%s' "$summary" | jq -r .type)" = SUMMARY ]
	[ "$(printf '%s' "$summary" | jq -r .unchanged)" = 1 ]
	printf '%s' "$summary" | jq -e '.updated | type == "number"' > /dev/null
	printf '%s' "$summary" | jq -e '.duration | type == "number"' > /dev/null
}

@test "--quiet prints only errors" {
	mkdir -p barren
	printf '[PULL]\npath = %s\npath = %s\n' "$CLONE" \
		"$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini --dry-run --quiet

	[[ "$output" == *"ERROR:"* ]]
	[[ "$output" != *"PULL: $CLONE"* ]]
	[[ "$output" != *"SUMMARY:"* ]]
}

@test "--quiet still writes every line to the log file" {
	printf '[PULL]\npath = %s\n' "$CLONE" > config.ini

	run_tool_stdout --config config.ini --dry-run --quiet \
		--log-file run.log

	[ "$status" -eq 0 ]
	[ -z "$output" ]
	grep -q 'SUMMARY:' run.log
	grep -q -- "$CLONE" run.log
}

@test "a failed repository exits 0 and warns about 3.0.0" {
	mkdir -p barren
	printf '[PULL]\npath = %s\n' "$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 0 ]
	[[ "$output" == *"3.0.0 will exit 2"* ]]
}

@test "--strict-exit makes a failed repository exit 2" {
	mkdir -p barren
	printf '[PULL]\npath = %s\n' "$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini --strict-exit

	[ "$status" -eq 2 ]
	[[ "$output" != *"3.0.0 will exit 2"* ]]
}

@test "exit_on_failure = yes opts in without the flag" {
	mkdir -p barren
	printf '[SETTINGS]\nexit_on_failure = yes\n\n[PULL]\npath = %s\n' \
		"$BATS_TEST_TMPDIR/barren" > config.ini

	run_tool --config config.ini

	[ "$status" -eq 2 ]
}
