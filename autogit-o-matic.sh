#!/bin/sh
# AutoGit-o-Matic: keep many Git repositories current from cron/systemd.
#
# Copyright (C) 2025 Mateusz Okulanis
# Email: FPGArtktic@outlook.com
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

VERSION=2.0.0

set -u

GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

readonly PROGRAM_NAME=autogit-o-matic
# Longest piece of git output kept on one log line.
readonly OUTPUT_LIMIT=150
# Seconds one git invocation may take, when timeout(1) is installed.
readonly GIT_TIMEOUT=300
# Exit codes. 2 (a repository failed) arrives with the summary line.
readonly EXIT_OK=0
readonly EXIT_USAGE=1
readonly EXIT_LOCKED=3

CONFIG_FILE=autogit-o-matic.ini
DRY_RUN=no
LOG_FORMAT=TXT
LOG_FILE=
VERBOSE=no
SCRIPT_DIR=.
INI_STREAM=
LOCK_PATH=
TIMEOUT_CMD=

# usage
# Print the synopsis and the flag list on stdout.
usage() (
	cat <<-EOF
		Usage: ${0} [OPTIONS]
		AutoGit-o-Matic: Automate Git operations across multiple repositories.

		Options:
		  --config FILE    Path to the configuration file (default: autogit-o-matic.ini)
		  --dry-run        Simulate operations without actually executing Git commands
		  --verbose, -v    Display more detailed information about operations
		  --log-file FILE  Write logs to the specified file as well as to stdout
		  --version        Print the version and exit
		  --help           Display this help message and exit

	EOF
)

# warn MESSAGE
# Report MESSAGE on stderr as "autogit-o-matic: MESSAGE"; the run goes on.
warn() (
	printf '%s: %s\n' "${PROGRAM_NAME}" "${1}" >&2
)

# die CODE MESSAGE
# Report MESSAGE on stderr and leave the script with status CODE.
# Brace body on purpose: exit must leave the script, not a subshell.
die() {
	warn "${2}"
	exit "${1}"
}

# script_directory
# Print the directory holding this script, as 1.0.0 did with BASH_SOURCE.
script_directory() (
	here="$(dirname -- "${0}")"

	CDPATH='' cd -P -- "${here}" && pwd
)

# absolute_path PATH
# Print PATH with its directory resolved, so a lock name cannot depend
# on the working directory a cron entry happens to start in.
absolute_path() (
	dir="$(dirname -- "${1}")"
	base="$(basename -- "${1}")"
	root="$(CDPATH='' cd -P -- "${dir}" && pwd)" || return 1

	printf '%s/%s\n' "${root%/}" "${base}"
)

# timestamp
# Print the local time in the format 1.0.0 wrote.
timestamp() (
	date '+%Y-%m-%d %H:%M:%S'
)

# compact
# Fold stdin onto one line, squeeze blanks, cut it to ${OUTPUT_LIMIT}.
compact() (
	tr '\n\r\t' '   ' | tr -s ' ' | sed 's/^ //; s/ $//' |
		cut -c "1-${OUTPUT_LIMIT}"
)

# log_txt LEVEL PATH STATUS MESSAGE
# Print one line in the text format 1.0.0 wrote.
log_txt() (
	now="$(timestamp)"

	if [ "${1}" = ERROR ]; then
		printf '[%s] ERROR: %s Path: %s\n' "${now}" "${4}" "${2}"
		return 0
	fi
	if [ -z "${4}" ]; then
		printf '[%s] %s: %s - %s\n' "${now}" "${1}" "${2}" "${3}"
		return 0
	fi
	printf '[%s] %s: %s - %s (%s)\n' "${now}" "${1}" "${2}" "${3}" "${4}"
)

# log_json LEVEL PATH STATUS MESSAGE
# Print one JSON object; one awk function escapes every field.
log_json() (
	now="$(timestamp)"

	printf '%s\t%s\t%s\t%s\t%s' "${now}" "${1}" "${2}" "${3}" "${4}" |
		awk -F '\t' '
		# kcov-exclude-start: awk source, not shell lines
		function esc(s,    out, c, i)
		{
			out = ""
			for (i = 1; i <= length(s); i++) {
				c = substr(s, i, 1)
				if (c == "\"" || c == "\\")
					out = out "\\" c
				else if (c < " ")
					out = out " "
				else
					out = out c
			}
			return out
		}
		{
			line = "{\"timestamp\":\"" esc($1) "\""
			line = line ",\"type\":\"" esc($2) "\""
			line = line ",\"path\":\"" esc($3) "\""
			line = line ",\"status\":\"" esc($4) "\""
			if ($5 != "")
				line = line ",\"message\":\"" esc($5) "\""
			print line "}"
		}
		# kcov-exclude-stop
		'
)

