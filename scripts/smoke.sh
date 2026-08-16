#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
binary=${1:-"$repository_root/.build/debug/apple-notes-reminders"}

"$binary" --version
"$binary" notes create --title "Smoke preview" --content "No mutation" --dry-run >/dev/null
"$binary" reminders create --title "Smoke preview" --due tomorrow --dry-run >/dev/null
"$binary" notes delete synthetic-id --dry-run >/dev/null
"$binary" reminders delete synthetic-id --dry-run >/dev/null
"$binary" doctor --pretty

echo "non-destructive smoke checks passed"
