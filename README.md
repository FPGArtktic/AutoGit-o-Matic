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

## Features

AutoGit-o-Matic is a single POSIX shell script that automates Git operations across multiple repositories. It helps you:

- **Pull or fetch updates** from multiple repositories with a single command
- **Scan directories** for Git repositories automatically, including bare mirrors and linked worktrees
- **Log operations** in both TXT and JSON formats
- **Dry-run** capability to simulate operations without making actual changes
- **Configurable paths** via an INI file
- **Safe unattended pulls**: `git pull --ff-only`, so a run can never leave a merge commit behind
- **Silent updates**: fast-forward branches nobody has checked out, without ever touching a work tree
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
- `--strict-exit` - Exit `2` when a repository fails (the default from 3.0.0)
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

Code `2` is **opt-in** until 3.0.0: pass `--strict-exit`, or set
`exit_on_failure = yes` in `[SETTINGS]`. Without it a failed repository is
reported as an `ERROR` line, the run still exits `0`, and one `WARN` on
stderr says the default is about to change.

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
- Discovery looks at the path itself and one level below it. A repository two
  levels down is not found.

### What each section does

| section          | effect                                                                    |
|------------------|---------------------------------------------------------------------------|
| `[SETTINGS]`     | `log_format = TXT` or `JSON`, and `exit_on_failure = yes` to opt into exit code `2`. An inline `# comment` after the value is ignored. |
| `[PULL]`         | `git pull --ff-only`. A bare repository or a dirty work tree is skipped with a `WARN`. |
| `[FETCH]`        | `git fetch --all --prune --tags`.                                         |
| `[DEFAULTS]`     | Option values every repository inherits: `exclude`, `max_depth`, `ssh_key`, `timeout`. |
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
| `max_depth` | How far below a configured path discovery looks. `0` is the path itself, `1` (the default) one level down. |
| `ssh_key`   | Becomes `GIT_SSH_COMMAND=ssh -i <key> -o IdentitiesOnly=yes` for that repository's git calls. |
| `timeout`   | Seconds one git call may take, when `timeout(1)` is installed. Default 300. |

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

### Running several repositories at once

`--jobs N` works on N repositories in parallel, in batches of N. Each log
line is written with a single `printf`, and a line that short cannot be
split by the kernel, so parallel jobs share one stdout and one log file
without interleaving. The run counts (`updated`, `failed`, …) are kept in
a file inside the lock directory for the same reason: a count in a shell
variable would not survive the subshell each job runs in.

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
