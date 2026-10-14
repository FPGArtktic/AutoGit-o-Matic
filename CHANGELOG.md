# Changelog

All notable changes to AutoGit-o-Matic are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.4.0] - 2026-10-14

### Added

- `[BUNDLE]`: one `git bundle` per repository into `bundle_dir`,
  carrying only what the repository gained since its last bundle. What
  has been exported is recorded in `$GIT_DIR/autogit/bundle-tips`,
  inside the repository it describes, so no state outside it has to be
  kept in step. Beside the bundles is a `SHA256SUMS` manifest; without
  `sha256sum` installed the bundle is still written and the log line
  says the manifest was skipped. A bundle's name carries a checksum of
  the refs as well as the time, because two bundles written in the same
  second would otherwise land on one file and an increment would be
  lost.
- `on_change`: a command run once for every repository whose refs
  moved, with `AUTOGIT_MODE` and `AUTOGIT_REPO` in its environment and
  its output on stderr. A hook that fails logs a `WARN`; it cannot fail
  an operation that already succeeded. A repository overrides it with
  `git config autogit.on-change`.
- `--status`: a report of what every configured repository looks like —
  mode, path, branch, how far it is from its upstream, whether the work
  tree is dirty. It writes nothing and takes no lock, so it can be run
  while a scheduled run is going.
- `--self-check`: what this machine can do, from git's version against
  the 2.20 minimum to which optional tools are installed. Needs no
  configuration file.
- `source =` as a spelling of `path =` in every section. A mirror's
  value is as often a URL as a directory, and `path` read wrongly
  there. `path =` keeps working everywhere.
- `contrib/systemd/autogit-o-matic.service` and `.timer`, and
  `contrib/cron.example`.

## [2.3.0] - 2026-10-14

### Added

- `[MIRROR]`: `git clone --mirror` into `mirror_dir` the first time a
  source is seen, `git remote update --prune` after that, so refs
  deleted upstream disappear from the mirror too. The section takes
  sources rather than local paths, which is why `section_targets`
  exists: a mirror source need not be a repository on this machine,
  and discovery has nothing to walk.
- Recursive submodule mirroring. The `url` entries in a mirror's
  `HEAD:.gitmodules` are mirrored the same way, five levels deep at
  most so that a cycle cannot spin forever. A relative URL such as
  `../shared.git` resolves against the source it came from, the way
  git resolves it.
- `fsck = yes` and `verify_tags = yes` in `[DEFAULTS]`, which run
  `git fsck --connectivity-only` and verify the signed tags of a
  mirror after each update. An unsigned tag is not a failure.

## [2.2.0] - 2026-10-14

### Added

- A summary line at the end of every run:
  `updated=N unchanged=N skipped=N failed=N duration=Ns`. Under
  `log_format = JSON` it is its own record, `"type":"SUMMARY"`, with
  integer fields. `updated` and `unchanged` are told apart by a
  checksum of the repository's refs taken before and after the
  operation, so the count means the same thing for every mode.
- `--quiet`, which keeps everything but `ERROR` off stdout. A
  `--log-file` still receives every line, including the summary.
- `--strict-exit` and `exit_on_failure = yes` in `[SETTINGS]`, which
  make a failed repository exit `2`. That becomes the default in
  3.0.0; until then a run that fails without the opt-in prints one
  `WARN` on stderr saying so, which is the deprecation path section
  2.2 of CLAUDE.md asks for.

- `[DEFAULTS]`, holding `exclude`, `max_depth`, `ssh_key` and
  `timeout` for every repository in the run. A repository overrides
  `ssh_key` and `timeout` for itself through `git config
  autogit.ssh-key` and `autogit.timeout`; git forbids an underscore in
  a configuration key, so the INI spelling keeps the underscore and
  the repository's own configuration uses a dash.
- `exclude` globs, applied to every discovered path, and `max_depth`,
  which decides how far below a configured path discovery looks. The
  default stays one level, which is what 1.0.0 did.
- `--jobs N`, which works on N repositories at a time in batches. The
  repository loop is fed by a here-document rather than a pipeline,
  because a pipeline puts the jobs in a subshell that `wait` cannot
  see.

### Fixed

- The lock directory is emptied before it is removed. It now holds the
  run's tally as well as its pid, and `rmdir` refuses a directory that
  still has a file in it, so without this a second run would have
  found the lock of the first one and exited `3` forever.

## [2.1.0] - 2026-10-14

### Added

