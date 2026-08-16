# Contributing

Open an issue before implementing a large feature or changing the JSON/MCP contract. Small fixes can go directly to a focused pull request.

## Development

```sh
swift package resolve
swift build
swift test
swift run ContractTests
```

Pull requests must:

- keep Notes.app and Reminders.app as the only sources of truth;
- avoid Full Disk Access, Accessibility, private frameworks, and direct Apple database access;
- pass user values as data rather than executable OSA source;
- add tests at the behavior boundary;
- document output-schema or permission changes;
- avoid real personal data in fixtures and logs;
- keep unrelated formatting or refactors out of the change.

Use conventional commits. By contributing, you agree that your contribution is licensed under the repository's MIT license.
