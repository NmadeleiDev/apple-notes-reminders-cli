# ZeroClaw setup

Build or install `apple-notes-reminders`, then use its absolute path. Do not launch a floating package installer from the MCP configuration.

```toml
[[mcp.servers]]
name = "apple-productivity"
transport = "stdio"
command = "/absolute/path/to/apple-notes-reminders"
args = ["mcp"]
tool_timeout_secs = 60

[mcp_bundles.apple_productivity]
servers = ["apple-productivity"]

[agents.rene]
mcp_bundles = ["apple_productivity"]
```

Keep deletion visible to an operator even if read operations are automatic:

```toml
[risk_profiles.greg]
auto_approve = [
  "apple-productivity__notes_accounts",
  "apple-productivity__notes_folders",
  "apple-productivity__notes_list",
  "apple-productivity__notes_get",
  "apple-productivity__notes_search",
  "apple-productivity__reminders_lists",
  "apple-productivity__reminders_list",
  "apple-productivity__reminders_get",
  "apple-productivity__reminders_search",
  "apple-productivity__permissions_status",
]
always_ask = [
  "apple-productivity__permissions_authorize",
  "apple-productivity__notes_delete",
  "apple-productivity__reminders_delete",
]
```

Copy `skills/apple-notes-reminders` into Rene's per-agent skill directory or a configured shared skill bundle. The skill is instruction-only; it does not require script-bearing skills to be enabled.

Restart Rene's session after changing MCP or skill bundles. Use `permissions_status` to inspect the permission state attributed to Rene's exact MCP host. With explicit user approval, `permissions_authorize` requests access from that same host and may display a macOS prompt. A CLI authorization launched from Terminal does not necessarily grant a daemon-hosted MCP server access.
