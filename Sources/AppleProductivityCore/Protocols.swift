import Foundation

public protocol NotesServing: Sendable {
  func permissionStatus() async -> String
  func authorize() async throws -> Bool
  func accounts() async throws -> [NoteAccount]
  func folders(account: String?) async throws -> [NoteFolder]
  func list(account: String?, folder: String?, limit: Int) async throws -> [NoteItem]
  func get(id: String) async throws -> NoteItem
  func search(query: String, account: String?, folder: String?, limit: Int) async throws
    -> [NoteItem]
  func create(title: String, content: String, account: String?, folder: String?) async throws
    -> NoteItem
  func append(id: String, content: String) async throws -> NoteItem
  func update(id: String, title: String?, content: String?, ifModifiedAt: Date?) async throws
    -> NoteItem
  func move(id: String, account: String?, folder: String) async throws -> NoteItem
  func delete(id: String) async throws
}

public protocol RemindersServing: Sendable {
  func permissionStatus() async -> String
  func authorize() async throws -> Bool
  func lists() async throws -> [ReminderListItem]
  func list(list: String?, includeCompleted: Bool, limit: Int) async throws -> [ReminderItem]
  func get(id: String) async throws -> ReminderItem
  func search(query: String, list: String?, includeCompleted: Bool, limit: Int) async throws
    -> [ReminderItem]
  func create(title: String, list: String?, notes: String?, url: URL?, dueAt: Date?, priority: Int)
    async throws -> ReminderItem
  func update(
    id: String, title: String?, list: String?, notes: String?, url: URL?, dueAt: Date?,
    priority: Int?, ifCompleted: Bool?
  ) async throws -> ReminderItem
  func setCompleted(id: String, completed: Bool) async throws -> ReminderItem
  func delete(id: String) async throws
}
