# AutoGit-o-Matic

<p align="center">
  <img src="logo.jpg" alt="AutoGit-o-Matic Logo" width="500"/>
</p>

<p align="center">
  <strong>Automate Git operations across multiple repositories</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#requirements">Requirements</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#cron-setup">Cron Setup</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#development">Development</a> •
  <a href="#license">License</a>
</p>

> **Picked up again after a long quiet.** The Bash version, now tagged
> `v1.0.0`, sat untouched from May 2025. In October 2026 the project was
> taken up again: the script was rewritten in POSIX `sh`, every known
> defect of 1.0.0 was fixed and covered by a test, and it grew a test
> suite, a lint gate and CI across four shells. Four releases followed —
> `2.0.0` (the rewrite), `2.1.0` (`SILENT_UPDATE`), `2.2.0` (summary
> line, `--quiet`, `--jobs N`, `[DEFAULTS]`) and `2.3.0` (`MIRROR` with
> recursive submodules). See [CHANGELOG.md](CHANGELOG.md) for the
> details.

## Features

AutoGit-o-Matic is a single POSIX shell script that automates Git operations across multiple repositories. It helps you:

- **Pull or fetch updates** from multiple repositories with a single command
- **Scan directories** for Git repositories automatically, including bare mirrors and linked worktrees
- **Log operations** in both TXT and JSON formats
- **Dry-run** capability to simulate operations without making actual changes
- **Configurable paths** via an INI file
- **Safe unattended pulls**: `git pull --ff-only`, so a run can never leave a merge commit behind
- **Silent updates**: fast-forward branches nobody has checked out, without ever touching a work tree
- **Mirrors for air-gapped transfer**: `clone --mirror`, pruning updates, and submodules followed through `.gitmodules`
- **One run at a time** per configuration file, so overlapping cron jobs cannot collide
- **No hanging on credentials**: `GIT_TERMINAL_PROMPT=0` is always set, and each git call is bounded by `timeout(1)` when it is installed

## Requirements

- A POSIX shell (`sh`). The script is tested under `dash`, `bash --posix` and `busybox sh`.
- `git` 2.20 or newer.
- Standard POSIX utilities: `awk`, `sed`, `tr`, `cut`, `date`, `cksum`.
- Optional: `timeout(1)`. Without it the script warns once and runs unbounded git calls.

