import Foundation

public protocol OSAExecuting: Sendable {
  func execute(script: String, arguments: [String]) async throws -> Data
}

public actor ProcessOSAExecutor: OSAExecuting {
  private let executableURL: URL
  private let maximumOutputBytes: Int

  public init(
    executableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript"),
    maximumOutputBytes: Int = 16 * 1_024 * 1_024
  ) {
    self.executableURL = executableURL
    self.maximumOutputBytes = maximumOutputBytes
  }

  public func execute(script: String, arguments: [String]) async throws -> Data {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["-l", "JavaScript", "-"] + arguments

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error

    do {
      try process.run()
    } catch {
      throw AppleProductivityError.backend(
        service: "Notes", message: "Could not start osascript: \(error.localizedDescription)")
    }

    input.fileHandleForWriting.write(Data(script.utf8))
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()

    let stdout = output.fileHandleForReading.readDataToEndOfFile()
    let stderr = error.fileHandleForReading.readDataToEndOfFile()
    guard stdout.count <= maximumOutputBytes else {
      throw AppleProductivityError.backend(
        service: "Notes",
        message:
          "Automation output exceeded the \(maximumOutputBytes)-byte safety limit. Narrow the query."
      )
    }

    guard process.terminationStatus == 0 else {
      let message =
        String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "osascript exited with status \(process.terminationStatus)"
      if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
        throw AppleProductivityError.permissionDenied(
          service: "Notes Automation",
          recovery:
            "Allow the invoking application under System Settings > Privacy & Security > Automation."
        )
      }
      if message.contains("NOT_FOUND:") {
        let identifier = message.components(separatedBy: "NOT_FOUND:").last ?? "unknown"
        throw AppleProductivityError.notFound(kind: "note or folder", identifier: identifier)
      }
      if message.contains("AMBIGUOUS:") {
        throw AppleProductivityError.ambiguous(
          kind: "Notes destination", query: message, matches: [])
      }
      if message.contains("CONFLICT:") {
        throw AppleProductivityError.conflict(
          message.components(separatedBy: "CONFLICT:").last ?? message)
      }
      throw AppleProductivityError.backend(service: "Notes", message: message)
    }
    return stdout
  }
}

public actor NotesService: NotesServing {
  private let executor: any OSAExecuting
  private let encoder = JSONEncoder()
  private let decoder = ProductivityCoding.decoder()

  public init(executor: any OSAExecuting = ProcessOSAExecutor()) {
    self.executor = executor
  }

  public func permissionStatus() async -> String {
    do {
      _ = try await accounts()
      return "authorized"
    } catch let error as AppleProductivityError {
      if case .permissionDenied = error { return "denied" }
      return "unavailable"
    } catch {
      return "unavailable"
    }
  }

  public func authorize() async throws -> Bool {
    _ = try await accounts()
    return true
  }

  public func accounts() async throws -> [NoteAccount] {
    try await call("accounts", payload: EmptyPayload())
  }

  public func folders(account: String?) async throws -> [NoteFolder] {
    try await call("folders", payload: AccountPayload(account: account))
  }

  public func list(account: String?, folder: String?, limit: Int) async throws -> [NoteItem] {
    try validateLimit(limit)
    return try await call(
      "list", payload: ListNotesPayload(account: account, folder: folder, limit: limit))
  }

  public func get(id: String) async throws -> NoteItem {
    try await call("get", payload: IDPayload(id: id))
  }

  public func search(query: String, account: String?, folder: String?, limit: Int) async throws
    -> [NoteItem]
  {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleProductivityError.invalidArguments("Search query must not be empty.")
    }
    try validateLimit(limit)
    return try await call(
      "search",
      payload: SearchNotesPayload(query: query, account: account, folder: folder, limit: limit)
    )
  }

  public func create(title: String, content: String, account: String?, folder: String?) async throws
    -> NoteItem
  {
    try validateTitle(title)
    return try await call(
      "create",
      payload: CreateNotePayload(title: title, content: content, account: account, folder: folder)
    )
  }

  public func append(id: String, content: String) async throws -> NoteItem {
    guard !content.isEmpty else {
      throw AppleProductivityError.invalidArguments("Append content must not be empty.")
    }
    return try await call("append", payload: AppendNotePayload(id: id, content: content))
  }

  public func update(id: String, title: String?, content: String?, ifModifiedAt: Date?) async throws
    -> NoteItem
  {
    guard title != nil || content != nil else {
      throw AppleProductivityError.invalidArguments("Provide at least one of title or content.")
    }
    if let title { try validateTitle(title) }
    let formatter = ISO8601DateFormatter()
    return try await call(
      "update",
      payload: UpdateNotePayload(
        id: id,
        title: title,
        content: content,
        ifModifiedAt: ifModifiedAt.map(formatter.string(from:))
      )
    )
  }

  public func move(id: String, account: String?, folder: String) async throws -> NoteItem {
    guard !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleProductivityError.invalidArguments("Destination folder must not be empty.")
    }
    return try await call(
      "move", payload: MoveNotePayload(id: id, account: account, folder: folder))
  }

  public func delete(id: String) async throws {
    let _: DeleteResult = try await call("delete", payload: IDPayload(id: id))
  }

  private func call<Response: Decodable, Payload: Encodable>(
    _ operation: String,
    payload: Payload
  ) async throws -> Response {
    let payloadData = try encoder.encode(payload)
    guard let payloadString = String(data: payloadData, encoding: .utf8) else {
      throw AppleProductivityError.backend(
        service: "Notes", message: "Could not encode request payload.")
    }
    let data = try await executor.execute(
      script: Self.script, arguments: [operation, payloadString])
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      let raw = String(data: data.prefix(1_024), encoding: .utf8) ?? "<binary>"
      throw AppleProductivityError.backend(
        service: "Notes",
        message: "Invalid automation response: \(error.localizedDescription). Output: \(raw)"
      )
    }
  }

  private func validateLimit(_ limit: Int) throws {
    guard (1...1_000).contains(limit) else {
      throw AppleProductivityError.invalidArguments("Limit must be between 1 and 1000.")
    }
  }

  private func validateTitle(_ title: String) throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleProductivityError.invalidArguments("Title must not be empty.")
    }
  }
}