# log LEVEL PATH STATUS MESSAGE
# Emit one line in ${LOG_FORMAT} on stdout and, when set, in ${LOG_FILE}.
log() (
	message="$(printf '%s' "${4}" | compact)"

	if [ "${LOG_FORMAT}" = JSON ]; then
		line="$(log_json "${1}" "${2}" "${3}" "${message}")"
	else
		line="$(log_txt "${1}" "${2}" "${3}" "${message}")"
	fi
	printf '%s\n' "${line}"
	if [ -n "${LOG_FILE}" ]; then
		printf '%s\n' "${line}" >>"${LOG_FILE}"
	fi
)

# verbose LEVEL MESSAGE
# Print "[LEVEL] MESSAGE" on stdout, but only under --verbose.
verbose() (
	if [ "${VERBOSE}" != yes ]; then
		return 0
	fi
	printf '[%s] %s\n' "${1}" "${2}"
)

# git_is_repo PATH
# Returns 0 when PATH is a work tree, a linked worktree, or bare.
# --resolve-git-dir takes its path as the option value, so no -- here.
git_is_repo() (
	if git rev-parse --resolve-git-dir "${1}/.git" >/dev/null 2>&1; then
		return 0
	fi
	git rev-parse --resolve-git-dir "${1}" >/dev/null 2>&1
)

# git_is_bare PATH
# Returns 0 when PATH is a bare or mirror repository.
git_is_bare() (
	bare="$(git -C "${1}" rev-parse --is-bare-repository 2>&1)"

	[ "${bare}" = true ]
)

# git_dirty PATH
# Returns 0 when PATH has staged or unstaged changes to tracked files.
git_dirty() (
	changes="$(git -C "${1}" status --porcelain --untracked-files=no 2>&1)"

	[ -n "${changes}" ]
)

# git_run PATH ARGS...
# Run git ARGS inside PATH, under timeout(1) when it exists.
# Prints git's output and stderr; returns git's status.
git_run() (
	path="${1}"
	shift

	cd -- "${path}" || return 1
	if [ -n "${TIMEOUT_CMD}" ]; then
		"${TIMEOUT_CMD}" "${GIT_TIMEOUT}" git "$@" 2>&1
		return "$?"
	fi
	git "$@" 2>&1
)

# git_fetch PATH
# Fetch every remote in PATH, pruning gone refs and taking tags.
git_fetch() (
	git_run "${1}" fetch --all --prune --tags
)

# git_pull PATH
# Pull PATH with --ff-only, so a run can never create a merge commit.
git_pull() (
	git_run "${1}" pull --ff-only
)

