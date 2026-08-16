import AppleProductivityCore
import ArgumentParser
import Foundation

@main
struct AppleNotesReminders: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apple-notes-reminders",
    abstract: "Native, structured access to Apple Notes and Reminders.",
    version: "0.1.0",
    subcommands: [Notes.self, Reminders.self, Authorize.self, Doctor.self, MCPCommand.self]
  )
}

struct OutputOptions: ParsableArguments {
  @Flag(name: .long, help: "Pretty-print JSON output.")
  var pretty = false
}

enum CLIOutput {
  static func run<Value: Codable>(pretty: Bool, operation: () async throws -> Value) async throws {
    do {
      let value = try await operation()
      try write(SuccessEnvelope(data: value), pretty: pretty, to: .standardOutput)
    } catch {
      let converted = error.appleProductivityError
      try? write(ErrorEnvelope(converted), pretty: pretty, to: .standardError)
      throw ExitCode(converted.exitCode)
    }
  }

  static func write<Value: Encodable>(_ value: Value, pretty: Bool, to handle: FileHandle) throws {
    var data = try ProductivityCoding.encoder(pretty: pretty).encode(value)
    data.append(0x0A)
    try handle.write(contentsOf: data)
  }
}

struct Notes: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Read and manage Apple Notes.",
    subcommands: [
      Accounts.self, Folders.self, List.self, Get.self, Search.self, Create.self, Append.self,
      Update.self, Move.self, Delete.self,
    ]
  )

  struct Accounts: AsyncParsableCommand {
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) { try await NotesService().accounts() }
    }
  }

  struct Folders: AsyncParsableCommand {
    @Option(name: .long, help: "Exact account name.") var account: String?
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        try await NotesService().folders(account: account)
      }
    }
  }

  struct List: AsyncParsableCommand {
    @Option(name: .long, help: "Exact account name.") var account: String?
    @Option(name: .long, help: "Folder name or path.") var folder: String?
    @Option(name: .long, help: "Maximum number of results.") var limit = 50
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        try await NotesService().list(account: account, folder: folder, limit: limit)
      }
    }
  }

  struct Get: AsyncParsableCommand {
    @Argument(help: "Stable note ID.") var id: String
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) { try await NotesService().get(id: id) }
    }
  }

  struct Search: AsyncParsableCommand {
    @Argument(help: "Text to search for.") var query: String
    @Option(name: .long, help: "Exact account name.") var account: String?
    @Option(name: .long, help: "Folder name or path.") var folder: String?
    @Option(name: .long, help: "Maximum number of results.") var limit = 50
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        try await NotesService().search(
          query: query, account: account, folder: folder, limit: limit)
      }
    }
  }

  struct Create: AsyncParsableCommand {
    @Option(name: .long, help: "Note title.") var title: String
    @Option(name: .long, help: "Plaintext body. Use --stdin for standard input.") var content:
      String?
    @Flag(name: .long, help: "Read plaintext body from standard input.") var stdin = false
    @Option(name: .long, help: "Exact account name.") var account: String?
    @Option(name: .long, help: "Existing folder path.") var folder: String?
    @Flag(name: .long, help: "Preview the mutation without changing Notes.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        let body = try readContent(content, stdin: stdin, required: false)
        if dryRun {
          return AnyCodableValue(
            MutationPreview(
              operation: "notes.create",
              changes: compact([
                "title": title, "content": body, "account": account, "folder": folder,
              ])
            ))
        }
        return AnyCodableValue(
          try await NotesService().create(
            title: title, content: body, account: account, folder: folder))
      }
    }
  }

  struct Append: AsyncParsableCommand {
    @Argument(help: "Stable note ID.") var id: String
    @Option(name: .long, help: "Plaintext to append. Use --stdin for standard input.") var content:
      String?
    @Flag(name: .long, help: "Read content from standard input.") var stdin = false
    @Flag(name: .long, help: "Preview the mutation without changing Notes.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        let body = try readContent(content, stdin: stdin, required: true)
        if dryRun {
          return AnyCodableValue(
            MutationPreview(operation: "notes.append", targetID: id, changes: ["content": body]))
        }
        return AnyCodableValue(try await NotesService().append(id: id, content: body))
      }
    }
  }

  struct Update: AsyncParsableCommand {
    @Argument(help: "Stable note ID.") var id: String
    @Option(name: .long, help: "Replacement title.") var title: String?
    @Option(name: .long, help: "Replacement plaintext body. Use --stdin for standard input.")
    var content: String?
    @Flag(name: .long, help: "Read replacement body from standard input.") var stdin = false
    @Option(
      name: .long, help: "Only update if the note still has this ISO-8601 modified timestamp.")
    var ifModifiedAt: String?
    @Flag(name: .long, help: "Preview the mutation without changing Notes.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        let body = stdin ? try readContent(nil, stdin: true, required: true) : content
        let expected = try ifModifiedAt.map { try FlexibleDateParser.parse($0) }
        if dryRun {
          return AnyCodableValue(
            MutationPreview(
              operation: "notes.update",
              targetID: id,
              changes: compact(["title": title, "content": body, "if_modified_at": ifModifiedAt])
            ))
        }
        return AnyCodableValue(
          try await NotesService().update(
            id: id, title: title, content: body, ifModifiedAt: expected
          ))
      }
    }
  }

  struct Move: AsyncParsableCommand {
    @Argument(help: "Stable note ID.") var id: String
    @Option(name: .long, help: "Exact destination account.") var account: String?
    @Option(name: .long, help: "Existing destination folder path.") var folder: String
    @Flag(name: .long, help: "Preview the mutation without changing Notes.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        if dryRun {
          return AnyCodableValue(
            MutationPreview(
              operation: "notes.move", targetID: id,
              changes: compact(["account": account, "folder": folder])
            ))
        }
        return AnyCodableValue(
          try await NotesService().move(id: id, account: account, folder: folder))
      }
    }
  }

  struct Delete: AsyncParsableCommand {
    @Argument(help: "Stable note ID.") var id: String
    @Flag(name: .long, help: "Required confirmation. The note moves to Recently Deleted.")
    var force = false
    @Flag(name: .long, help: "Preview the deletion without changing Notes.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        if dryRun { return DeleteResult(id: id, deleted: false, dryRun: true) }
        guard force else {
          throw AppleProductivityError.invalidArguments("Deletion requires --force.")
        }
        try await NotesService().delete(id: id)
        return DeleteResult(id: id, deleted: true, dryRun: false)
      }
    }
  }
}