private struct EmptyPayload: Codable {}
private struct AccountPayload: Codable { let account: String? }
private struct IDPayload: Codable { let id: String }
private struct ListNotesPayload: Codable {
  let account: String?
  let folder: String?
  let limit: Int
}
private struct SearchNotesPayload: Codable {
  let query: String
  let account: String?
  let folder: String?
  let limit: Int
}
private struct CreateNotePayload: Codable {
  let title: String
  let content: String
  let account: String?
  let folder: String?
}
private struct AppendNotePayload: Codable {
  let id: String
  let content: String
}
private struct UpdateNotePayload: Codable {
  let id: String
  let title: String?
  let content: String?
  let ifModifiedAt: String?
}
private struct MoveNotePayload: Codable {
  let id: String
  let account: String?
  let folder: String
}
private struct DeleteResult: Codable {
  let deleted: Bool
  let id: String
}

extension NotesService {
  fileprivate static let script = #"""
    function run(argv) {
      const operation = argv[0];
      const args = JSON.parse(argv[1] || "{}");
      const notes = Application("Notes");

      function value(fn, fallback) {
        try { const result = fn(); return result === undefined || result === null ? fallback : result; }
        catch (_) { return fallback; }
      }

      function iso(value) {
        if (!value) return null;
        try { return new Date(value).toISOString(); } catch (_) { return null; }
      }

      function collectFolderContexts(container, accountName, prefix, contexts) {
        childFolders(container).forEach(folder => {
          const name = String(folder.name());
          const path = prefix ? prefix + "/" + name : name;
          contexts[String(folder.id())] = {account: accountName, folder: path};
          collectFolderContexts(folder, accountName, path, contexts);
        });
      }

      function buildFolderContexts() {
        const contexts = {};
        notes.accounts().forEach(account => {
          collectFolderContexts(account, String(account.name()), "", contexts);
        });
        return contexts;
      }

      const folderContexts = buildFolderContexts();

      function contextForNote(note) {
        const folderID = value(() => note.container().id(), null);
        return folderContexts[String(folderID)] || {
          account: value(() => note.container().name(), null),
          folder: null
        };
      }

      function noteObject(note, includeContent) {
        const context = contextForNote(note);
        return {
          id: String(note.id()),
          title: String(value(() => note.name(), "")),
          account: context.account,
          folder: context.folder,
          createdAt: iso(value(() => note.creationDate(), null)),
          modifiedAt: iso(value(() => note.modificationDate(), null)),
          bodyHTML: includeContent ? String(value(() => note.body(), "")) : null,
          plaintext: includeContent ? String(value(() => note.plaintext(), "")) : null,
          passwordProtected: Boolean(value(() => note.passwordProtected(), false))
        };
      }

      function allNotes() {
        return notes.notes();
      }

      function findNote(id) {
        const matches = allNotes().filter(note => String(value(() => note.id(), "")) === String(id));
        if (matches.length === 0) throw new Error("NOT_FOUND:" + id);
        return matches[0];
      }

      function findAccount(name) {
        const accounts = notes.accounts();
        if (!name) {
          const preferred = accounts.filter(account => String(account.name()).toLowerCase() === "icloud");
          return preferred[0] || accounts[0];
        }
        const exact = accounts.filter(account => String(account.name()) === String(name));
        if (exact.length === 0) throw new Error("NOT_FOUND:account:" + name);
        return exact[0];
      }

      function childFolders(container) {
        return value(() => container.folders(), []);
      }

      function collectFolders(container, accountName, prefix, output) {
        childFolders(container).forEach(folder => {
          const name = String(folder.name());
          const path = prefix ? prefix + "/" + name : name;
          output.push({id: String(folder.id()), name: name, path: path, account: accountName});
          collectFolders(folder, accountName, path, output);
        });
      }

      function findFolder(account, path) {
        if (!path) return account;
        let current = account;
        path.split("/").filter(Boolean).forEach(component => {
          const matches = childFolders(current).filter(folder => String(folder.name()) === component);
          if (matches.length === 0) throw new Error("NOT_FOUND:folder:" + path);
          if (matches.length > 1) throw new Error("AMBIGUOUS:folder:" + path);
          current = matches[0];
        });
        return current;
      }

      function escapeHTML(text) {
        return String(text)
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/\"/g, "&quot;")
          .replace(/'/g, "&#39;");
      }

      function paragraphHTML(text) {
        return escapeHTML(text).replace(/\n/g, "<br>");
      }

      function composeBody(title, content) {
        return "<h1>" + escapeHTML(title) + "</h1><div>" + paragraphHTML(content || "") + "</div>";
      }

      function filteredNotes(account, folder, query, limit) {
        const lowered = query ? String(query).toLowerCase() : null;
        const results = [];
        const candidates = allNotes();
        for (let index = 0; index < candidates.length && results.length < limit; index += 1) {
          const item = noteObject(candidates[index], Boolean(lowered));
          if (account && item.account !== account) continue;
          if (folder && item.folder !== folder && !(item.folder || "").endsWith("/" + folder)) continue;
          if (lowered && !item.title.toLowerCase().includes(lowered) && !(item.plaintext || "").toLowerCase().includes(lowered)) continue;
          if (!lowered) { item.bodyHTML = null; item.plaintext = null; }
          results.push(item);
        }
        return results;
      }

      let result;
      if (operation === "accounts") {
        result = notes.accounts().map(account => ({id: String(account.id()), name: String(account.name())}));
      } else if (operation === "folders") {
        result = [];
        const accounts = args.account ? [findAccount(args.account)] : notes.accounts();
        accounts.forEach(account => collectFolders(account, String(account.name()), "", result));
      } else if (operation === "list") {
        result = filteredNotes(args.account, args.folder, null, args.limit);
      } else if (operation === "search") {
        result = filteredNotes(args.account, args.folder, args.query, args.limit);
      } else if (operation === "get") {
        result = noteObject(findNote(args.id), true);
      } else if (operation === "create") {
        const account = findAccount(args.account);
        const destination = findFolder(account, args.folder);
        const created = notes.Note({body: composeBody(args.title, args.content)});
        destination.notes.push(created);
        delay(0.2);
        result = noteObject(created, true);
      } else if (operation === "append") {
        const note = findNote(args.id);
        note.body = String(note.body()) + "<div>" + paragraphHTML(args.content) + "</div>";
        delay(0.1);
        result = noteObject(note, true);
      } else if (operation === "update") {
        const note = findNote(args.id);
        if (args.ifModifiedAt) {
          const actual = new Date(note.modificationDate()).getTime();
          const expected = new Date(args.ifModifiedAt).getTime();
          if (Math.abs(actual - expected) > 1000) throw new Error("CONFLICT:note modified since supplied timestamp");
        }
        const title = args.title === null ? String(note.name()) : args.title;
        const content = args.content === null ? String(note.plaintext()).split("\n").slice(1).join("\n") : args.content;
        note.body = composeBody(title, content);
        delay(0.1);
        result = noteObject(note, true);
      } else if (operation === "move") {
        const note = findNote(args.id);
        const account = findAccount(args.account);
        const destination = findFolder(account, args.folder);
        notes.move(note, {to: destination});
        delay(0.1);
        result = noteObject(findNote(args.id), true);
      } else if (operation === "delete") {
        const note = findNote(args.id);
        notes.delete(note);
        result = {deleted: true, id: args.id};
      } else {
        throw new Error("Unsupported operation: " + operation);
      }

      return JSON.stringify(result);
    }
    """#
}
