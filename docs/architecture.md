# Architecture

## Source of truth

Notes.app and Reminders.app are the only persistent sources of truth. The project maintains no cache, mirror database, account registry, or background sync state.

```text
CLI commands ─┐
              ├─ AppleProductivityCore ─┬─ Notes OSA backend ── Notes.app
MCP tools ────┘                          └─ EventKit backend ─── Reminders.app
```

`AppleProductivityCore` owns models, validation, error taxonomy, coding, and backend protocols. Both executable surfaces call the same services.

## Notes backend

Apple does not provide a public Notes data framework. The Notes backend runs one static JavaScript-for-Automation program through `/usr/bin/osascript`. The operation and JSON payload are separate process arguments. User-controlled content is never concatenated into executable source.

The backend reads and mutates through Notes.app itself. It does not request Full Disk Access and does not inspect `NoteStore.sqlite`.

Known platform constraints:

- Notes tags, pin state, smart-folder definitions, and some rich attachment metadata are not fully scriptable.
- Whole-body updates convert the supplied plaintext into conservative HTML and may lose unsupported formatting.
- Note deletion moves the item to Recently Deleted according to Notes.app behavior.

## Reminders backend

The Reminders backend owns an actor-isolated `EKEventStore`. It requests full Reminders access on macOS 14+ and uses public `EKReminder` and `EKCalendar` APIs for every operation.

Private ReminderKit frameworks and direct database access are prohibited. Consequently, features absent from public EventKit—such as native sections and some attachment/tag behaviors—are outside the supported contract.

## Machine contract

The CLI writes a JSON envelope with `schema_version`, `ok`, and either `data` or `error`. Dates are encoded as ISO-8601. Diagnostics never contaminate stdout.

MCP uses the official Swift MCP SDK over stdio. Tool results return the same envelope as text and structured content. The adapter is isolated from the core because the SDK remains pre-1.0.

## Permission identity

The executable embeds Reminders and Apple Events usage descriptions. Release binaries use a stable bundle identifier. Local source builds are ad-hoc identities; macOS may associate their prompts with Terminal or the agent host. A release can be Developer ID signed and notarized without changing the data model.

When a hardened-runtime application launches the MCP server, macOS may attribute Apple Events and EventKit access to that responsible host. Such a host must carry its own Apple Events entitlement and privacy usage descriptions. The CLI cannot add entitlements to its parent process or enclosing application.

## Threat model

The primary risks are prompt-driven destructive actions, stale reads followed by overwrites, command/OSA injection, excessive data disclosure, and broad macOS privacy grants.

Controls:

- stable-ID mutations;
- explicit delete confirmation at both CLI and MCP boundaries;
- dry-run mutation previews;
- optimistic conflict checks;
- static automation source and serialized arguments;
- bounded reads;
- no Full Disk Access, Accessibility, network, telemetry, or private database access;
- exact dependency resolution in `Package.resolved`.

The MCP host remains responsible for deciding which tools an agent can see and which require operator approval.
