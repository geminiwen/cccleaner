# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**cccleaner** is a Bash utility that cleans Claude Code's history and cached data from `~/.claude.json` and `~/.claude/` directory. It provides safe cleanup with automatic backups.

## Architecture

### Single Script Design
The entire tool is a single Bash script (`cccleaner`) with no external dependencies except `jq` for JSON manipulation.

### Core Components

**Data Sources:**
- `~/.claude.json` - Main configuration file containing project histories and cached data
- `~/.claude/` directory - Contains multiple subdirectories (file-history, projects, todos, shell-snapshots, statsig, debug) and history.jsonl

**Backup System:**
- All operations create timestamped backups in `~/.claude_backups/` before modification
- Backups include both the JSON file and entire directory structure

**Operation Modes:**
1. **Targeted cleaning** - Clear specific elements (cache, folders, individual projects)
2. **Complete cleaning** (`--all`) - Runs all cleaning operations: histories + projects + folders + cache + history.jsonl
3. **Interactive mode** - Menu-driven interface for selective cleaning

### Key Functions

**Cleaning Operations:**
- `clear_all_histories()` - Empties the `history` array in each project within .claude.json
- `clear_all_projects()` - Deletes all project entries from .claude.json (sets projects to {})
- `clear_claude_folders()` - Removes contents from all ~/.claude subdirectories
- `clear_history_jsonl()` - Truncates the history.jsonl file (doesn't delete, just empties)
- `clear_cache()` - Removes cached keys from .claude.json (cachedChangelog, cachedStatsigGates, cachedDynamicConfigs)
- `clean_all()` - Orchestrates all cleaning functions

**JSON Manipulation Pattern:**
All .claude.json modifications follow this pattern:
1. Create temp file with `mktemp`
2. Use `jq` to perform transformation, outputting to temp file
3. On success, replace original with temp file
4. On failure, remove temp file and exit

## Usage

```bash
# Test the script
./cccleaner --list

# Clean everything (most common use case)
./cccleaner --all

# Interactive mode
./cccleaner --interactive

# Specific operations
./cccleaner --cache           # Only cache
./cccleaner --folders         # Only folders + history.jsonl
./cccleaner --project /path   # Specific project
```

## Making Changes

### When modifying cleaning operations:
- Always preserve the backup creation logic
- Use the temp file pattern for all JSON modifications
- Maintain the colored output functions (print_info, print_success, print_error, print_warning)
- Update both the script's `show_usage()` and README.md

### When adding new directories to clean:
Add to `clear_claude_folders()` following the existing pattern:
```bash
if [ -d "$CLAUDE_DIR/new-folder" ]; then
    rm -rf "$CLAUDE_DIR/new-folder"/*
    print_success "Cleared new-folder"
    cleaned=1
fi
```

### Testing changes:
1. Test with `--list` first (read-only operation)
2. Test with `--no-backup` flag only after verifying behavior
3. Verify backups are created correctly before destructive operations
4. Check that temp files are cleaned up on errors

## Important Notes

- The script uses `set -euo pipefail` for strict error handling
- All modifications are atomic (via temp files)
- The `--folders` option includes history.jsonl cleanup
- The `--all` option is equivalent to running all individual cleaning operations (histories + projects + folders + cache + history.jsonl)
- Project paths in interactive mode come from `jq -r '.projects | keys[]'`
