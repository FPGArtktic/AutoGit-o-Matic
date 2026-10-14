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

VERSION=2.5.0

set -u

GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

readonly PROGRAM_NAME=autogit-o-matic
# Longest piece of git output kept on one log line.
readonly OUTPUT_LIMIT=150
# Seconds one git invocation may take, when timeout(1) is installed.
readonly GIT_TIMEOUT=300
# How deep submodule mirroring follows, so a cycle cannot spin forever.
readonly MIRROR_MAX_DEPTH=5
# Exit codes (CLAUDE.md 3.5). EXIT_FAILED is opt-in until 3.0.0.
readonly EXIT_OK=0
readonly EXIT_USAGE=1
readonly EXIT_FAILED=2
readonly EXIT_LOCKED=3

CONFIG_FILE=autogit-o-matic.ini
DRY_RUN=no
LOG_FORMAT=TXT
LOG_FILE=
VERBOSE=no
QUIET=no
STRICT_EXIT=no
STATUS_ONLY=no
SUMMARY=yes
JOBS=1
START_TIME=0
TALLY_FILE=
SCRIPT_DIR=.
INI_STREAM=
LOCK_PATH=
TIMEOUT_CMD=
SHA256_CMD=

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
		  --quiet          Print only errors on stdout; a log file still gets everything
		  --jobs N         Work on N repositories at a time (default 1)
		  --strict-exit    Exit 2 when a repository fails (the default from 3.0.0)
		  --status         Report what every configured repository looks like, change nothing
		  --self-check     Report what this machine can do, then exit
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
	if [ "${QUIET}" = no ] || [ "${1}" = ERROR ]; then
		printf '%s\n' "${line}"
	fi
	if [ -n "${LOG_FILE}" ]; then
		printf '%s\n' "${line}" >>"${LOG_FILE}"
	fi
)

# run_seconds
# Print how many seconds the run has taken so far.
run_seconds() (
	now="$(date +%s 2>/dev/null)"

	if [ -z "${now}" ] || [ "${START_TIME}" -eq 0 ]; then
		printf '0\n'
		return 0
	fi
	printf '%s\n' "$((now - START_TIME))"
)

# tally_add OUTCOME
# Record one repository outcome. Short appends from parallel jobs do
# not interleave, so this stays correct under --jobs.
tally_add() (
	if [ -z "${TALLY_FILE}" ]; then
		return 0
	fi
	printf '%s\n' "${1}" >>"${TALLY_FILE}"
)

# tally_count OUTCOME
# Print how many repositories ended with OUTCOME.
tally_count() (
	if [ -z "${TALLY_FILE}" ] || [ ! -f "${TALLY_FILE}" ]; then
		printf '0\n'
		return 0
	fi
	count="$(grep -c -Fx -- "${1}" "${TALLY_FILE}")"
	printf '%s\n' "${count}"
)

# summary_json TIMESTAMP COUNTS SECONDS
# Print the summary as one JSON object, its fields read out of the
# "key=value key=value" string the text format uses.
summary_json() (
	printf '%s' "${2}" |
		awk -v stamp="${1}" -v seconds="${3}" '
		# kcov-exclude-start: awk source, not shell lines
		{
			out = "{\"timestamp\":\"" stamp "\""
			out = out ",\"type\":\"SUMMARY\""
			for (i = 1; i <= NF; i++) {
				split($i, kv, "=")
				out = out ",\"" kv[1] "\":" kv[2] + 0
			}
			print out ",\"duration\":" seconds + 0 "}"
		}
		# kcov-exclude-stop
		'
)

# log_summary
# Print the one line every run ends with (CLAUDE.md 3.5). Every field
# is an integer or a literal, so none of them needs JSON escaping.
log_summary() (
	if [ "${SUMMARY}" = no ]; then
		return 0
	fi
	now="$(timestamp)"
	seconds="$(run_seconds)"
	counts="updated=$(tally_count updated)"
	counts="${counts} unchanged=$(tally_count unchanged)"
	counts="${counts} skipped=$(tally_count skipped)"
	counts="${counts} failed=$(tally_count failed)"

	if [ "${LOG_FORMAT}" = JSON ]; then
		line="$(summary_json "${now}" "${counts}" "${seconds}")"
	else
		line="[${now}] SUMMARY: ${counts} duration=${seconds}s"
	fi
	if [ "${QUIET}" = no ]; then
		printf '%s\n' "${line}"
	fi
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

# git_config_value REPO KEY
# Print autogit.KEY from REPO's own configuration; nothing if unset.
# A git config key cannot hold an underscore, so ssh_key reads as
# autogit.ssh-key there while the INI keeps one spelling.
git_config_value() (
	name="$(printf '%s' "${2}" | tr '_' '-')"

	git -C "${1}" config --get "autogit.${name}" 2>/dev/null
)

# option_value KEY REPO
# Print KEY for REPO: the repository's own autogit.KEY wins over
# [DEFAULTS], which wins over nothing at all (CLAUDE.md 3.3).
option_value() (
	value="$(git_config_value "${2}" "${1}")"

	if [ -n "${value}" ]; then
		printf '%s\n' "${value}"
		return 0
	fi
	section_values DEFAULTS "${1}" | head -n 1
)

# match_any PATH GLOBS
# Returns 0 when PATH matches one of the comma-separated GLOBS.
match_any() (
	rest="${2}"

	while [ -n "${rest}" ]; do
		glob="${rest%%,*}"
		rest="${rest#"${glob}"}"
		rest="${rest#,}"
		# Unquoted on purpose: ${glob} is a pattern, not a literal.
		# shellcheck disable=SC2254
		case "${1}" in
		${glob})
			return 0
			;;
		*)
			# No match; the next glob gets its turn.
			;;
		esac
	done
	return 1
)