- `[SILENT_UPDATE]`: fetch a repository, then move every branch that
  tracks a remote and is strictly behind it with `git branch -f`. A
  branch is left alone when it tracks nothing, when it has diverged or
  is ahead, and when it is checked out in the repository or in any of
  its worktrees. No work tree is ever touched and nothing is merged,
  which makes the mode safe to run from cron against clones somebody
  is working in. A bare repository is skipped with a `WARN`.
- `git_upstream`, `git_checked_out_branches` and `git_ff_branch` as
  single-purpose git primitives behind that mode.

## [2.0.0] - 2026-10-14

### Changed

- The script is **POSIX `sh`**, not Bash. It runs unchanged under `dash`,
  `bash --posix` and `busybox sh`; `#!/bin/sh` is the shebang. Arrays,
  `pushd`, `mapfile`, `${var^^}`, `[[ ]]`, here-strings and `local` are
  gone, and `shellcheck --shell=sh --severity=style --enable=all` is clean.
- `[PULL]` now runs `git pull --ff-only`, so an unattended run can no
  longer create a merge commit. A diverged branch is reported as an
  `ERROR` and left alone. **This changes 1.0.0's behaviour on purpose**:
  there is no deprecation path for the default operation of a cron job.
- `[FETCH]` now runs `git fetch --all --prune --tags`, so refs deleted
  upstream disappear locally and new tags arrive.
- A dirty work tree, or a bare repository found in a `[PULL]` section, is
  skipped with a `WARN` line instead of being handed to git.
- Every git call runs with `GIT_TERMINAL_PROMPT=0`, and under `timeout(1)`
  when it is installed. Without `timeout(1)` the run warns once.
- `[PULL]` and `[FETCH]` share one parser and one dispatch point. Adding a
  mode is one `case` arm, not a copy of the section handling.

### Added

- `--version`, printing the `VERSION=` constant that the release job
  checks against the tag.
- A lock, so overlapping cron runs cannot process the same repositories
  twice. The lock is a directory under `$TMPDIR` named after the
  configuration file's absolute path; a second run exits `3`. A lock whose
  owning process is gone is reclaimed.
- Discovery of bare mirrors and linked worktrees (a `.git` file), not just
  directories holding a `.git` directory.
- `AUTOGIT_LIB=1` makes `main` a no-op, so a test can source the script
  and exercise one function.

- `justfile`: the `lint`, `test [shell]`, `test-all`, `coverage` and
  `check` recipes. `just check` is the pre-commit gate.
- `.shellcheckrc`: pins the POSIX dialect so an editor and the lint
  gate agree on the shell being checked.
- A `bats-core` suite. `tests/helper.sh` builds bare remotes and clones
  in `$BATS_TEST_TMPDIR` and runs the script under `$AUTOGIT_SH`;
  `tests/cli.bats` and `tests/log.bats` pin the flags, INI sections and
  log line formats 1.0.0 shipped, so the POSIX rewrite cannot change
  them unnoticed.
- `.github/workflows/ci.yml`: `lint`, `test` (`sh`, `dash`,
  `bash --posix`, `busybox sh`), `coverage` and `release` jobs, each one
  calling the same `just` recipe a developer calls. Actions are pinned
  by commit SHA and tracked by Dependabot.

### Fixed

- `verbose_log` was called before it was defined, so `--verbose` printed a
  "command not found" error whenever the configuration file was found next
  to the script rather than in the working directory.
- `for path in $paths` split a configured path on every space; a
  repository under a path with a space in it was never updated.
- JSON log lines were not escaped: a `"` or a newline in a path or in
  git's output produced lines that no JSON parser would accept. One awk
  function now escapes every field, and git's output is folded onto one
  line and cut to 150 characters.
- There was no lock, so two cron runs could work on one repository at once.
- Nothing stopped git from asking for credentials, and no git call was
  bounded, so a run could hang forever in cron.
- `git pull` could create a merge commit with nobody watching.
- `is_git_repository` tested `-d .git`, which misses linked worktrees and
  bare or mirror repositories.
- `[PULL]` and `[FETCH]` were two copies of the same code.

## [1.0.0] - 2025-05-28

### Added

- `[PULL]` and `[FETCH]` operations across many repositories from one
  INI file, with repository discovery one directory deep.
- `--config`, `--dry-run`, `--verbose`/`-v`, `--log-file` and `--help`.
- TXT and JSON Lines log formats, selected by `log_format` in
  `[SETTINGS]`.

[2.4.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/releases/tag/v1.0.0
