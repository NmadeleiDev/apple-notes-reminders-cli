import AppleProductivityCore
import Foundation
import MCP

struct MCPServerRunner {
  let notes: any NotesServing
  let reminders: any RemindersServing

  init(
    notes: any NotesServing = NotesService(),
    reminders: any RemindersServing = RemindersService()
  ) {
    self.notes = notes
    self.reminders = reminders
  }

  func run() async throws {
    let server = Server(
      name: "apple-notes-reminders",
      version: "0.1.1",
      title: "Apple Notes & Reminders",
      instructions:
        "Use stable IDs from read tools for mutations. Delete tools require confirm=true. Prefer append over replacing a note when preserving rich content matters.",
      capabilities: .init(tools: .init())
    )

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: Self.tools)
    }

    await server.withMethodHandler(CallTool.self) { request in
      await call(request)
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
  }

  private func call(_ request: CallTool.Parameters) async -> CallTool.Result {
    let arguments = request.arguments ?? [:]
    do {
      switch request.name {
      case "notes_accounts":
        return try success(await notes.accounts())
      case "notes_folders":
        return try success(await notes.folders(account: arguments.string("account")))
      case "notes_list":
        return try success(
          await notes.list(
            account: arguments.string("account"),
            folder: arguments.string("folder"),
            limit: arguments.integer("limit") ?? 50
          ))
      case "notes_get":
        return try success(await notes.get(id: try arguments.requiredString("id")))
      case "notes_search":
        return try success(
          await notes.search(
            query: try arguments.requiredString("query"),
            account: arguments.string("account"),
            folder: arguments.string("folder"),
            limit: arguments.integer("limit") ?? 50
          ))
      case "notes_create":
        return try success(
          await notes.create(
            title: try arguments.requiredString("title"),
            content: arguments.string("content") ?? "",
            account: arguments.string("account"),
            folder: arguments.string("folder")
          ))
      case "notes_append":
        return try success(
          await notes.append(
            id: try arguments.requiredString("id"),
            content: try arguments.requiredString("content")
          ))
      case "notes_update":
        return try success(
          await notes.update(
            id: try arguments.requiredString("id"),
            title: arguments.string("title"),
            content: arguments.string("content"),
            ifModifiedAt: try arguments.date("if_modified_at")
          ))
      case "notes_move":
        return try success(
          await notes.move(
            id: try arguments.requiredString("id"),
            account: arguments.string("account"),
            folder: try arguments.requiredString("folder")
          ))
      case "notes_delete":
        try arguments.requireConfirmation()
        let id = try arguments.requiredString("id")
        try await notes.delete(id: id)
        return try success(DeleteResponse(deleted: true, id: id))
      case "reminders_lists":
        return try success(await reminders.lists())
      case "reminders_list":
        return try success(
          await reminders.list(
            list: arguments.string("list"),
            includeCompleted: arguments.boolean("include_completed") ?? false,
            limit: arguments.integer("limit") ?? 50
          ))
      case "reminders_get":
        return try success(await reminders.get(id: try arguments.requiredString("id")))
      case "reminders_search":
        return try success(
          await reminders.search(
            query: try arguments.requiredString("query"),
            list: arguments.string("list"),
            includeCompleted: arguments.boolean("include_completed") ?? false,
            limit: arguments.integer("limit") ?? 50
          ))
      case "reminders_create":
        return try success(
          await reminders.create(
            title: try arguments.requiredString("title"),
            list: arguments.string("list"),
            notes: arguments.string("notes"),
            url: try arguments.url("url"),
            dueAt: try arguments.date("due_at"),
            priority: arguments.integer("priority") ?? 0
          ))
      case "reminders_update":
        return try success(
          await reminders.update(
            id: try arguments.requiredString("id"),
            title: arguments.string("title"),
            list: arguments.string("list"),
            notes: arguments.string("notes"),
            url: try arguments.url("url"),
            dueAt: try arguments.date("due_at"),
            priority: arguments.integer("priority"),
            ifCompleted: arguments.boolean("if_completed")
          ))
      case "reminders_complete":
        return try success(
          await reminders.setCompleted(id: try arguments.requiredString("id"), completed: true))
      case "reminders_reopen":
        return try success(
          await reminders.setCompleted(id: try arguments.requiredString("id"), completed: false))
      case "reminders_delete":
        try arguments.requireConfirmation()
        let id = try arguments.requiredString("id")
        try await reminders.delete(id: id)
        return try success(DeleteResponse(deleted: true, id: id))
      default:
        throw AppleProductivityError.notFound(kind: "MCP tool", identifier: request.name)
      }
    } catch {
      return failure(error.appleProductivityError)
    }
  }

  private func success<Value: Codable>(_ data: Value) throws -> CallTool.Result {
    let envelope = SuccessEnvelope(data: data)
    let text = try String(decoding: ProductivityCoding.encoder().encode(envelope), as: UTF8.self)
    return try .init(
      content: [.text(text: text, annotations: nil, _meta: nil)],
      structuredContent: envelope,
      isError: false
    )
  }

  private func failure(_ error: AppleProductivityError) -> CallTool.Result {
    let envelope = ErrorEnvelope(error)
    let text =
      (try? String(decoding: ProductivityCoding.encoder().encode(envelope), as: UTF8.self))
      ?? #"{"schema_version":"1","ok":false,"error":{"code":"encoding_failure","message":"Could not encode error"}}"#
    return
      (try? .init(
        content: [.text(text: text, annotations: nil, _meta: nil)],
        structuredContent: envelope,
        isError: true
      )) ?? .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
  }
}