Nothing else. There is no runtime dependency on Bash, Python, or any library.

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/AutoGit-o-Matic.git
```

2. Make the script executable:
```bash
chmod +x autogit-o-matic.sh
```

3. Create your configuration file (you can copy and modify the example one):
```bash
cp autogit-o-matic.ini.example autogit-o-matic.ini
```

## Usage

Run the script with:

```bash
./autogit-o-matic.sh [OPTIONS]
```

### Options

- `--config FILE` - Path to the configuration file (default: autogit-o-matic.ini)
- `--dry-run` - Simulate operations without actually executing Git commands
- `--verbose, -v` - Display more detailed information about operations
- `--quiet` - Print only errors on stdout; a log file, if any, still gets every line
- `--jobs N` - Work on N repositories at a time (default 1)
- `--status` - Report what every configured repository looks like and change nothing
- `--self-check` - Report what this machine can do, then exit
- `--strict-exit` - Exit `2` when a repository fails; the default since 3.0.0, kept for scripts that pass it
- `--log-file FILE` - Write logs to the specified file as well as to stdout
- `--version` - Print the version and exit
- `--help` - Display help message and exit

### Exit codes

| code | meaning                                      |
|------|----------------------------------------------|
| `0`  | the run finished                             |
| `1`  | a usage or configuration error               |
| `2`  | at least one repository failed               |
| `3`  | another run holds the lock for this config   |

Code `2` is the default since 3.0.0, so a cron entry or a monitoring check
notices a repository that failed. To go back to a run that always exits `0`,
set `exit_on_failure = no` in `[SETTINGS]`. `--strict-exit` still exists and
still means exit `2`; it is simply what happens anyway.

### Summary line

Every run ends with one line counting what it did:

```
[2026-10-14 18:05:39] SUMMARY: updated=2 unchanged=1 skipped=1 failed=1 duration=4s
```

`updated` means a repository's refs changed, `unchanged` that the operation
succeeded and changed nothing, `skipped` that it was deliberately left alone
(a dirty work tree, a bare repository, a branch checked out elsewhere), and
`failed` that git or the configuration was at fault. Under `log_format = JSON`
the same line is its own record, with integer fields:

```json
{"timestamp":"2026-10-14 18:05:39","type":"SUMMARY","updated":2,"unchanged":1,"skipped":1,"failed":1,"duration":4}
```

`--quiet` suppresses the summary along with everything else that is not an
error; a `--log-file` still receives it.

The summary is the one line 1.0.0 did not print, so a reader that parses
every line of the log can be told to do without it:

```ini
[SETTINGS]
summary = no
```

That drops the line from stdout and from a log file alike. Anything other
than `no`, `false` or `0` — the empty string included — keeps it.

### Example

```bash
./autogit-o-matic.sh --verbose --log-file autogit.log
```

You can also specify the full path to the script and configuration file:

```bash
/path/to/autogit-o-matic.sh --config /path/to/autogit-o-matic.ini --log-file /path/to/log/autogit.log
```

For example:

```bash
/home/mok/git/AutoGit-o-Matic/autogit-o-matic.sh --config /home/mok/git/AutoGit-o-Matic/autogit-o-matic.ini --log-file ~/RAMDISC/autogit.log
```

**Note:** If you don't specify a configuration file with `--config`, the script will automatically look for `autogit-o-matic.ini` in the current directory. If it doesn't find it there, it will look for the config file in the same directory as the script itself.

### Locking

Only one run per configuration file can be active at a time. The lock is a
directory named after the configuration file's absolute path, created under
`$TMPDIR` (`/tmp` when `TMPDIR` is unset). A second run exits with code `3`
instead of fetching the same repositories twice. A lock left behind by a run
that was killed is reclaimed automatically once its process is gone.

## Cron Setup

To automate Git operations on a schedule, you can set up a cron job:

1. Open your crontab file:
```bash
crontab -e
```

2. Add a line to run the script at your desired schedule. For example, to run it every hour:
```
0 * * * * /path/to/autogit-o-matic.sh --log-file /path/to/autogit.log
```

3. For daily runs at 8:30 AM:
```
30 8 * * * /path/to/autogit-o-matic.sh --log-file /path/to/autogit.log
```

4. To run it every 15 minutes:
```
*/15 * * * * /path/to/autogit-o-matic.sh --log-file /path/to/autogit.log
```

Make sure to use absolute paths in your cron job to avoid any path-related issues.

## Configuration

The configuration file (`autogit-o-matic.ini`) uses an INI format:

```ini
[SETTINGS]
log_format = JSON  # Can be TXT or JSON

[PULL]
# Repositories to pull from
/home/user/git/repo1/
/home/user/git/repo2/