# excluded PATH
# Returns 0 when an exclude glob in [DEFAULTS] covers PATH.
excluded() (
	globs="$(section_values DEFAULTS exclude | head -n 1)"

	if [ -z "${globs}" ]; then
		return 1
	fi
	match_any "${1}" "${globs}"
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

# repo_ssh_command REPO
# Print the GIT_SSH_COMMAND an ssh_key asks for; nothing without one.
repo_ssh_command() (
	key="$(option_value ssh_key "${1}")"

	if [ -z "${key}" ]; then
		return 0
	fi
	printf 'ssh -i %s -o IdentitiesOnly=yes\n' "${key}"
)

# repo_timeout REPO
# Print how many seconds one git call may take for REPO.
repo_timeout() (
	seconds="$(option_value timeout "${1}")"

	case "${seconds}" in
	'' | *[!0-9]*)
		printf '%s\n' "${GIT_TIMEOUT}"
		;;
	*)
		printf '%s\n' "${seconds}"
		;;
	esac
)

# git_run PATH ARGS...
# Run git ARGS inside PATH, under timeout(1) when it exists, with the
# ssh key and the timeout that PATH asks for. Returns git's status.
git_run() (
	path="${1}"
	shift
	ssh_command="$(repo_ssh_command "${path}")"
	seconds="$(repo_timeout "${path}")"

	if [ -n "${ssh_command}" ]; then
		GIT_SSH_COMMAND="${ssh_command}"
		export GIT_SSH_COMMAND
	fi
	cd -- "${path}" || return 1
	if [ -n "${TIMEOUT_CMD}" ]; then
		"${TIMEOUT_CMD}" "${seconds}" git "$@" 2>&1
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

# refs_fingerprint REPO
# Print a checksum of every ref in REPO, so a mode's effect can be told
# from no effect without knowing what the mode does.
refs_fingerprint() (
	git -C "${1}" for-each-ref --format='%(objectname) %(refname)' \
		2>/dev/null | cksum
)

# git_upstream REPO BRANCH
# Print the ref BRANCH tracks in REPO; nothing when it tracks none.
git_upstream() (
	git -C "${1}" rev-parse --symbolic-full-name --verify \
		"${2}@{upstream}" 2>/dev/null
)

# git_checked_out_branches REPO
# Print every branch checked out in REPO or in one of its worktrees.
git_checked_out_branches() (
	git -C "${1}" worktree list --porcelain |
		awk '/^branch / { sub(/^branch refs\/heads\//, ""); print }'
)

# git_ff_branch REPO BRANCH UPSTREAM
# Move BRANCH to UPSTREAM if that is a fast-forward; never checks out.
# Returns 0 moved, 1 nothing to do or not a fast-forward, 2 git error.
git_ff_branch() (
	from="$(git -C "${1}" rev-parse --verify "${2}" 2>/dev/null)"
	to="$(git -C "${1}" rev-parse --verify "${3}" 2>/dev/null)"

	if [ -z "${from}" ] || [ "${from}" = "${to}" ]; then
		return 1
	fi
	if ! git -C "${1}" merge-base --is-ancestor "${2}" "${3}"; then
		return 1
	fi
	if git_run "${1}" branch -f "${2}" "${3}" >/dev/null; then
		return 0
	fi
	return 2
)

# git_clone_mirror SOURCE DEST
# Clone SOURCE into DEST as a mirror.
git_clone_mirror() (
	parent="${2%/*}"

	mkdir -p -- "${parent}" || return 1
	git_run "${parent}" clone --mirror -- "${1}" "${2}"
)

# git_remote_update DEST
# Update every remote of the mirror DEST, pruning refs that are gone.
git_remote_update() (
	git_run "${1}" remote update --prune
)

# git_submodule_urls REPO
# Print the submodule URLs recorded in REPO's HEAD .gitmodules.
git_submodule_urls() (
	git -C "${1}" show HEAD:.gitmodules 2>/dev/null |
		awk '$1 == "url" { print $3 }'
)

# git_fsck REPO
# Check REPO's object graph without reading every object.
git_fsck() (
	git_run "${1}" fsck --connectivity-only
)

# git_dir REPO
# Print REPO's git directory as an absolute path.
git_dir() (
	git -C "${1}" rev-parse --absolute-git-dir 2>/dev/null
)

# git_ref_list REPO
# Print every ref in REPO as "objectname refname".
git_ref_list() (
	git -C "${1}" for-each-ref --format='%(objectname) %(refname)' \
		2>/dev/null
)

# git_bundle_create REPO FILE EXCLUDES...
# Bundle every ref in REPO except what the ^objectname EXCLUDES cover.
git_bundle_create() (
	repo="${1}"
	file="${2}"
	shift 2

	git_run "${repo}" bundle create "${file}" --all "$@"
)

# discovery_depth
# Print how deep discovery may go: max_depth in [DEFAULTS], else 1.
discovery_depth() (
	depth="$(section_values DEFAULTS max_depth | head -n 1)"

	case "${depth}" in
	'' | *[!0-9]*)
		printf '1\n'
		;;
	*)
		printf '%s\n' "${depth}"
		;;
	esac
)