private struct DeleteResponse: Codable {
  let deleted: Bool
  let id: String
}

extension Dictionary where Key == String, Value == MCP.Value {
  fileprivate func string(_ key: String) -> String? { self[key]?.stringValue }
  fileprivate func integer(_ key: String) -> Int? { self[key]?.intValue }
  fileprivate func boolean(_ key: String) -> Bool? { self[key]?.boolValue }

  fileprivate func requiredString(_ key: String) throws -> String {
    guard let result = string(key), !result.isEmpty else {
      throw AppleProductivityError.invalidArguments("Missing required string argument '\(key)'.")
    }
    return result
  }

  fileprivate func date(_ key: String) throws -> Date? {
    guard let raw = string(key) else { return nil }
    return try FlexibleDateParser.parse(raw)
  }

  fileprivate func url(_ key: String) throws -> URL? {
    guard let raw = string(key) else { return nil }
    guard let result = URL(string: raw), result.scheme != nil else {
      throw AppleProductivityError.invalidArguments("Argument '\(key)' must be an absolute URL.")
    }
    return result
  }

  fileprivate func requireConfirmation() throws {
    guard boolean("confirm") == true else {
      throw AppleProductivityError.invalidArguments(
        "This destructive operation requires confirm=true.")
    }
  }
}

