#!/bin/bash
# AutoGit-o-Matic: Automate Git operations across multiple repositories
# Version: 0.1.0
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

# Default values
CONFIG_FILE="autogit-o-matic.ini"
DRY_RUN=false
LOG_FORMAT="TXT"
VERBOSE=false
LOG_FILE=""  # When empty, no log file is created. When specified, all logs go ONLY to this file

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "AutoGit-o-Matic: Automate Git operations across multiple repositories."
    echo ""
    echo "Options:"
    echo "  --config FILE    Path to the configuration file (default: autogit-o-matic.ini)"
    echo "  --dry-run        Simulate operations without actually executing Git commands"
    echo "  --verbose, -v    Display more detailed information about operations"
    echo "  --log-file FILE  Write logs to the specified file (creates a single log file only at this location)"
    echo "  --help           Display this help message and exit"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --log-file)
            LOG_FILE="$2"  # This is the only location where logs will be written to
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found."
    exit 1
fi

# Get current timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Log operations in TXT format
log_txt() {
    local timestamp=$(get_timestamp)
    local type="$1"
    local path="$2"
    local status="$3"
    local message="$4"
    
    if [ "$type" = "ERROR" ]; then
        echo "[$timestamp] ERROR: $message Path: $path"
    else
        if [ -z "$message" ]; then
            echo "[$timestamp] $type: $path - $status"
        else
            echo "[$timestamp] $type: $path - $status ($message)"
        fi
    fi
}

# Log operations in JSON format
log_json() {
    local timestamp=$(get_timestamp)
    local type="$1"
    local path="$2"
    local status="$3"
    local message="$4"
    
    if [ -z "$message" ]; then
        echo "{\"timestamp\":\"$timestamp\",\"type\":\"$type\",\"path\":\"$path\",\"status\":\"$status\"}"
    else
        echo "{\"timestamp\":\"$timestamp\",\"type\":\"$type\",\"path\":\"$path\",\"status\":\"$status\",\"message\":\"$message\"}"
    fi
}

# Log an operation
log_operation() {
    local type="$1"
    local path="$2"
    local status="$3"
    local message="$4"
    
    local log_message=""
    if [ "$LOG_FORMAT" = "JSON" ]; then
        log_message=$(log_json "$type" "$path" "$status" "$message")
    else
        log_message=$(log_txt "$type" "$path" "$status" "$message")
    fi
    
    # Print to console
    echo "$log_message"
    
    # Write to log file if specified (ONLY to the centralized log file, not in individual repositories)
    if [ -n "$LOG_FILE" ]; then
        echo "$log_message" >> "$LOG_FILE"
    fi
}

# Log an error
log_error() {
    local path="$1"
    local message="$2"
    
    log_operation "ERROR" "$path" "Failed" "$message"
}

# Check if a directory is a Git repository
is_git_repository() {
    local path="$1"
    
    if [ -d "$path/.git" ]; then
        return 0  # True in bash
    else
        return 1  # False in bash
    fi
}

# Verbose log function
verbose_log() {
    local message="$1"
    local level="${2:-INFO}"
    
    if $VERBOSE; then
        case "$level" in
            "INFO")
                echo "[INFO] $message"
                ;;
            "DEBUG")
                echo "[DEBUG] $message"
                ;;
            "WARN")
                echo "[WARNING] $message"
                ;;
            *)
                echo "[INFO] $message"
                ;;
        esac
    fi
}

