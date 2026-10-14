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
- `--log-file FILE` - Write logs to the specified file as well as to stdout
- `--version` - Print the version and exit
- `--help` - Display help message and exit

### Exit codes

| code | meaning                                      |
|------|----------------------------------------------|
| `0`  | the run finished                             |
| `1`  | a usage or configuration error               |
| `3`  | another run holds the lock for this config   |

A repository that fails is reported as an `ERROR` log line; it does not yet
change the exit code. That arrives together with the summary line
(roadmap item 3).

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
| `[SETTINGS]`     | `log_format = TXT` or `JSON`. An inline `# comment` after the value is ignored. |
| `[PULL]`         | `git pull --ff-only`. A bare repository or a dirty work tree is skipped with a `WARN`. |
| `[FETCH]`        | `git fetch --all --prune --tags`.                                         |

Unknown sections are ignored, and section names are case insensitive.

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
