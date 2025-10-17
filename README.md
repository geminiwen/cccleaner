# Claude Code Cleaner (cccleaner)

A shell script to clean history and cached data from Claude Code's `~/.claude.json` file and `~/.claude/` directory.

## Features

- Clear all project histories at once
- Clear specific project history
- Delete entire projects
- Clear cached data (changelog, gates, configs)
- Clear `~/.claude` folder contents (file-history, projects, todos, shell-snapshots, statsig, debug)
- Clear `~/.claude/history.jsonl`
- Clean all option (everything at once)
- Interactive mode for easy selection
- Automatic backup creation before modifications
- Color-coded output for better readability

## Prerequisites

- `jq` - command-line JSON processor
  - macOS: `brew install jq`
  - Linux: `apt-get install jq` or `yum install jq`

## Installation

1. Clone or download the script:
```bash
git clone <your-repo-url>
cd cccleaner
```

2. Make the script executable:
```bash
chmod +x cccleaner
```

3. (Optional) Add to PATH for easy access:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/cccleaner"
```

## Usage

### List all projects
```bash
./cccleaner --list
```

### Clean everything (recommended)
```bash
./cccleaner --all
```

### Clear specific project history
```bash
./cccleaner --project /Users/username/myproject
```

### Interactive mode (recommended)
```bash
./cccleaner --interactive
```

### Clear cached data
```bash
./cccleaner --cache
```

### Clear ~/.claude folders (including history.jsonl)
```bash
./cccleaner --folders
```

### Skip backup creation (not recommended)
```bash
./cccleaner --all --no-backup
```

## Options

| Option | Description |
|--------|-------------|
| `-a, --all` | Clean everything (histories + folders + cache + history.jsonl) |
| `-p, --project PATH` | Clear history for specific project path |
| `-l, --list` | List all projects |
| `-i, --interactive` | Interactive mode to select projects |
| `-c, --cache` | Clear cached data (changelog, etc.) |
| `-f, --folders` | Clear ~/.claude folder contents (file-history, projects, todos, shell-snapshots, statsig, debug, history.jsonl) |
| `-h, --help` | Show help message |
| `--no-backup` | Skip backup creation (not recommended) |

## Backups

By default, the script creates a backup before any modifications:
- Backups are stored in `~/.claude_backups/`
- Backup filename format:
  - `claude_claude.json_YYYYMMDD_HHMMSS` for ~/.claude.json
  - `claude_dir_YYYYMMDD_HHMMSS` for ~/.claude directory

To restore from backup:
```bash
# Restore .claude.json
cp ~/.claude_backups/claude_claude.json_20250117_143022 ~/.claude.json

# Restore .claude directory
cp -r ~/.claude_backups/claude_dir_20250117_143022 ~/.claude
```

## What Gets Cleaned?

### Project History (--all, -p)
The script clears the `history` array in each project, which contains:
- Previous command/prompt history
- Pasted contents

### Cached Data (--cache)
When using `--cache`, the following keys are removed from ~/.claude.json:
- `cachedChangelog`
- `cachedStatsigGates`
- `cachedDynamicConfigs`

### Claude Folders (--folders)
Clears contents of the following directories:
- `~/.claude/file-history/` - File edit history
- `~/.claude/projects/` - Project-specific data
- `~/.claude/todos/` - Todo lists
- `~/.claude/shell-snapshots/` - Shell state snapshots
- `~/.claude/statsig/` - Feature flags and statistics
- `~/.claude/debug/` - Debug logs
- `~/.claude/history.jsonl` - Complete conversation history log

### Clean All (--all)
Performs all of the above cleaning operations at once

### What's NOT Touched
The script preserves:
- Global settings (numStartups, installMethod, etc.)
- User ID and authentication data
- Project settings (allowedTools, mcpServers, etc.) - when using --folders only
- Tips history
- Feature flags
- `~/.claude/commands/` - Custom slash commands
- `~/.claude/settings.json` - User settings

## Examples

### Example 1: Interactive cleaning
```bash
$ ./cccleaner -i

[INFO] Backup created: ~/.claude_backups/claude_claude.json_20250117_143022

Interactive Mode - Select projects to clean

Projects:
  [1] /Users/john/Code/myapp (15 history items)
  [2] /Users/john/Code/webapp (8 history items)
  [3] /Users/john/Code/api (23 history items)

Options:
  [a] Clean everything
  [c] Clear cache
  [f] Clear folders (file-history, projects, todos, shell-snapshots, statsig, debug, history.jsonl)
  [q] Quit

Enter selection (number/a/c/f/q): 1

What would you like to do with: /Users/john/Code/myapp
  [1] Clear history only
  [2] Delete project entirely
  [q] Cancel

Enter selection: 1

[SUCCESS] Cleared history for: /Users/john/Code/myapp
[SUCCESS] Done!
```

### Example 2: Clean everything with --all
```bash
$ ./cccleaner --all

[INFO] Backup created: ~/.claude_backups/claude_claude.json_20250117_143530
[INFO] Backup created: ~/.claude_backups/claude_dir_20250117_143530

[INFO] Performing deep clean...

[SUCCESS] Cleared all project histories
[SUCCESS] Cleared file-history
[SUCCESS] Cleared projects
[SUCCESS] Cleared todos
[SUCCESS] Cleared shell-snapshots
[SUCCESS] Cleared statsig
[SUCCESS] Cleared debug
[SUCCESS] Cleared cached data
[SUCCESS] Cleared history.jsonl
[SUCCESS] Deep clean completed!
```

### Example 3: List projects
```bash
$ ./cccleaner --list

[INFO] Projects in ~/.claude.json:

  /Users/john/Code/myapp
  /Users/john/Code/webapp
  /Users/john/Code/api
```

## Safety Features

1. **Automatic backups**: Every operation creates a timestamped backup
2. **Confirmation prompts**: Destructive operations require confirmation in interactive mode
3. **JSON validation**: Uses `jq` to ensure JSON integrity
4. **Error handling**: Script exits safely on errors without corrupting the file

## Troubleshooting

### "jq is required but not installed"
Install jq using your package manager:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- CentOS/RHEL: `sudo yum install jq`

### "Project not found"
Make sure you're using the exact project path as shown in `--list`

### "Failed to read projects"
Your `~/.claude.json` file might be corrupted. Try restoring from a backup.

## License

MIT License - feel free to modify and distribute

## Contributing

Issues and pull requests are welcome!