# emit_repo PATH
# Print PATH unless an exclude glob covers it.
emit_repo() (
	if excluded "${1}"; then
		return 0
	fi
	printf '%s\n' "${1}"
)

# discover_in DIR DEPTH
# Print the repositories at DIR, descending while DEPTH is left.
discover_in() (
	if git_is_repo "${1}"; then
		emit_repo "${1}"
		return 0
	fi
	if [ "${2}" -le 0 ]; then
		return 0
	fi
	for entry in "${1}"/*; do
		if [ -d "${entry}" ]; then
			discover_in "${entry}" "$((${2} - 1))"
		fi
	done
)

# discover_repos PATH
# Print every repository at PATH or below it, one per line. Work trees,
# linked worktrees and bare mirrors all come out the same.
discover_repos() (
	base="${1%/}"
	depth="$(discovery_depth)"

	if [ -z "${base}" ]; then
		base=/
	fi
	discover_in "${base}" "${depth}"
)

# state_dir REPO
# Print REPO's private state directory, creating it on the way. Private
# state lives inside the repository it describes (CLAUDE.md 3.3).
state_dir() (
	dir="$(git_dir "${1}")"

	if [ -z "${dir}" ]; then
		return 1
	fi
	mkdir -p -- "${dir}/autogit" || return 1
	printf '%s/autogit\n' "${dir}"
)

# bundle_tips REPO
# Print the refs REPO's last bundle covered; nothing before the first.
bundle_tips() (
	dir="$(state_dir "${1}")"

	if [ -z "${dir}" ] || [ ! -f "${dir}/bundle-tips" ]; then
		return 0
	fi
	cat -- "${dir}/bundle-tips"
)

# write_bundle_tips REPO
# Record REPO's refs as the point the next bundle starts from.
write_bundle_tips() (
	dir="$(state_dir "${1}")"

	if [ -z "${dir}" ]; then
		return 1
	fi
	git_ref_list "${1}" >"${dir}/bundle-tips"
)

# bundle_is_current REPO
# Returns 0 when REPO's refs are exactly what the last bundle covered.
bundle_is_current() (
	now="$(git_ref_list "${1}")"
	last="$(bundle_tips "${1}")"

	[ "${now}" = "${last}" ]
)

# bundle_excludes REPO
# Print a ^objectname line for every ref the last bundle covered.
bundle_excludes() (
	bundle_tips "${1}" | awk '{ print "^" $1 }'
)

# bundle_file REPO DIR
# Print the path of the bundle to write for REPO under DIR. The name
# carries a checksum of the refs as well as the time, because two
# bundles written in the same second would otherwise collide and the
# older increment would be lost.
bundle_file() (
	stamp="$(date '+%Y%m%d%H%M%S')"
	sum="$(git_ref_list "${1}" | cksum)"
	source="${1%/}"
	name="${source##*/}"

	printf '%s/%s-%s-%s.bundle\n' "${2%/}" "${name%.git}" "${stamp}" \
		"${sum%% *}"
)

# bundle_manifest FILE
# Append FILE's checksum to the SHA256SUMS beside it, when sha256sum is
# installed. Prints what the repository ended up producing.
bundle_manifest() (
	name="${1##*/}"
	dir="${1%/*}"

	if [ -z "${SHA256_CMD}" ]; then
		printf 'bundled %s, no sha256sum for the manifest\n' "${name}"
		return 0
	fi
	(cd -- "${dir}" && "${SHA256_CMD}" -- "${name}" >>SHA256SUMS) ||
		return 2
	printf 'bundled %s\n' "${name}"
)

