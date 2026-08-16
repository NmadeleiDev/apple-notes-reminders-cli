#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

cli_version=$(sed -n 's/.*version: "\([0-9][0-9.]*\)".*/\1/p' Sources/AppleNotesRemindersCLI/CLI.swift | head -1)
mcp_version=$(sed -n 's/.*version: "\([0-9][0-9.]*\)".*/\1/p' Sources/AppleNotesRemindersCLI/MCPServerRunner.swift | head -1)
plist_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/AppleNotesRemindersCLI/Resources/Info.plist)

if [[ -z "$cli_version" || "$cli_version" != "$mcp_version" || "$cli_version" != "$plist_version" ]]; then
  echo "Version mismatch: CLI=$cli_version MCP=$mcp_version plist=$plist_version" >&2
  exit 1
fi

if [[ $# -gt 0 && "$1" != "$cli_version" ]]; then
  echo "Tag version $1 does not match source version $cli_version" >&2
  exit 1
fi

skill=skills/apple-notes-reminders/SKILL.md
grep -q '^name: apple-notes-reminders$' "$skill"
grep -q '^description: .\{40,\}$' "$skill"
grep -q 'apple_productivity__permissions_status' "$skill"
grep -q 'apple_productivity__permissions_authorize' "$skill"
if grep -q 'TODO' "$skill"; then
  echo "Skill contains unresolved TODOs." >&2
  exit 1
fi

if grep -ERn '(NoteStore\.sqlite|ReminderKit|Full Disk Access required|Accessibility required)' Sources; then
  echo "Prohibited private integration found in production source." >&2
  exit 1
fi

swift package show-dependencies --format json >/dev/null
echo "metadata, policy, and dependency checks passed"