struct Reminders: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Read and manage Apple Reminders through EventKit.",
    subcommands: [
      Lists.self, List.self, Get.self, Search.self, Create.self, Update.self, Complete.self,
      Reopen.self, Delete.self,
    ]
  )

  struct Lists: AsyncParsableCommand {
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) { try await RemindersService().lists() }
    }
  }

  struct List: AsyncParsableCommand {
    @Option(name: .long, help: "Exact list name or stable list ID.") var list: String?
    @Flag(name: .long, help: "Include completed reminders.") var includeCompleted = false
    @Option(name: .long, help: "Maximum number of results.") var limit = 50
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        try await RemindersService().list(
          list: list, includeCompleted: includeCompleted, limit: limit)
      }
    }
  }

  struct Get: AsyncParsableCommand {
    @Argument(help: "Stable reminder ID.") var id: String
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) { try await RemindersService().get(id: id) }
    }
  }

  struct Search: AsyncParsableCommand {
    @Argument(help: "Text to search for.") var query: String
    @Option(name: .long, help: "Exact list name or stable list ID.") var list: String?
    @Flag(name: .long, help: "Include completed reminders.") var includeCompleted = false
    @Option(name: .long, help: "Maximum number of results.") var limit = 50
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        try await RemindersService().search(
          query: query, list: list, includeCompleted: includeCompleted, limit: limit)
      }
    }
  }

  struct Create: AsyncParsableCommand {
    @Option(name: .long, help: "Reminder title.") var title: String
    @Option(name: .long, help: "Exact list name or stable list ID.") var list: String?
    @Option(name: .long, help: "Reminder notes.") var notes: String?
    @Option(name: .long, help: "Absolute URL.") var url: String?
    @Option(
      name: .long, help: "Due date: ISO-8601, yyyy-MM-dd, yyyy-MM-dd HH:mm, today, or tomorrow.")
    var due: String?
    @Option(name: .long, help: "EventKit priority, 0 through 9.") var priority = 0
    @Flag(name: .long, help: "Preview the mutation without changing Reminders.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        let parsedURL = try parseURL(url)
        let parsedDue = try due.map { try FlexibleDateParser.parse($0) }
        if dryRun {
          return AnyCodableValue(
            MutationPreview(
              operation: "reminders.create",
              changes: compact([
                "title": title, "list": list, "notes": notes, "url": url, "due_at": due,
                "priority": String(priority),
              ])))
        }
        return AnyCodableValue(
          try await RemindersService().create(
            title: title, list: list, notes: notes, url: parsedURL, dueAt: parsedDue,
            priority: priority
          ))
      }
    }
  }

  struct Update: AsyncParsableCommand {
    @Argument(help: "Stable reminder ID.") var id: String
    @Option(name: .long, help: "Replacement title.") var title: String?
    @Option(name: .long, help: "Exact destination list name or ID.") var list: String?
    @Option(name: .long, help: "Replacement notes.") var notes: String?
    @Option(name: .long, help: "Replacement absolute URL.") var url: String?
    @Option(name: .long, help: "Replacement due date.") var due: String?
    @Option(name: .long, help: "Replacement EventKit priority, 0 through 9.") var priority: Int?
    @Flag(name: .long, help: "Require the reminder to be incomplete before updating.")
    var ifIncomplete = false
    @Flag(name: .long, help: "Preview the mutation without changing Reminders.") var dryRun = false
    @OptionGroup var output: OutputOptions

    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        let parsedURL = try parseURL(url)
        let parsedDue = try due.map { try FlexibleDateParser.parse($0) }
        if dryRun {
          return AnyCodableValue(
            MutationPreview(
              operation: "reminders.update", targetID: id,
              changes: compact([
                "title": title, "list": list, "notes": notes, "url": url, "due_at": due,
                "priority": priority.map(String.init), "if_completed": ifIncomplete ? "false" : nil,
              ])))
        }
        return AnyCodableValue(
          try await RemindersService().update(
            id: id, title: title, list: list, notes: notes, url: parsedURL, dueAt: parsedDue,
            priority: priority, ifCompleted: ifIncomplete ? false : nil
          ))
      }
    }
  }

  struct Complete: AsyncParsableCommand {
    @Argument(help: "Stable reminder ID.") var id: String
    @Flag(name: .long, help: "Preview without changing Reminders.") var dryRun = false
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        if dryRun {
          return AnyCodableValue(
            MutationPreview(operation: "reminders.complete", targetID: id, changes: [:]))
        }
        return AnyCodableValue(try await RemindersService().setCompleted(id: id, completed: true))
      }
    }
  }

  struct Reopen: AsyncParsableCommand {
    @Argument(help: "Stable reminder ID.") var id: String
    @Flag(name: .long, help: "Preview without changing Reminders.") var dryRun = false
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        if dryRun {
          return AnyCodableValue(
            MutationPreview(operation: "reminders.reopen", targetID: id, changes: [:]))
        }
        return AnyCodableValue(try await RemindersService().setCompleted(id: id, completed: false))
      }
    }
  }

  struct Delete: AsyncParsableCommand {
    @Argument(help: "Stable reminder ID.") var id: String
    @Flag(name: .long, help: "Required confirmation. Reminder deletion is permanent.") var force =
      false
    @Flag(name: .long, help: "Preview without changing Reminders.") var dryRun = false
    @OptionGroup var output: OutputOptions
    func run() async throws {
      try await CLIOutput.run(pretty: output.pretty) {
        if dryRun { return DeleteResult(id: id, deleted: false, dryRun: true) }
        guard force else {
          throw AppleProductivityError.invalidArguments("Deletion requires --force.")
        }
        try await RemindersService().delete(id: id)
        return DeleteResult(id: id, deleted: true, dryRun: false)
      }
    }
  }
}