# discover_repos PATH
# Print every repository at PATH or one level below it, one per line.
# Work trees, linked worktrees and bare mirrors all come out the same.
discover_repos() (
	base="${1%/}"

	if [ -z "${base}" ]; then
		base=/
	fi
	if git_is_repo "${base}"; then
		printf '%s\n' "${base}"
		return 0
	fi
	for entry in "${base}"/*; do
		if [ -d "${entry}" ] && git_is_repo "${entry}"; then
			printf '%s\n' "${entry}"
		fi
	done
)

# mode_verb MODE
# Print the git subcommand MODE runs, for the log message.
mode_verb() (
	printf '%s' "${1}" | tr '[:upper:]' '[:lower:]'
)

# do_fetch REPO
# Fetch REPO. Returns 0 fetched, 2 git error; prints git's output.
do_fetch() (
	if git_fetch "${1}"; then
		return 0
	fi
	return 2
)

# do_pull REPO
# Pull REPO with --ff-only; a bare repo or a dirty work tree is skipped.
# Returns 0 pulled, 1 skipped, 2 git error; prints the reason or output.
do_pull() (
	if git_is_bare "${1}"; then
		printf 'bare repository\n'
		return 1
	fi
	if git_dirty "${1}"; then
		printf 'working tree is dirty\n'
		return 1
	fi
	if git_pull "${1}"; then
		return 0
	fi
	return 2
)

# run_mode MODE REPO
# Dispatch MODE to its handler; a new mode means one arm here.
run_mode() (
	case "${1}" in
	FETCH)
		do_fetch "${2}"
		;;
	PULL)
		do_pull "${2}"
		;;
	*)
		printf 'unknown mode: %s\n' "${1}"
		return 2
		;;
	esac
)

# process_repo MODE REPO
# Run MODE on REPO and log exactly one line about the outcome.
# Returns 0 done, 1 skipped, 2 failed.
process_repo() (
	verb="$(mode_verb "${1}")"

	if [ "${DRY_RUN}" = yes ]; then
		log "${1}" "${2}" 'Success (Dry Run)' \
			"Would execute 'git ${verb}'"
		return 0
	fi
	output="$(run_mode "${1}" "${2}")"
	result="$?"
	if [ "${result}" -eq 0 ]; then
		log "${1}" "${2}" Success "${output}"
		return 0
	fi
	if [ "${result}" -eq 1 ]; then
		log WARN "${2}" Skipped "${output}"
		return 1
	fi
	log ERROR "${2}" Failed \
		"Failed to execute git ${verb}: ${output}"
	return 2
)

# process_repos MODE PATH
# Run MODE on every repository discovered under PATH.
process_repos() (
	verbose INFO "Processing ${1} operation for path: ${2}"
	repos="$(discover_repos "${2}")"

	if [ -z "${repos}" ]; then
		log ERROR "${2}" Failed 'No Git repositories found'
		return 2
	fi
	printf '%s\n' "${repos}" |
		while IFS= read -r repo; do
			process_repo "${1}" "${repo}"
		done
)

# run_section MODE
# Run MODE on every path its section of the config lists.
run_section() (
	section_values "${1}" path |
		while IFS= read -r path; do
			verbose INFO "Found ${1} path: ${path}"
			process_repos "${1}" "${path}"
		done
)

# run_sections
# Run every section the config defines, in the order 1.0.0 used.
run_sections() (
	for mode in PULL FETCH; do
		run_section "${mode}"
	done
)

# resolve_config FILE
# Print FILE, or FILE inside the script's directory; nothing if neither
# exists, which is how the caller learns the config is missing.
resolve_config() (
	if [ -f "${1}" ]; then
		printf '%s\n' "${1}"
		return 0
	fi
	if [ -f "${SCRIPT_DIR}/${1}" ]; then
		printf '%s\n' "${SCRIPT_DIR}/${1}"
		return 0
	fi
	return 1
)

# parse_ini FILE
# Print FILE as a normalized "section<TAB>key<TAB>value" stream. A bare
# absolute path becomes "SECTION<TAB>path<TAB>value", as 1.0.0 read it.
parse_ini() (
	awk '
	# kcov-exclude-start: awk source, not shell lines
	/^[[:space:]]*[;#]/ { next }
	/^[[:space:]]*$/ { next }
	/^[[:space:]]*\[/ {
		section = $0
		sub(/^[[:space:]]*\[/, "", section)
		sub(/\].*$/, "", section)
		section = toupper(section)
		next
	}
	section == "" { next }
	{
		eq = index($0, "=")
		key = "path"
		value = $0
		if (eq > 0) {
			key = substr($0, 1, eq - 1)
			value = substr($0, eq + 1)
		}
		sub(/^[[:space:]]+/, "", key)
		sub(/[[:space:]]+$/, "", key)
		sub(/^[[:space:]]+/, "", value)
		sub(/[[:space:]]+$/, "", value)
		if (value == "")
			next
		if (eq <= 0 && substr(value, 1, 1) != "/")
			next
		printf "%s\t%s\t%s\n", section, tolower(key), value
	}
	# kcov-exclude-stop
	' <"${1}"
)

# section_values SECTION KEY
# Print the values KEY holds in SECTION, one per line, in file order.
# Reads the stream parse_ini built, never the INI file (CLAUDE.md 3.4).
section_values() (
	printf '%s\n' "${INI_STREAM}" |
		awk -F '\t' -v section="${1}" -v key="${2}" \
			'$1 == section && $2 == key { print $3 }'
)

# apply_settings
# Set LOG_FORMAT from [SETTINGS]; an unknown value stays TXT.
# Mutates global state on purpose (CLAUDE.md 3.2).
apply_settings() {
	# awk takes the first word, so "JSON  # a comment" still reads as
	# JSON, the way 1.0.0's regexp did.
	format="$(section_values SETTINGS log_format | head -n 1 |
		awk '{ print $1 }')"
	format="$(printf '%s' "${format}" | tr '[:lower:]' '[:upper:]')"
	case "${format}" in
	TXT | JSON)
		LOG_FORMAT="${format}"
		;;
	*)
		# Anything else, the empty string included, stays TXT.
		;;
	esac
}

# lock_path CONFIG
# Print the lock directory for CONFIG, under ${TMPDIR:-/tmp}.
lock_path() (
	sum="$(printf '%s' "${1}" | cksum)"

	printf '%s/%s-%s.lock\n' "${TMPDIR:-/tmp}" "${PROGRAM_NAME}" \
		"${sum%% *}"
)

# lock_is_stale PATH
# Returns 0 when PATH's owning process is gone or left no pid behind.
lock_is_stale() (
	pid="$(cat -- "${1}/pid" 2>/dev/null)"

	if [ -z "${pid}" ]; then
		return 0
	fi
	if kill -0 "${pid}" 2>/dev/null; then
		return 1
	fi
	return 0
)

# lock_acquire PATH
# Take PATH as a lock directory, reclaiming it from a dead run.
# Returns 0 taken, 3 held by a live run.
lock_acquire() (
	if mkdir -- "${1}" 2>/dev/null; then
		printf '%s\n' "$$" >"${1}/pid"
		return 0
	fi
	if ! lock_is_stale "${1}"; then
		return "${EXIT_LOCKED}"
	fi
	warn "reclaiming the stale lock ${1}"
	rm -f -- "${1}/pid"
	lock_reclaim "${1}"
)

# lock_reclaim PATH
# Replace the stale lock directory PATH with one owned by this run.
lock_reclaim() (
	rmdir -- "${1}" 2>/dev/null
	if ! mkdir -- "${1}" 2>/dev/null; then
		return "${EXIT_LOCKED}"
	fi
	printf '%s\n' "$$" >"${1}/pid"
)

# lock_release PATH
# Remove the lock directory PATH; safe when it is already gone.
lock_release() (
	if [ -z "${1}" ]; then
		return 0
	fi
	rm -f -- "${1}/pid"
	rmdir -- "${1}" 2>/dev/null
	return 0
)

# set_option FLAG VALUE
# Apply FLAG; VALUE belongs to it when the flag takes one.
# Mutates global state on purpose (CLAUDE.md 3.2).
set_option() {
	case "${1}" in
	--config)
		if [ -z "${2}" ]; then
			die "${EXIT_USAGE}" "${1} needs a file"
		fi
		CONFIG_FILE="${2}"
		;;
	--log-file)
		if [ -z "${2}" ]; then
			die "${EXIT_USAGE}" "${1} needs a file"
		fi
		LOG_FILE="${2}"
		;;
	--dry-run)
		DRY_RUN=yes
		;;
	--verbose | -v)
		VERBOSE=yes
		;;
	*)
		die "${EXIT_USAGE}" "unknown option: ${1}"
		;;
	esac
}

# parse_args ARGS...
# Set CONFIG_FILE, DRY_RUN, LOG_FILE and VERBOSE from ARGS.
# Mutates global state on purpose; the name is fixed by CLAUDE.md 4.
parse_args() {
	while [ "$#" -gt 0 ]; do
		case "${1}" in
		--help)
			usage
			exit "${EXIT_OK}"
			;;
		--version)
			printf '%s\n' "${VERSION}"
			exit "${EXIT_OK}"
			;;
		--config | --log-file)
			set_option "${1}" "${2:-}"
			shift 2
			;;
		--dry-run | --verbose | -v)
			set_option "${1}" ''
			shift
			;;
		*)
			warn "unknown option: ${1}"
			usage >&2
			exit "${EXIT_USAGE}"
			;;
		esac
	done
}

# main ARGS...
# Parse the arguments and the config, take the lock, run every section.
# A no-op when AUTOGIT_LIB=1, so tests can source this file.
main() {
	if [ "${AUTOGIT_LIB:-0}" = 1 ]; then
		return 0
	fi
	parse_args "$@"
	SCRIPT_DIR="$(script_directory)"
	config_file="$(resolve_config "${CONFIG_FILE}")"
	if [ -z "${config_file}" ]; then
		die "${EXIT_USAGE}" "configuration file not found: ${CONFIG_FILE}"
	fi
	CONFIG_FILE="$(absolute_path "${config_file}")"
	verbose INFO "Using configuration file: ${CONFIG_FILE}"
	INI_STREAM="$(parse_ini "${CONFIG_FILE}")"
	apply_settings
	TIMEOUT_CMD="$(command -v timeout 2>/dev/null)"
	if [ -z "${TIMEOUT_CMD}" ]; then
		warn 'timeout(1) not found: a git call can hang'
	fi
	LOCK_PATH="$(lock_path "${CONFIG_FILE}")"
	if ! lock_acquire "${LOCK_PATH}"; then
		die "${EXIT_LOCKED}" "another run holds ${LOCK_PATH}"
	fi
	trap 'lock_release "${LOCK_PATH}"' EXIT HUP INT TERM
	run_sections
	lock_release "${LOCK_PATH}"
	return "${EXIT_OK}"
}

main "$@"
