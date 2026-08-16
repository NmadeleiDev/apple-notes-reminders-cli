# Apple Notes & Reminders CLI

A native macOS CLI and local MCP server for Apple Notes and Reminders. It gives humans, scripts, and AI agents the same typed operations, stable identifiers, and versioned JSON output.

The project deliberately uses Apple's supported integration boundaries:

- Reminders uses public EventKit APIs.
- Notes uses bounded OSA automation against Notes.app because Apple provides no public Notes data framework.
- It never reads or writes Apple's private SQLite databases.
- It requires neither Full Disk Access nor Accessibility permission.
- It has no network access or telemetry.

> Status: early public release. Back up important data and inspect mutations before granting unattended write access.

## Requirements

- macOS 14 Sonoma or newer
- Swift 6.0 or newer when building from source
- Apple Notes and/or Reminders configured locally

## Install from source

```sh
git clone https://github.com/NmadeleiDev/apple-notes-reminders-cli.git
cd apple-notes-reminders-cli
swift build -c release
install -m 0755 .build/release/apple-notes-reminders /usr/local/bin/apple-notes-reminders
```

Do not use `sudo` unless your selected installation directory actually requires it. Tagged releases will include a universal macOS archive and SHA-256 checksums.

## Permissions

Request only the integrations you intend to use:

```sh
apple-notes-reminders authorize notes --pretty
apple-notes-reminders authorize reminders --pretty
apple-notes-reminders doctor --pretty
```

macOS attributes automation permission to the application that launches the command. If an agent daemon runs the binary, authorize it from that same host context and inspect **System Settings → Privacy & Security → Automation / Reminders**.

## CLI examples

Every successful command writes a versioned JSON envelope to stdout. Errors use the same contract on stderr and return a distinct nonzero exit status.

```sh
# Read
apple-notes-reminders notes accounts --pretty
apple-notes-reminders notes search "project alpha" --limit 20 --pretty
apple-notes-reminders reminders list --list Work --pretty
apple-notes-reminders reminders search "renew" --include-completed --pretty

# Preview mutations
apple-notes-reminders notes create --title "Meeting" --content "Agenda" --dry-run --pretty
apple-notes-reminders reminders create --title "Send report" --due tomorrow --dry-run --pretty

# Mutate using stable IDs returned by read commands
apple-notes-reminders notes append NOTE_ID --content "Follow-up" --pretty
apple-notes-reminders reminders complete REMINDER_ID --pretty

# Destructive commands require --force
apple-notes-reminders notes delete NOTE_ID --force
apple-notes-reminders reminders delete REMINDER_ID --force
```

Use `--stdin` for note bodies that should not appear in shell history:

```sh
printf '%s\n' 'Private body' | apple-notes-reminders notes create --title "Draft" --stdin
```

### Commands

```text
notes accounts|folders|list|get|search|create|append|update|move|delete
reminders lists|list|get|search|create|update|complete|reopen|delete
authorize notes|reminders|all
doctor
mcp
```

Dates accept ISO-8601, `yyyy-MM-dd`, `yyyy-MM-dd HH:mm`, `today`, `tomorrow`, or `now`. Local formats use the Mac's current calendar and time zone.

## MCP server

Run the local stdio server:

```sh
apple-notes-reminders mcp
```

Example MCP configuration:

```json
{
  "mcpServers": {
    "apple-productivity": {
      "command": "/absolute/path/to/apple-notes-reminders",
      "args": ["mcp"]
    }
  }
}
```

The MCP surface returns both human-readable JSON text and `structuredContent`. Delete tools require `confirm: true`, even if the host separately auto-approves the tool call.

See [ZeroClaw setup](docs/zeroclaw.md) for a least-privilege Rene configuration. The reusable agent skill is in [`skills/apple-notes-reminders`](skills/apple-notes-reminders/SKILL.md).

## Safety properties

- User values are passed to the Notes automation program as serialized arguments, never interpolated into executable OSA source.
- Read results are bounded to 1–1000 items.
- Mutations address stable Apple identifiers.
- Note updates support `--if-modified-at` optimistic concurrency.
- Reminder updates support `--if-incomplete` conflict detection.
- CLI deletes require `--force`; MCP deletes require `confirm: true`.
- Note deletion uses Notes.app's normal Recently Deleted behavior. Reminder deletion is permanent.
- `--dry-run` previews every CLI mutation without opening either backend.

Replacing an Apple Note body can discard formatting that is not representable through Notes automation. Prefer `notes append` when preserving existing rich content matters.

## Development

```sh
swift package resolve
swift build
swift test
swift run ContractTests
swift build -c release
```

`ContractTests` exists for Command Line Tools-only installations that omit the test runtime shipped with full Xcode. CI runs both the normal Swift Testing suite and this standalone safety-contract suite.

Architecture and security decisions are documented in [docs/architecture.md](docs/architecture.md). Contributions are welcome under [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
