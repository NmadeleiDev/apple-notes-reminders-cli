---
name: apple-notes-reminders
description: Manage Apple Notes and Apple Reminders through the apple-notes-reminders MCP tools. Use when the user asks to find, read, create, append, update, organize, complete, reopen, or delete a note or reminder on their Mac, or asks about Notes/Reminders accounts, folders, lists, permissions, or health.
---

# Apple Notes and Reminders

Use only tools present in the active tool list. Never invent a tool name, alias, or generic `action` wrapper. Use the MCP tools whose names end in `notes_*` and `reminders_*`. Treat Apple stable IDs as the only safe mutation handles.

## ZeroClaw tool names

ZeroClaw exposes MCP tools as `<server-name>__<tool-name>`. With the recommended server name `apple_productivity`, call these permission tools exactly:

- `apple_productivity__permissions_status` with `{}`
- `apple_productivity__permissions_authorize` with `{"service":"notes"}` or `{"service":"reminders"}`

Do not call bare permission names under ZeroClaw, and never guess names such as `apple_reminders_check_permissions_tool`. If the configured server name differs, select the exact qualified name shown in the active tool list.

## Workflow

1. Use the narrowest read tool that can identify the target.
2. If a title or name matches multiple items, show the candidates and ask the user to choose. Never guess.
3. Use the returned stable ID for every mutation.
4. Preserve the user's wording, dates, list/folder choice, and time zone. Ask only when an omitted choice materially changes the result.
5. Read the item again after a mutation when verification matters.

## Notes rules

- Prefer `notes_append` over `notes_update` for additions; whole-body replacement can lose rich formatting or attachments.
- Before replacing a body, call `notes_get`. Pass its modification timestamp as `if_modified_at` when available.
- Never claim tags, pin state, smart folders, or attachment layout were changed unless the returned result proves it.
- `notes_delete` moves an item to Recently Deleted. Ask the user to confirm the exact title and stable ID, then pass `confirm: true`.

## Reminders rules

- Interpret unqualified relative dates in the user's local time zone. Preserve whether the user supplied a date only or a specific time.
- Prefer exact list names or list IDs from `reminders_lists`.
- Completing and reopening are reversible mutations; report the returned state.
- Reminder deletion is permanent. Ask the user to confirm the exact title and stable ID, then pass `confirm: true`.

## Safety

- Do not broaden a search beyond the user's requested account, folder, or list without saying so.
- Do not expose unrelated note bodies or reminder notes in the response.
- On a permission denial, call the exposed `permissions_status` tool once. Its result is authoritative for the current MCP host.
- If the service is `not_determined`, ask the user for approval, then call the exposed `permissions_authorize` tool from MCP so macOS attributes the request to the agent host.
- If the service is `denied`, tell the user which service is denied and direct them to **System Settings → Privacy & Security → Automation / Reminders**. Do not claim that running the CLI from Terminal authorizes a daemon-hosted MCP server.
- Do not retry a permission denial or authorization request repeatedly.
- Treat tool errors as authoritative. Never report success from intent alone.