[FETCH]
# Repositories to fetch from
/home/user/git/repo3/
/home/user/git/repo4/
```

You can specify either individual repositories or parent directories containing Git repositories.

### Path syntax

- A bare line is a path only when it starts with `/`. Anything else on a bare
  line is ignored, as in 1.0.0.
- `path = <value>` accepts any value, relative paths included; they are
  resolved against the working directory of the run.
- Paths containing a tab or a newline are **not supported**: the log and the
  internal record streams are line-oriented with tab-separated fields.
- A trailing `/` is accepted and ignored.
- Discovery looks at the path itself and **five** levels below it, and
  **stops at a repository**: a directory that is a repository is used and
  never entered, so a submodule or a repository nested inside a work tree is
  never reported separately. `max_depth = 1` restores the single level that
  1.0.0 scanned.

### What each section does

| section          | effect                                                                    |
|------------------|---------------------------------------------------------------------------|
| `[SETTINGS]`     | `log_format = TXT` or `JSON`, `exit_on_failure = no` to keep exiting `0` when a repository fails, `summary = no` to drop the summary line. An inline `# comment` after the value is ignored. |
| `[PULL]`         | `git pull --ff-only`. A bare repository or a dirty work tree is skipped with a `WARN`. |
| `[FETCH]`        | `git fetch --all --prune --tags`.                                         |
| `[DEFAULTS]`     | Option values every repository inherits: `exclude`, `max_depth`, `ssh_key`, `timeout`, `mirror_dir`, `fsck`, `verify_tags`. |
| `[BUNDLE]`       | `git bundle` of what a repository gained since its last bundle, into `bundle_dir`, with a `SHA256SUMS` manifest beside it. |
| `[MIRROR]`       | `git clone --mirror` the first time, `git remote update --prune` after that, into `mirror_dir`. Submodules named in `.gitmodules` are mirrored too, recursively. |
| `[SILENT_UPDATE]`| `git fetch`, then `git branch -f` for every branch that tracks a remote, is behind it, and is not checked out in the repository or in any of its worktrees. Nothing is merged and no work tree is touched. A bare repository is skipped. |

Unknown sections are ignored, and section names are case insensitive.

### Options a repository can inherit or override

`[DEFAULTS]` holds values that apply to every repository in the run:

```ini
[DEFAULTS]
exclude = */vendor,*-archive
max_depth = 2
ssh_key = /home/user/.ssh/deploy
timeout = 120
```

| key         | effect                                                                  |
|-------------|-------------------------------------------------------------------------|
| `exclude`   | Comma-separated globs; a discovered repository whose path matches one is left alone. |
| `max_depth` | How far below a configured path discovery looks. `0` is the path itself, `1` one level down, `5` the default. Descent stops at a repository whatever the depth. |
| `ssh_key`   | Becomes `GIT_SSH_COMMAND=ssh -i <key> -o IdentitiesOnly=yes` for that repository's git calls. |
| `timeout`   | Seconds one git call may take, when `timeout(1)` is installed. Default 300. |
| `mirror_dir`| Where `[MIRROR]` keeps its mirrors. Required by that section; without it every mirror is skipped. |
| `fsck`      | `yes` runs `git fsck --connectivity-only` on a mirror after each update. |
| `verify_tags`| `yes` verifies every *signed* tag in a mirror after each update. Unsigned tags are not checked. |
| `bundle_dir`| Where `[BUNDLE]` writes its bundles and their `SHA256SUMS`. Required by that section. |
| `on_change` | A command to run once for every repository whose refs moved, with `AUTOGIT_MODE` and `AUTOGIT_REPO` in its environment. |

A repository can override `ssh_key` and `timeout` for itself, with git's
own configuration:

```bash
git -C /path/to/repo config autogit.ssh-key /home/user/.ssh/other
git -C /path/to/repo config autogit.timeout 600
```

A git configuration key cannot contain an underscore, so `ssh_key` in the
INI file is `autogit.ssh-key` in a repository. `exclude` and `max_depth`
decide what gets discovered in the first place, so they are read from
`[DEFAULTS]` only.

### Mirroring for air-gapped transfer

`[MIRROR]` takes sources, not local paths — a source is as often a URL as a
directory — so write them as `source =`. The older spelling `path =` means
exactly the same thing and keeps working.

Three repositories onto a disk you can carry:

```ini
[DEFAULTS]
mirror_dir = /srv/transfer/mirrors

[MIRROR]
source = https://github.com/example/project.git
source = git@github.com:example/library.git
source = /srv/git/internal.git
```

```console
$ autogit-o-matic.sh --config /etc/autogit-o-matic.ini
[2026-10-14 09:00:01] MIRROR: https://github.com/example/project.git - Success (mirrored)
[2026-10-14 09:00:04] MIRROR: git@github.com:example/library.git - Success (mirrored)
[2026-10-14 09:00:05] MIRROR: /srv/git/internal.git - Success (mirrored)
[2026-10-14 09:00:05] SUMMARY: updated=3 unchanged=0 skipped=0 failed=0 duration=4s
```

