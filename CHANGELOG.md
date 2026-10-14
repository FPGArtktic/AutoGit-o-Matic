# Changelog

All notable changes to AutoGit-o-Matic are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - unreleased

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

[2.0.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/FPGArtktic/AutoGit-o-Matic/releases/tag/v1.0.0