# Execute a Git command
execute_git_command() {
    local path="$1"
    local command="$2"
    
    # Check if directory exists
    if [ ! -d "$path" ]; then
        log_error "$path" "Directory does not exist"
        return 1
    fi
    
    # Check if it's a Git repository
    if ! is_git_repository "$path"; then
        log_error "$path" "Not a Git repository"
        return 1
    fi
    
    # If verbose mode, print additional info
    if $VERBOSE; then
        verbose_log "Executing 'git $command' in: $path"
    fi
    
    # If dry run, just log what would happen
    if $DRY_RUN; then
        log_operation "${command^^}" "$path" "Success (Dry Run)" "Would execute 'git $command'"
        return 0
    fi
    
    # Execute the Git command
    pushd "$path" > /dev/null
    if output=$(git "$command" 2>&1); then
        log_operation "${command^^}" "$path" "Success" "$output"
        if $VERBOSE && [ -n "$output" ]; then
            # Show a more concise version of the output if it's too long
            if [ ${#output} -gt 150 ]; then
                verbose_log "${output:0:147}..." "DEBUG"
            else
                verbose_log "$output" "DEBUG"
            fi
        fi
        popd > /dev/null
        return 0
    else
        log_error "$path" "Failed to execute git $command: $output"
        if $VERBOSE; then
            verbose_log "Command failed with error" "WARN"
            verbose_log "$output" "DEBUG"
        fi
        popd > /dev/null
        return 1
    fi
}

# Scan for Git repositories in a base path and its immediate subdirectories
scan_for_repositories() {
    local base_path="$1"
    local repositories=()
    
    # Remove trailing slash from base_path if present
    base_path="${base_path%/}"
    
    # Check if the base path itself is a Git repository
    if is_git_repository "$base_path"; then
        if $VERBOSE; then
            verbose_log "Found Git repository: $base_path" >&2
        fi
        repositories+=("$base_path")
        echo "$base_path"
        return 0
    fi
    
    # If the base path is not a repository, check immediate subdirectories
    if [ -d "$base_path" ]; then
        if $VERBOSE; then
            verbose_log "Scanning subdirectories in: $base_path" >&2
        fi
        
        # Count the number of repositories found
        local found_count=0
        
        for subdir in "$base_path"/*; do
            if [ -d "$subdir" ]; then
                if is_git_repository "$subdir"; then
                    if $VERBOSE && [ $found_count -lt 5 ]; then
                        # Only log the first 5 repositories to avoid cluttering output
                        verbose_log "Found Git repository: $subdir" >&2
                    elif $VERBOSE && [ $found_count -eq 5 ]; then
                        verbose_log "More repositories found... (truncating verbose output)" >&2
                    fi
                    found_count=$((found_count + 1))
                    repositories+=("$subdir")
                    echo "$subdir"
                fi
            fi
        done
        
        if $VERBOSE && [ $found_count -gt 0 ]; then
            verbose_log "Total repositories found: $found_count" >&2
        fi
    fi
    
    # Return nothing if no repositories found
    if [ ${#repositories[@]} -eq 0 ]; then
        if $VERBOSE; then
            verbose_log "No Git repositories found in: $base_path" "WARN" >&2
        fi
        return 0
    fi
}

# Process Git operations on repositories
process_repositories() {
    local operation="$1"
    local path="$2"
    
    if $VERBOSE; then
        verbose_log "Processing $operation operation for path: $path"
    fi
    
    # Get repositories
    mapfile -t repositories < <(scan_for_repositories "$path")
    
    if [ ${#repositories[@]} -eq 0 ]; then
        log_error "$path" "No Git repositories found"
        return 1
    fi
    
    # Log repository count in verbose mode
    if $VERBOSE; then
        verbose_log "Found ${#repositories[@]} Git repositories to process"
    fi
    
    # Execute Git operation on each repository
    for repo in "${repositories[@]}"; do
        # Skip empty lines
        if [ -z "$repo" ]; then
            continue
        fi
        execute_git_command "$repo" "${operation,,}"  # Convert operation to lowercase
    done
}

# Read settings from the configuration file
if grep -q "^\[SETTINGS\]" "$CONFIG_FILE"; then
    log_format_line=$(grep -A 10 "^\[SETTINGS\]" "$CONFIG_FILE" | grep "^log_format" | head -n 1)
    if [[ $log_format_line =~ ^log_format[[:space:]]*=[[:space:]]*([[:alnum:]]+) ]]; then
        LOG_FORMAT="${BASH_REMATCH[1]^^}"  # Convert to uppercase
        if [ "$LOG_FORMAT" != "TXT" ] && [ "$LOG_FORMAT" != "JSON" ]; then
            LOG_FORMAT="TXT"  # Default to TXT if invalid format
        fi
    fi
fi

# Process PULL operations
if grep -q "^\[PULL\]" "$CONFIG_FILE"; then
    # Debug: Dump PULL section content
    if $VERBOSE; then
        verbose_log "Debug: Content of [PULL] section:"
        pull_section=$(sed -n '/^\[PULL\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[PULL\]" | grep -v "^\[")
        while IFS= read -r line; do
            verbose_log "  $line"
        done <<< "$pull_section"
    fi
    
    # Try to read paths with "path =" prefix first
    paths=$(sed -n '/^\[PULL\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[PULL\]" | grep -v "^\[" | grep "^path" | sed 's/^path[[:space:]]*=[[:space:]]*//')
    
    # If no paths with prefix were found, try to read direct paths
    if [ -z "$paths" ]; then
        if $VERBOSE; then
            verbose_log "No 'path =' entries found in [PULL] section, trying direct paths"
        fi
        # Fix: Use a better approach to extract direct paths that start with /
        paths=$(sed -n '/^\[PULL\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[PULL\]" | grep -v "^\[" | grep -v "^;" | grep -v "^$" | grep "^/" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Debug extracted paths
        if $VERBOSE; then
            verbose_log "Debug: extracted paths from [PULL] section: '$paths'"
        fi
    fi
    
    if [ -z "$paths" ]; then
        if $VERBOSE; then
            verbose_log "No paths found in [PULL] section"
        fi
    else
        for path in $paths; do
            if $VERBOSE; then
                verbose_log "Found PULL path: $path"
            fi
            process_repositories "PULL" "$path"
        done
    fi
fi

# Process FETCH operations
if grep -q "^\[FETCH\]" "$CONFIG_FILE"; then
    # Debug: Dump FETCH section content
    if $VERBOSE; then
        verbose_log "Debug: Content of [FETCH] section:"
        fetch_section=$(sed -n '/^\[FETCH\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[FETCH\]" | grep -v "^\[")
        while IFS= read -r line; do
            verbose_log "  $line"
        done <<< "$fetch_section"
    fi
    
    # Try to read paths with "path =" prefix first
    paths=$(sed -n '/^\[FETCH\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[FETCH\]" | grep -v "^\[" | grep "^path" | sed 's/^path[[:space:]]*=[[:space:]]*//')
    
    # If no paths with prefix were found, try to read direct paths
    if [ -z "$paths" ]; then
        if $VERBOSE; then
            verbose_log "No 'path =' entries found in [FETCH] section, trying direct paths"
        fi
        # Fix: Use a better approach to extract direct paths that start with /
        paths=$(sed -n '/^\[FETCH\]/,/^\[/p' "$CONFIG_FILE" | grep -v "^\[FETCH\]" | grep -v "^\[" | grep -v "^;" | grep -v "^$" | grep "^/" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Debug extracted paths
        if $VERBOSE; then
            verbose_log "Debug: extracted paths from [FETCH] section: '$paths'"
        fi
    fi
    
    if [ -z "$paths" ]; then
        if $VERBOSE; then
            verbose_log "No paths found in [FETCH] section"
        fi
    else
        for path in $paths; do
            if $VERBOSE; then
                verbose_log "Found FETCH path: $path"
            fi
            process_repositories "FETCH" "$path"
        done
    fi
fi

exit 0