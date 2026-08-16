import Foundation

public enum AppleProductivitySchema {
  public static let version = "1"
}

public struct NoteAccount: Codable, Equatable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct NoteFolder: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let account: String

  public init(id: String, name: String, path: String, account: String) {
    self.id = id
    self.name = name
    self.path = path
    self.account = account
  }
}

public struct NoteItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let account: String?
  public let folder: String?
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let bodyHTML: String?
  public let plaintext: String?
  public let passwordProtected: Bool

  public init(
    id: String,
    title: String,
    account: String? = nil,
    folder: String? = nil,
    createdAt: Date? = nil,
    modifiedAt: Date? = nil,
    bodyHTML: String? = nil,
    plaintext: String? = nil,
    passwordProtected: Bool = false
  ) {
    self.id = id
    self.title = title
    self.account = account
    self.folder = folder
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.bodyHTML = bodyHTML
    self.plaintext = plaintext
    self.passwordProtected = passwordProtected
  }
}

public struct ReminderListItem: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let source: String?

  public init(id: String, name: String, source: String? = nil) {
    self.id = id
    self.name = name
    self.source = source
  }
}

public struct ReminderItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let listID: String
  public let list: String
  public let notes: String?
  public let url: URL?
  public let dueAt: Date?
  public let completedAt: Date?
  public let isCompleted: Bool
  public let priority: Int

  public init(
    id: String,
    title: String,
    listID: String,
    list: String,
    notes: String? = nil,
    url: URL? = nil,
    dueAt: Date? = nil,
    completedAt: Date? = nil,
    isCompleted: Bool = false,
    priority: Int = 0
  ) {
    self.id = id
    self.title = title
    self.listID = listID
    self.list = list
    self.notes = notes
    self.url = url
    self.dueAt = dueAt
    self.completedAt = completedAt
    self.isCompleted = isCompleted
    self.priority = priority
  }
}

public struct PermissionState: Codable, Equatable, Sendable {
  public let notesAutomation: String
  public let reminders: String

  public init(notesAutomation: String, reminders: String) {
    self.notesAutomation = notesAutomation
    self.reminders = reminders
  }
}

public struct DoctorReport: Codable, Equatable, Sendable {
  public let healthy: Bool
  public let permissions: PermissionState
  public let notesAccounts: Int?
  public let reminderLists: Int?
  public let warnings: [String]

  public init(
    healthy: Bool,
    permissions: PermissionState,
    notesAccounts: Int?,
    reminderLists: Int?,
    warnings: [String]
  ) {
    self.healthy = healthy
    self.permissions = permissions
    self.notesAccounts = notesAccounts
    self.reminderLists = reminderLists
    self.warnings = warnings
  }
}

public struct MutationPreview: Codable, Equatable, Sendable {
  public let operation: String
  public let targetID: String?
  public let changes: [String: String]

  public init(operation: String, targetID: String? = nil, changes: [String: String]) {
    self.operation = operation
    self.targetID = targetID
    self.changes = changes
  }
}
