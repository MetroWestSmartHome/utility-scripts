# Claude Code Hook: File Edit Reminder
# Injects context reminder when specific files are modified
#
# Setup: See README.md or https://metrowestsmarthome.com/?p=319
#
# CUSTOMIZE THESE VALUES:
# - $pattern: Regex to match file paths (use [/\\] for path separators)
# - $message: Reminder message Claude will see

# ============================================================================
# CONFIGURATION - Edit these for your project
# ============================================================================

# File path pattern to match (regex)
# Examples:
#   "my-project.*\.(yaml|yml)$"           - YAML files in my-project
#   "src.*\.(ts|tsx)$"                    - TypeScript files in src/
#   "drafts[/\\].*\.md$"                  - Markdown files in drafts/
$pattern = "YOUR_PROJECT_PATTERN"

# Reminder message to inject into Claude's context
$message = "YOUR_REMINDER_MESSAGE"

# ============================================================================
# HOOK LOGIC - Generally no changes needed below
# ============================================================================

# Read tool input from stdin (Claude passes JSON)
$inputData = @($input) -join "`n"

try {
    $json = $inputData | ConvertFrom-Json
    $filePath = $json.tool_input.file_path

    if ($filePath -and $filePath -match $pattern) {
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "PostToolUse"
                additionalContext = $message
            }
        }
        Write-Output ($output | ConvertTo-Json -Depth 10 -Compress)
    }
} catch {
    # Silently ignore parsing errors - not all tool uses have file_path
}

exit 0