extension MCPServerRunner {
  fileprivate static let tools: [Tool] = [
    tool("notes_accounts", "List Apple Notes accounts.", properties: [:]),
    tool(
      "notes_folders", "List Apple Notes folders and stable IDs.",
      properties: [
        "account": string("Exact account name.")
      ]),
    tool(
      "notes_list", "List note metadata without bodies. Results are bounded.",
      properties: noteFilters),
    tool(
      "notes_get", "Read one note by stable ID, including HTML and plaintext.",
      properties: idProperty, required: ["id"]),
    tool(
      "notes_search", "Search note titles and plaintext content.",
      properties: noteFilters.merging([
        "query": string("Text to search for.")
      ]) { _, new in new }, required: ["query"]),
    tool(
      "notes_create", "Create a plaintext Apple Note.",
      properties: [
        "title": string("Note title."), "content": string("Plaintext body."),
        "account": string("Exact account name."),
        "folder": string("Folder path such as Work/Projects."),
      ], required: ["title"]),
    tool(
      "notes_append", "Append plaintext without replacing existing rich content.",
      properties: [
        "id": string("Stable note ID."), "content": string("Plaintext to append."),
      ], required: ["id", "content"]),
    tool(
      "notes_update",
      "Replace a note title and/or body. Use append when rich-content preservation matters.",
      properties: [
        "id": string("Stable note ID."), "title": string("Replacement title."),
        "content": string("Replacement plaintext body."),
        "if_modified_at": string(
          "Optional optimistic-concurrency ISO-8601 timestamp from notes_get."),
      ], required: ["id"]),
    tool(
      "notes_move", "Move a note to an existing folder.",
      properties: [
        "id": string("Stable note ID."), "account": string("Destination account."),
        "folder": string("Destination folder path."),
      ], required: ["id", "folder"]),
    tool(
      "notes_delete", "Move a note to Recently Deleted. Requires explicit confirmation.",
      properties: destructiveID, required: ["id", "confirm"]),
    tool("reminders_lists", "List Apple Reminders lists and stable IDs.", properties: [:]),
    tool("reminders_list", "List reminders with bounded output.", properties: reminderFilters),
    tool(
      "reminders_get", "Read one reminder by stable ID.", properties: idProperty, required: ["id"]),
    tool(
      "reminders_search", "Search reminder titles, notes, and URLs.",
      properties: reminderFilters.merging([
        "query": string("Text to search for.")
      ]) { _, new in new }, required: ["query"]),
    tool(
      "reminders_create", "Create a reminder using public EventKit.",
      properties: reminderMutation.merging([
        "title": string("Reminder title.")
      ]) { _, new in new }, required: ["title"]),
    tool(
      "reminders_update", "Update a reminder by stable ID.",
      properties: reminderMutation.merging([
        "id": string("Stable reminder ID."),
        "if_completed": boolean("Optional expected completion state for conflict detection."),
      ]) { _, new in new }, required: ["id"]),
    tool(
      "reminders_complete", "Mark a reminder complete.", properties: idProperty, required: ["id"]),
    tool(
      "reminders_reopen", "Mark a completed reminder incomplete.", properties: idProperty,
      required: ["id"]),
    tool(
      "reminders_delete", "Permanently delete a reminder. Requires explicit confirmation.",
      properties: destructiveID, required: ["id", "confirm"]),
  ]

  fileprivate static let idProperty: [String: MCP.Value] = [
    "id": string("Stable item ID returned by a read tool.")
  ]
  fileprivate static let destructiveID: [String: MCP.Value] = [
    "id": string("Stable item ID returned by a read tool."),
    "confirm": boolean("Must be true after the user confirms deletion."),
  ]
  fileprivate static let noteFilters: [String: MCP.Value] = [
    "account": string("Exact account name."), "folder": string("Folder name or path."),
    "limit": integer("Maximum results, 1 through 1000.", minimum: 1, maximum: 1000),
  ]
  fileprivate static let reminderFilters: [String: MCP.Value] = [
    "list": string("Exact list name or stable list ID."),
    "include_completed": boolean("Include completed reminders."),
    "limit": integer("Maximum results, 1 through 1000.", minimum: 1, maximum: 1000),
  ]
  fileprivate static let reminderMutation: [String: MCP.Value] = [
    "list": string("Exact destination list name or stable list ID."),
    "notes": string("Reminder notes."), "url": string("Absolute URL."),
    "due_at": string("ISO-8601, yyyy-MM-dd, yyyy-MM-dd HH:mm, today, or tomorrow."),
    "priority": integer("EventKit priority from 0 through 9.", minimum: 0, maximum: 9),
  ]

  fileprivate static func tool(
    _ name: String,
    _ description: String,
    properties: [String: MCP.Value],
    required: [String] = []
  ) -> Tool {
    var schema: [String: MCP.Value] = [
      "type": "object",
      "properties": .object(properties),
      "additionalProperties": false,
    ]
    if !required.isEmpty { schema["required"] = .array(required.map(MCP.Value.string)) }
    return Tool(name: name, description: description, inputSchema: .object(schema))
  }

  fileprivate static func string(_ description: String) -> MCP.Value {
    .object(["type": "string", "description": .string(description)])
  }

  fileprivate static func boolean(_ description: String) -> MCP.Value {
    .object(["type": "boolean", "description": .string(description)])
  }

  fileprivate static func integer(_ description: String, minimum: Int, maximum: Int) -> MCP.Value {
    .object([
      "type": "integer", "description": .string(description),
      "minimum": .int(minimum), "maximum": .int(maximum),
    ])
  }
}