struct Authorize: AsyncParsableCommand {
  enum Service: String, ExpressibleByArgument { case notes, reminders, all }
  @Argument(help: "Service to authorize: notes, reminders, or all.") var service: Service = .all
  @OptionGroup var output: OutputOptions

  func run() async throws {
    try await CLIOutput.run(pretty: output.pretty) {
      var result: [String: Bool] = [:]
      if service == .notes || service == .all {
        result["notes"] = try await NotesService().authorize()
      }
      if service == .reminders || service == .all {
        result["reminders"] = try await RemindersService().authorize()
      }
      return result
    }
  }
}

struct Doctor: AsyncParsableCommand {
  @OptionGroup var output: OutputOptions
  func run() async throws {
    try await CLIOutput.run(pretty: output.pretty) {
      let notes = NotesService()
      let reminders = RemindersService()
      async let notesStatus = notes.permissionStatus()
      async let remindersStatus = reminders.permissionStatus()
      let statuses = await (notesStatus, remindersStatus)
      let noteAccounts = try? await notes.accounts().count
      let reminderLists = try? await reminders.lists().count
      var warnings: [String] = []
      if statuses.0 != "authorized" { warnings.append("Notes Automation is \(statuses.0).") }
      if !["full_access", "authorized"].contains(statuses.1) {
        warnings.append("Reminders access is \(statuses.1).")
      }
      return DoctorReport(
        healthy: warnings.isEmpty,
        permissions: PermissionState(notesAutomation: statuses.0, reminders: statuses.1),
        notesAccounts: noteAccounts,
        reminderLists: reminderLists,
        warnings: warnings
      )
    }
  }
}