That leaves `/srv/transfer/mirrors/project.git`, `library.git` and
`internal.git`. Copy the directory to the machine behind the air gap and
each one is a repository people can work from:

```bash
# A first copy on the other side.
git clone /media/transfer/mirrors/project.git

# Or feed a clone that already exists there.
git -C ~/work/project remote add transfer /media/transfer/mirrors/project.git
git -C ~/work/project fetch transfer
```

Run the same configuration again next week and only what moved is fetched:
`updated=1 unchanged=2`. Each source is mirrored to
`<mirror_dir>/<name>.git`, where `<name>` is the last path element with any
`.git` suffix removed. The first run clones with `--mirror`, every later run
does `git remote update --prune`, so a ref deleted upstream disappears from
the mirror as well.

### Bundles, when the disk has to stay small

A mirror carries everything every time. `[BUNDLE]` carries only what is
new, as one file per repository:

```ini
[DEFAULTS]
bundle_dir = /srv/transfer/bundles

[BUNDLE]
source = /srv/git/project.git
source = /srv/git/library.git
source = /srv/git/internal.git
```

The first run writes a full bundle per repository; every later run writes
one that contains only the commits added since, named
`<name>-<timestamp>-<checksum>.bundle`. What has already been exported is
recorded in `$GIT_DIR/autogit/bundle-tips` inside the repository itself, so
nothing outside it has to be kept in step.

Beside the bundles is a `SHA256SUMS` manifest, so the other side can tell a
truncated copy from a whole one:

```bash
cd /media/transfer/bundles && sha256sum -c SHA256SUMS
git clone project-20261014090001-1653878.bundle project   # the first one
git -C project pull /media/transfer/bundles/project-20261021090002-9912034.bundle master
```

A bundle written without `sha256sum` on the machine still works; the log
line says the manifest was skipped.

Submodules are followed: after a mirror is updated, the `url` entries in its
`HEAD:.gitmodules` are mirrored the same way, and so are theirs, up to five
levels deep. A relative URL such as `../shared.git` resolves against the
source it came from, exactly as git resolves it, so a group of repositories
that reference each other relatively mirrors as a group.

### Reacting to a change, and looking without touching

`on_change` runs a command once for every repository whose refs moved, with
`AUTOGIT_MODE` and `AUTOGIT_REPO` in its environment:

```ini
[DEFAULTS]
on_change = systemctl --user restart my-site.service
```

Its output goes to stderr so that it cannot land in the middle of the log,
and a hook that exits non-zero logs a `WARN` rather than failing a fetch
that already succeeded. A single repository can set its own with
`git config autogit.on-change '<command>'`.

`--status` reports what every configured repository looks like and changes
nothing — no fetch, no refs, not even a lock, so it is safe to run while a
scheduled run is going:

```console
$ autogit-o-matic.sh --config /etc/autogit-o-matic.ini --status
FETCH	/srv/git/project	master	ahead=0 behind=2	dirty=no
PULL	/home/user/work/site	main	ahead=1 behind=0	dirty=yes
```

`--self-check` reports what the machine can do — git's version against the
2.20 minimum, which optional tools are installed, whether the lock
directory is writable — and needs no configuration file.

### Running several repositories at once

`--jobs N` works on N repositories in parallel, in batches of N. Each log
line is written with a single `printf`, and a line that short cannot be
split by the kernel, so parallel jobs share one stdout and one log file
without interleaving. The run counts (`updated`, `failed`, …) are kept in
a file inside the lock directory for the same reason: a count in a shell
variable would not survive the subshell each job runs in.

## Versions