# bundle_write REPO DIR
# Bundle what REPO gained since its last bundle into DIR.
# Returns 0 done, 2 git error; prints what happened.
bundle_write() (
	repo="${1}"
	dir="${2}"

	if bundle_is_current "${repo}"; then
		printf 'nothing new to bundle\n'
		return 0
	fi
	file="$(bundle_file "${repo}" "${dir}")"
	excludes="$(bundle_excludes "${repo}")"

	# set -- replaces the positional parameters, so the arguments are
	# held by name first. Deliberate word splitting: every item is
	# ^<objectname>, which holds neither a space nor a glob character.
	# shellcheck disable=SC2086
	set -- ${excludes}
	if ! output="$(git_bundle_create "${repo}" "${file}" "$@")"; then
		printf '%s\n' "${output}"
		return 2
	fi
	write_bundle_tips "${repo}"
	bundle_manifest "${file}"
)

# do_bundle REPO
# Write an incremental bundle of REPO for carrying elsewhere.
# Returns 0 done, 1 skipped, 2 git error.
do_bundle() (
	dir="$(option_value bundle_dir "${1}")"

	if [ -z "${dir}" ]; then
		printf 'no bundle_dir is configured\n'
		return 1
	fi
	mkdir -p -- "${dir}" || return 2
	bundle_write "${1}" "${dir}"
)

# yes_option KEY REPO
# Returns 0 when KEY reads as a yes for REPO.
yes_option() (
	value="$(option_value "${1}" "${2}")"

	case "${value}" in
	yes | YES | Yes | true | 1)
		return 0
		;;
	*)
		return 1
		;;
	esac
)

# mirror_target SOURCE
# Print where SOURCE is mirrored: mirror_dir plus the repository name.
# Prints nothing when no mirror_dir is configured.
mirror_target() (
	root="$(section_values DEFAULTS mirror_dir | head -n 1)"
	source="${1%/}"

	if [ -z "${root}" ]; then
		return 0
	fi
	name="${source##*/}"
	printf '%s/%s.git\n' "${root%/}" "${name%.git}"
)