struct MCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp", abstract: "Run the local MCP server over stdio.")
  func run() async throws { try await MCPServerRunner().run() }
}

private struct DeleteResult: Codable {
  let id: String
  let deleted: Bool
  let dryRun: Bool
}

private enum AnyCodableValue: Codable {
  case note(NoteItem)
  case reminder(ReminderItem)
  case preview(MutationPreview)

  init(_ value: NoteItem) { self = .note(value) }
  init(_ value: ReminderItem) { self = .reminder(value) }
  init(_ value: MutationPreview) { self = .preview(value) }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .note(let value): try value.encode(to: encoder)
    case .reminder(let value): try value.encode(to: encoder)
    case .preview(let value): try value.encode(to: encoder)
    }
  }

  init(from decoder: Decoder) throws {
    if let value = try? NoteItem(from: decoder) {
      self = .note(value)
      return
    }
    if let value = try? ReminderItem(from: decoder) {
      self = .reminder(value)
      return
    }
    self = .preview(try MutationPreview(from: decoder))
  }
}

private func readContent(_ inline: String?, stdin: Bool, required: Bool) throws -> String {
  if stdin && inline != nil {
    throw AppleProductivityError.invalidArguments("Use either --content or --stdin, not both.")
  }
  let result: String
  if stdin {
    result = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
  } else {
    result = inline ?? ""
  }
  if required && result.isEmpty {
    throw AppleProductivityError.invalidArguments("Content must not be empty.")
  }
  return result
}

private func parseURL(_ value: String?) throws -> URL? {
  guard let value else { return nil }
  guard let url = URL(string: value), url.scheme != nil else {
    throw AppleProductivityError.invalidArguments("URL must be absolute.")
  }
  return url
}

private func compact(_ values: [String: String?]) -> [String: String] {
  values.compactMapValues { $0 }
}
