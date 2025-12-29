# Claude Code Hook Scripts

PowerShell hook scripts for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/hooks) that inject context reminders when specific files are edited.

## Why Hooks?

CLAUDE.md instructions are suggestions—Claude may forget them. Hooks guarantee execution and inject reminders directly into Claude's context via the `additionalContext` pattern.

**Key insight:** `Write-Host` output only appears in verbose mode. For Claude to see your reminders, you must output JSON with an `additionalContext` field.

## Scripts

| Script | Trigger | Reminder |
|--------|---------|----------|
| `hook-file-reminder.ps1` | Edit/Write matching pattern | Customizable message in context |

## Setup

### 1. Copy the Hook Script

Place `hook-file-reminder.ps1` in your project's `.claude/scripts/` folder.

### 2. Configure settings.local.json

Create `.claude/settings.local.json` in your project root:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \".claude/scripts/hook-file-reminder.ps1\"",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### 3. Customize the Script

Edit the script to match your file patterns and messages:

```powershell
# Example: YAML files in a config folder
if ($filePath -match "YOUR_PROJECT.*config.*\.(yaml|yml)$") {
    $message = "YOUR_REMINDER_MESSAGE"
    # ...
}
```

### 4. Restart Claude Code

Hooks are loaded at startup. Restart Claude Code to apply changes.

## How It Works

1. Claude Code calls your hook after every Edit/Write operation
2. The hook receives JSON via stdin with the tool input (including `file_path`)
3. If the file matches your pattern, the hook outputs JSON with `additionalContext`
4. Claude sees your message as a `<system-reminder>` in the conversation

## Example Use Cases

- **YAML validation reminder** for Home Assistant configs
- **WordPress update reminder** for blog drafts
- **Test run reminder** after modifying source code
- **Documentation update reminder** for API changes

## Troubleshooting

**Hook not firing?**
- Verify `settings.local.json` syntax is valid JSON
- Restart Claude Code after adding hooks
- Check the file path pattern matches your files

**Message not visible to Claude?**
- Use `Write-Output` with JSON, not `Write-Host`
- Include the `hookSpecificOutput.additionalContext` structure
- Check for PowerShell errors with `-ErrorAction Stop`

## Related

- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [CLAUDE.md Deep Dive](https://metrowestsmarthome.com/?p=319) - Full tutorial on hooks and CLAUDE.md patterns

## License

MIT License - see [LICENSE](../LICENSE)