# resolve_url BASE URL
# Print URL with any leading ./ or ../ resolved against BASE, which is
# how git reads a relative submodule URL.
resolve_url() (
	base="${1%/}"
	rest="${2}"

	while :; do
		case "${rest}" in
		./*)
			rest="${rest#./}"
			;;
		../*)
			base="${base%/*}"
			rest="${rest#../}"
			;;
		*)
			break
			;;
		esac
	done
	if [ "${rest}" = "${2}" ]; then
		printf '%s\n' "${2}"
		return 0
	fi
	printf '%s/%s\n' "${base}" "${rest}"
)

# mirror_sync SOURCE DEST
# Clone SOURCE into DEST the first time, update DEST after that.
mirror_sync() (
	if [ ! -d "${2}" ]; then
		git_clone_mirror "${1}" "${2}"
		return "$?"
	fi
	git_remote_update "${2}"
)

# tag_is_signed REPO TAG
# Returns 0 when TAG is an annotated tag that carries a signature.
tag_is_signed() (
	git -C "${1}" cat-file tag "${2}" 2>/dev/null |
		grep -q 'BEGIN PGP SIGNATURE'
)

# verify_tags REPO
# Verify every signed tag in REPO. Returns 2 when one does not verify.
verify_tags() (
	tags="$(git -C "${1}" for-each-ref --format='%(refname:short)' \
		refs/tags)"

	while IFS= read -r tag; do
		verify_one_tag "${1}" "${tag}" || return 2
	done <<-EOF
		${tags}
	EOF
)

# verify_one_tag REPO TAG
# Verify TAG when it is signed; an unsigned tag is nothing to check.
verify_one_tag() (
	if [ -z "${2}" ]; then
		return 0
	fi
	if ! tag_is_signed "${1}" "${2}"; then
		return 0
	fi
	git -C "${1}" verify-tag "${2}" >/dev/null 2>&1
)

# mirror_checks DEST
# Run the optional integrity checks DEST asks for.
# Returns 0 fine, 2 when a check failed.
mirror_checks() (
	if yes_option fsck "${1}"; then
		git_fsck "${1}" >/dev/null || return 2
	fi
	if yes_option verify_tags "${1}"; then
		verify_tags "${1}" || return 2
	fi
	return 0
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

# ff_branch_safe REPO BRANCH CHECKED_OUT
# Fast-forward BRANCH unless it tracks nothing or appears in the
# newline-separated CHECKED_OUT. Returns git_ff_branch's status.
ff_branch_safe() (
	upstream="$(git_upstream "${1}" "${2}")"

	if [ -z "${upstream}" ]; then
		return 1
	fi
	if printf '%s\n' "${3}" | grep -Fqx -- "${2}"; then
		return 1
	fi
	git_ff_branch "${1}" "${2}" "${upstream}"
)

# ff_branches REPO
# Print the name of every branch of REPO that was fast-forwarded.
ff_branches() (
	checked_out="$(git_checked_out_branches "${1}")"

	git -C "${1}" for-each-ref --format='%(refname:short)' refs/heads |
		while IFS= read -r branch; do
			if ff_branch_safe "${1}" "${branch}" "${checked_out}"; then
				printf '%s\n' "${branch}"
			fi
		done
)

# do_silent_update REPO
# Fetch REPO, then fast-forward the branches nobody has checked out.
# Returns 0 done, 1 skipped, 2 git error; prints what it did.
do_silent_update() (
	if git_is_bare "${1}"; then
		printf 'bare repository\n'
		return 1
	fi
	if ! output="$(git_fetch "${1}")"; then
		printf '%s\n' "${output}"
		return 2
	fi
	moved="$(ff_branches "${1}" | tr '\n' ' ')"
	if [ -z "${moved}" ]; then
		printf 'nothing to fast-forward\n'
		return 0
	fi
	printf 'moved: %s\n' "${moved% }"
)

# dry_run_message MODE
# Print the message a dry run logs for MODE.
dry_run_message() (
	case "${1}" in
	SILENT_UPDATE)
		printf 'Would fetch and fast-forward what is safe\n'
		;;
	MIRROR)
		printf 'Would clone or update the mirror\n'
		;;
	BUNDLE)
		printf 'Would write a bundle of what is new\n'
		;;
	*)
		verb="$(mode_verb "${1}")"
		printf "Would execute 'git %s'\n" "${verb}"
		;;
	esac
)

# mirror_one_url SOURCE URL DEPTH
# Mirror URL, which may be relative to SOURCE, one level deeper.
mirror_one_url() (
	if [ -z "${2}" ]; then
		return 0
	fi
	resolved="$(resolve_url "${1}" "${2}")"

	do_mirror "${resolved}" "$((${3} + 1))" >/dev/null
)

# mirror_url_list SOURCE URLS DEPTH
# Mirror each of the newline-separated URLS, the relative ones against
# SOURCE. Prints how many submodules came along.
mirror_url_list() (
	count=0

	while IFS= read -r url; do
		mirror_one_url "${1}" "${url}" "${3}" || return 2
		count="$((count + 1))"
	done <<-EOF
		${2}
	EOF
	printf 'mirrored with %s submodule(s)\n' "${count}"
)

# mirror_submodules SOURCE DEST DEPTH
# Mirror every submodule DEST records, stopping at MIRROR_MAX_DEPTH so
# that a cycle in .gitmodules cannot spin forever.
mirror_submodules() (
	urls="$(git_submodule_urls "${2}")"

	if [ -z "${urls}" ] || [ "${3}" -ge "${MIRROR_MAX_DEPTH}" ]; then
		printf 'mirrored\n'
		return 0
	fi
	mirror_url_list "${1}" "${urls}" "${3}"
)

# do_mirror SOURCE [DEPTH]
# Clone or update the mirror of SOURCE under mirror_dir, then its
# submodules. Returns 0 done, 1 skipped, 2 git error.
do_mirror() (
	dest="$(mirror_target "${1}")"
	depth="${2:-0}"

	if [ -z "${dest}" ]; then
		printf 'no mirror_dir is configured\n'
		return 1
	fi
	if ! output="$(mirror_sync "${1}" "${dest}")"; then
		printf '%s\n' "${output}"
		return 2
	fi
	if ! mirror_checks "${dest}"; then
		printf 'integrity check failed\n'
		return 2
	fi
	mirror_submodules "${1}" "${dest}" "${depth}"
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
	SILENT_UPDATE)
		do_silent_update "${2}"
		;;
	MIRROR)
		do_mirror "${2}"
		;;
	BUNDLE)
		do_bundle "${2}"
		;;
	*)
		printf 'unknown mode: %s\n' "${1}"
		return 2
		;;
	esac
)

# section_targets MODE PATH
# Print what MODE works on for PATH: every repository discovered under
# it, or, for MIRROR, the source itself, which need not exist here yet.
section_targets() (
	case "${1}" in
	MIRROR)
		printf '%s\n' "${2}"
		;;
	*)
		discover_repos "${2}"
		;;
	esac
)

# fingerprint_target MODE TARGET
# Print the checksum that shows MODE's effect on TARGET. For MIRROR the
# effect lands in the mirror, and for BUNDLE in the exported tips - a
# repository's own refs do not move when it is bundled.
fingerprint_target() (
	case "${1}" in
	MIRROR)
		dest="$(mirror_target "${2}")"
		refs_fingerprint "${dest}"
		;;
	BUNDLE)
		bundle_tips "${2}" | cksum
		;;
	*)
		refs_fingerprint "${2}"
		;;
	esac
)

# report_success MODE REPO BEFORE OUTPUT
# Log a successful MODE on REPO and tally it by whether BEFORE still
# describes its refs.
report_success() (
	after="$(fingerprint_target "${1}" "${2}")"

	log "${1}" "${2}" Success "${4}"
	if [ "${3}" = "${after}" ]; then
		tally_add unchanged
		return 0
	fi
	tally_add updated
	run_on_change "${1}" "${2}"
)

# hook_run COMMAND
# Run COMMAND through sh, bounded by timeout(1) when it is installed.
hook_run() (
	if [ -n "${TIMEOUT_CMD}" ]; then
		"${TIMEOUT_CMD}" "${GIT_TIMEOUT}" sh -c "${1}"
		return "$?"
	fi
	sh -c "${1}"
)

# run_on_change MODE REPO
# Run REPO's on_change command with AUTOGIT_MODE and AUTOGIT_REPO in
# its environment. A hook that fails warns; it cannot fail a run that
# has already succeeded. Its output goes to stderr, so that it cannot
# land in the middle of the log stream.
run_on_change() (
	command_line="$(option_value on_change "${2}")"

	if [ -z "${command_line}" ]; then
		return 0
	fi
	AUTOGIT_MODE="${1}"
	AUTOGIT_REPO="${2}"
	export AUTOGIT_MODE AUTOGIT_REPO
	if hook_run "${command_line}" >&2; then
		return 0
	fi
	warn "on_change failed for ${2}"
)

# process_repo MODE REPO
# Run MODE on REPO, log one line about it, tally the outcome.
# Returns 0 done, 1 skipped, 2 failed.
process_repo() (
	verb="$(mode_verb "${1}")"

	if [ "${DRY_RUN}" = yes ]; then
		message="$(dry_run_message "${1}")"
		log "${1}" "${2}" 'Success (Dry Run)' "${message}"
		tally_add unchanged
		return 0
	fi
	before="$(fingerprint_target "${1}" "${2}")"
	output="$(run_mode "${1}" "${2}")"
	result="$?"
	if [ "${result}" -eq 0 ]; then
		report_success "${1}" "${2}" "${before}" "${output}"
		return 0
	fi
	if [ "${result}" -eq 1 ]; then
		log WARN "${2}" Skipped "${output}"
		tally_add skipped
		return 1
	fi
	log ERROR "${2}" Failed "Failed to execute git ${verb}: ${output}"
	tally_add failed
	return 2
)

# run_batch MODE REPOS
# Run MODE on each of the newline-separated REPOS, ${JOBS} at a time.
# The loop is fed by a here-document rather than a pipeline, because a
# pipeline would put the jobs in a subshell that wait(1) cannot see.
run_batch() (
	running=0

	while IFS= read -r repo; do
		process_repo "${1}" "${repo}" &
		running="$((running + 1))"
		if [ "${running}" -ge "${JOBS}" ]; then
			wait
			running=0
		fi
	done <<-EOF
		${2}
	EOF
	wait
)

# process_repos MODE PATH
# Run MODE on every repository discovered under PATH, ${JOBS} at once.
process_repos() (
	verbose INFO "Processing ${1} operation for path: ${2}"
	repos="$(section_targets "${1}" "${2}")"

	if [ -z "${repos}" ]; then
		log ERROR "${2}" Failed 'No Git repositories found'
		tally_add failed
		return 2
	fi
	run_batch "${1}" "${repos}"
)

# run_section MODE
# Run MODE on every path its section of the config lists.
run_section() (
	section_entries "${1}" |
		while IFS= read -r path; do
			verbose INFO "Found ${1} path: ${path}"
			process_repos "${1}" "${path}"
		done
)

# run_sections
# Run every section the config defines, in the order 1.0.0 used.
run_sections() (
	for mode in PULL FETCH SILENT_UPDATE MIRROR BUNDLE; do
		run_section "${mode}"
	done
)

# git_current_branch REPO
# Print REPO's checked out branch; nothing when detached or bare.
git_current_branch() (
	git -C "${1}" symbolic-ref --short -q HEAD 2>/dev/null
)

# git_ahead_behind REPO BRANCH
# Print "ahead=N behind=N" for BRANCH against its upstream, or dashes
# when it tracks nothing.
git_ahead_behind() (
	upstream="$(git_upstream "${1}" "${2}")"

	if [ -z "${upstream}" ]; then
		printf 'ahead=- behind=-\n'
		return 0
	fi
	counts="$(git -C "${1}" rev-list --left-right --count \
		"${2}...${upstream}" 2>/dev/null)"
	printf 'ahead=%s behind=%s\n' "${counts%%	*}" \
		"${counts##*	}"
)

# status_line MODE REPO
# Print one tab-separated record about REPO: nothing for a path that is
# not a repository.
status_line() (
	if [ -z "${2}" ] || ! git_is_repo "${2}"; then
		return 0
	fi
	branch="$(git_current_branch "${2}")"
	counts="$(git_ahead_behind "${2}" "${branch}")"
	dirty=no

	if git_dirty "${2}"; then
		dirty=yes
	fi
	printf '%s\t%s\t%s\t%s\tdirty=%s\n' "${1}" "${2}" \
		"${branch:--}" "${counts}" "${dirty}"
)

# status_paths MODE PATH
# Print a status record for every repository MODE would work on at PATH.
status_paths() (
	targets="$(section_targets "${1}" "${2}")"

	while IFS= read -r repo; do
		status_line "${1}" "${repo}"
	done <<-EOF
		${targets}
	EOF
)

# status_section MODE
# Print the status of every path MODE's section lists.
status_section() (
	section_entries "${1}" |
		while IFS= read -r path; do
			status_paths "${1}" "${path}"
		done
)

# status_report
# Report what every configured repository looks like, changing nothing.
status_report() (
	for mode in PULL FETCH SILENT_UPDATE MIRROR BUNDLE; do
		status_section "${mode}"
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

# section_entries SECTION
# Print what SECTION lists. "path" is the spelling 1.0.0 used and it
# keeps working; "source" means exactly the same and reads better for a
# mirror, whose value is a URL as often as a path.
section_entries() (
	section_values "${1}" path
	section_values "${1}" source
)

# section_values SECTION KEY
# Print the values KEY holds in SECTION, one per line, in file order.
# Reads the stream parse_ini built, never the INI file (CLAUDE.md 3.4).
section_values() (
	printf '%s\n' "${INI_STREAM}" |
		awk -F '\t' -v section="${1}" -v key="${2}" \
			'$1 == section && $2 == key { print $3 }'
)

# setting_value KEY
# Print the first word of KEY's value in [SETTINGS]; nothing if unset.
# The first word is what 1.0.0 read, so "JSON  # a comment" still works.
setting_value() (
	section_values SETTINGS "${1}" | head -n 1 | awk '{ print $1 }'
)

# set_log_format
# Set LOG_FORMAT from [SETTINGS]; an unknown value stays TXT.
# Mutates global state on purpose (CLAUDE.md 3.2).
set_log_format() {
	format="$(setting_value log_format | tr '[:lower:]' '[:upper:]')"
	case "${format}" in
	TXT | JSON)
		LOG_FORMAT="${format}"
		;;
	*)
		# Anything else, the empty string included, stays TXT.
		;;
	esac
}

# set_exit_policy
# Turn on the strict exit code when [SETTINGS] asks for it.
# Mutates global state on purpose (CLAUDE.md 3.2).
set_exit_policy() {
	case "$(setting_value exit_on_failure)" in
	yes | YES | Yes | true | 1)
		STRICT_EXIT=yes
		;;
	*)
		# Anything else leaves 2.x exiting 0 on a failed repository.
		;;
	esac
}

# set_summary_policy
# Drop the summary line when [SETTINGS] asks for that. It is the one
# line 1.0.0 did not print, so a reader that parses every line of
# stdout needs a way to say no to it.
# Mutates global state on purpose (CLAUDE.md 3.2).
set_summary_policy() {
	value="$(setting_value summary)"

	case "${value}" in
	no | NO | No | false | 0)
		SUMMARY=no
		;;
	*)
		# Anything else, the empty string included, keeps the line.
		;;
	esac
}

# apply_settings
# Apply every [SETTINGS] key. Mutates global state on purpose.
apply_settings() {
	set_log_format
	set_exit_policy
	set_summary_policy
}

# exit_code FAILED
# Print the status this run leaves with. Warns once while the strict
# code is still opt-in (CLAUDE.md 2.2).
exit_code() (
	if [ "${1}" -eq 0 ]; then
		printf '%s\n' "${EXIT_OK}"
		return 0
	fi
	if [ "${STRICT_EXIT}" = yes ]; then
		printf '%s\n' "${EXIT_FAILED}"
		return 0
	fi
	warn 'a repository failed; 3.0.0 will exit 2 (see --strict-exit)'
	printf '%s\n' "${EXIT_OK}"
)

# lock_path CONFIG
# Print the lock directory for CONFIG, under ${TMPDIR:-/tmp}.
lock_path() (
	sum="$(printf '%s' "${1}" | cksum)"

	printf '%s/%s-%s.lock\n' "${TMPDIR:-/tmp}" "${PROGRAM_NAME}" \
		"${sum%% *}"
)

# lock_empty PATH
# Remove the files a run keeps inside the lock directory PATH, so that
# rmdir can take the directory itself.
lock_empty() (
	rm -f -- "${1}/pid" "${1}/tally"
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
	lock_empty "${1}"
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
	lock_empty "${1}"
	rmdir -- "${1}" 2>/dev/null
	return 0
)

# check_tool NAME KIND
# Report whether NAME is installed. Returns 1 when a required tool is
# missing, 0 for anything optional.
check_tool() (
	path="$(command -v "${1}" 2>/dev/null)"

	if [ -n "${path}" ]; then
		printf 'ok       %-10s %s\n' "${1}" "${path}"
		return 0
	fi
	printf '%-8s %-10s not found\n' "${2}" "${1}"
	if [ "${2}" = required ]; then
		return 1
	fi
)

# check_git_version
# Report whether git is new enough for everything this script uses.
check_git_version() (
	version="$(git --version 2>/dev/null | awk '{ print $3 }')"
	rest="${version#*.}"
	major="${version%%.*}"
	minor="${rest%%.*}"

	case "${major}${minor}" in
	'' | *[!0-9]*)
		printf 'required git        version %s is unreadable\n' \
			"${version}"
		return 1
		;;
	*)
		# Both parts are numbers, so the arithmetic below is safe.
		;;
	esac
	if [ "$((major * 100 + minor))" -lt 220 ]; then
		printf 'required git        %s is older than 2.20\n' "${version}"
		return 1
	fi
	printf 'ok       git        %s\n' "${version}"
)

# check_writable PATH LABEL
# Report whether PATH can be written to; never fails the check.
check_writable() (
	if [ -w "${1}" ]; then
		printf 'ok       %-10s %s is writable\n' "${2}" "${1}"
		return 0
	fi
	printf 'warn     %-10s %s is not writable\n' "${2}" "${1}"
)

# self_check
# Report what this machine can do. Returns 1 when something the script
# cannot work without is missing.
self_check() (
	missing=0

	for tool in git awk sed tr cut date cksum grep mkdir rmdir; do
		check_tool "${tool}" required || missing=$((missing + 1))
	done
	for tool in timeout sha256sum flock; do
		check_tool "${tool}" optional || true
	done
	check_git_version || missing=$((missing + 1))
	check_writable "${TMPDIR:-/tmp}" lockdir
	printf 'version  %-10s %s\n' autogit "${VERSION}"
	if [ "${missing}" -gt 0 ]; then
		return 1
	fi
)

# is_count VALUE
# Returns 0 when VALUE is a positive decimal number.
is_count() (
	case "${1}" in
	'' | 0 | *[!0-9]*)
		return 1
		;;
	*)
		return 0
		;;
	esac
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
	--jobs)
		if ! is_count "${2}"; then
			die "${EXIT_USAGE}" "${1} needs a positive number"
		fi
		JOBS="${2}"
		;;
	--dry-run)
		DRY_RUN=yes
		;;
	--status)
		STATUS_ONLY=yes
		;;
	--quiet)
		QUIET=yes
		;;
	--strict-exit)
		STRICT_EXIT=yes
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
		--self-check)
			self_check
			exit "$?"
			;;
		--config | --log-file | --jobs)
			set_option "${1}" "${2:-}"
			shift 2
			;;
		--dry-run | --verbose | -v | --quiet | --strict-exit | --status)
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
	START_TIME="$(date +%s 2>/dev/null)"
	if [ -z "${START_TIME}" ]; then
		START_TIME=0
	fi
	SCRIPT_DIR="$(script_directory)"
	config_file="$(resolve_config "${CONFIG_FILE}")"
	if [ -z "${config_file}" ]; then
		die "${EXIT_USAGE}" "configuration file not found: ${CONFIG_FILE}"
	fi
	CONFIG_FILE="$(absolute_path "${config_file}")"
	verbose INFO "Using configuration file: ${CONFIG_FILE}"
	INI_STREAM="$(parse_ini "${CONFIG_FILE}")"
	apply_settings
	SHA256_CMD="$(command -v sha256sum 2>/dev/null)"
	TIMEOUT_CMD="$(command -v timeout 2>/dev/null)"
	if [ -z "${TIMEOUT_CMD}" ]; then
		warn 'timeout(1) not found: a git call can hang'
	fi
	if [ "${STATUS_ONLY}" = yes ]; then
		status_report
		return "${EXIT_OK}"
	fi
	LOCK_PATH="$(lock_path "${CONFIG_FILE}")"
	if ! lock_acquire "${LOCK_PATH}"; then
		die "${EXIT_LOCKED}" "another run holds ${LOCK_PATH}"
	fi
	trap 'lock_release "${LOCK_PATH}"' EXIT HUP INT TERM
	TALLY_FILE="${LOCK_PATH}/tally"
	run_sections
	failed="$(tally_count failed)"
	log_summary
	code="$(exit_code "${failed}")"
	lock_release "${LOCK_PATH}"
	return "${code}"
}

main "$@"
