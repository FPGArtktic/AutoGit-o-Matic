# AutoGit-o-Matic

<p align="center">
  <img src="logo.jpg" alt="AutoGit-o-Matic Logo" width="500"/>
</p>

<p align="center">
  <strong>Automate Git operations across multiple repositories</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#cron-setup">Cron Setup</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#license">License</a>
</p>

## Features

AutoGit-o-Matic is a Bash script that automates Git operations across multiple repositories. It helps you:

- **Pull or fetch updates** from multiple repositories with a single command
- **Scan directories** for Git repositories automatically
- **Log operations** in both TXT and JSON formats
- **Dry-run** capability to simulate operations without making actual changes
- **Configurable paths** via an INI file

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
- `--log-file FILE` - Write logs to the specified file
- `--help` - Display help message and exit

### Example

```bash
./autogit-o-matic.sh --verbose --log-file autogit.log
```

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