Every release is tagged and published, with the script, the example
configuration and a `SHA256SUMS` on the
[releases page](https://github.com/FPGArtktic/AutoGit-o-Matic/releases).
`autogit-o-matic.sh --version` prints the version a copy came from.

That is also the answer to an upgrade you do not want. Nothing is deleted:
if a release changes something you relied on, the previous one stays exactly
where it was.

```bash
# the whole repository at an older release
git clone --branch v2.5.0 https://github.com/FPGArtktic/AutoGit-o-Matic.git

# or go back in a clone you already have
git -C AutoGit-o-Matic checkout v2.5.0

# or just the script, from the release assets
curl -LO https://github.com/FPGArtktic/AutoGit-o-Matic/releases/download/v2.5.0/autogit-o-matic.sh
```

### Which release breaks what

A release that changes what an existing configuration or cron entry does
gets a **major** number. Inside a major line, upgrading is safe: every
feature since 2.0.0 is either invisible until you configure it or has an
off switch.

| release | safe to upgrade into? | what it did to an existing setup |
|---------|----------------------|----------------------------------|
| `1.0.0` | —                    | the original Bash script |
| `2.0.0` | **no**               | `[PULL]` became `git pull --ff-only`, so a diverged branch is reported instead of merged; a dirty work tree or a bare repository in `[PULL]` is skipped; errors moved to stderr; a run that finds the lock held exits `3` |
| `2.1.0` | yes                  | nothing: added `[SILENT_UPDATE]` |
| `2.2.0` | yes, with one note   | added flags, `[DEFAULTS]`, and the `SUMMARY` line — one line on stdout that 1.0.0 did not print. `2.5.0` added `summary = no` to turn it off |
| `2.3.0` | yes                  | nothing: added `[MIRROR]` |
| `2.4.0` | yes                  | nothing: added `[BUNDLE]`, `on_change`, `--status`, `--self-check` |
| `2.5.0` | yes                  | nothing: added `summary = no` |
| `3.0.0` | **no**               | a failed repository exits `2` instead of `0`; discovery descends five levels instead of one. Both are switchable: `exit_on_failure = no` and `max_depth = 1` give you 2.x behaviour on 3.x |

So: **`2.0.0` and `3.0.0` are the breaks.** Everything else is additive.
Both of 3.0.0's changes have a switch, so a configuration file can keep the
old behaviour, and `2.5.0` stays exactly where it is if you would rather not
move at all — clone the tag, or take the script from its release, and
nothing has shifted under you.

[CHANGELOG.md](CHANGELOG.md) says what every release changed, in detail, and
marks the breaking parts.

## Development

Development tasks run through [`just`](https://github.com/casey/just):

```bash
just lint        # shellcheck, checkbashisms, shfmt
just test        # the bats suite under sh
just test dash   # ... or under one named shell
just test-all    # sh, dash, bash --posix, busybox sh
just coverage    # kcov, with an 80 % floor
just check       # all of the above; the pre-commit gate
```

The development dependencies are `shellcheck`, `checkbashisms` (Debian's
`devscripts`), `shfmt`, `bats-core`, `jq`, `kcov`, `dash` and `busybox`. None
of them is needed to run the script.

One wrinkle worth knowing: `kcov` cannot follow `bats` 1.13 or newer, which
manipulates the same `set -x` and DEBUG traps that kcov's collectors use.
The suite passes either way, but the coverage number comes out roughly half
of the truth. CI runs Ubuntu's bats and measures correctly; locally, point
the recipe at an older bats:

```bash
just coverage ~/tools/bats-1.12/bin/bats
```

## Scheduling

`contrib/` has ready-made units and crontab lines:

- `contrib/systemd/autogit-o-matic.service` and `.timer` — an hourly
  `oneshot` run with `Persistent=true`, so a machine that was asleep catches
  up instead of waiting for the next hour. The service treats exit code `3`
  as success, because that only means the previous run is still going.
- `contrib/cron.example` — the same thing for cron, including how to
  swallow exit `3` when overlapping runs are expected.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

```
AutoGit-o-Matic - Automate Git operations across multiple repositories
Copyright (C) 2025 Mateusz Okulanis

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```

## Author

**Mateusz Okulanis**  
Email: FPGArtktic@outlook.com

---
