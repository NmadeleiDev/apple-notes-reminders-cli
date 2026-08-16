@preconcurrency import EventKit
import Foundation

public actor RemindersService: RemindersServing {
  private let store: EKEventStore
  private var calendar: Calendar

  public init(store: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
    self.store = store
    self.calendar = calendar
  }

  public func permissionStatus() async -> String {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .notDetermined: "not_determined"
    case .restricted: "restricted"
    case .denied: "denied"
    case .fullAccess: "full_access"
    case .writeOnly: "write_only"
    case .authorized: "authorized"
    @unknown default: "unknown"
    }
  }

  public func authorize() async throws -> Bool {
    do {
      return try await store.requestFullAccessToReminders()
    } catch {
      throw AppleProductivityError.permissionDenied(
        service: "Reminders",
        recovery: "Allow this executable under System Settings > Privacy & Security > Reminders."
      )
    }
  }

  public func lists() async throws -> [ReminderListItem] {
    try requireReadAccess()
    return store.calendars(for: .reminder)
      .map { ReminderListItem(id: $0.calendarIdentifier, name: $0.title, source: $0.source?.title) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func list(list: String?, includeCompleted: Bool, limit: Int) async throws -> [ReminderItem]
  {
    try validateLimit(limit)
    try requireReadAccess()
    let calendars = try resolveCalendars(list)
    let predicate = store.predicateForReminders(in: calendars)
    let reminders = try await fetch(predicate)
    return
      reminders
      .filter { includeCompleted || !$0.isCompleted }
      .sorted(by: Self.reminderSort)
      .prefix(limit)
      .map(Self.item)
  }

  public func get(id: String) async throws -> ReminderItem {
    try requireReadAccess()
    return Self.item(try reminder(id: id))
  }

  public func search(query: String, list: String?, includeCompleted: Bool, limit: Int) async throws
    -> [ReminderItem]
  {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleProductivityError.invalidArguments("Search query must not be empty.")
    }
    let lowered = query.localizedLowercase
    return try await self.list(list: list, includeCompleted: includeCompleted, limit: 1_000)
      .filter {
        $0.title.localizedLowercase.contains(lowered)
          || ($0.notes?.localizedLowercase.contains(lowered) ?? false)
          || ($0.url?.absoluteString.localizedLowercase.contains(lowered) ?? false)
      }
      .prefix(limit)
      .map { $0 }
  }

  public func create(
    title: String,
    list: String?,
    notes: String?,
    url: URL?,
    dueAt: Date?,
    priority: Int
  ) async throws -> ReminderItem {
    try validateTitle(title)
    try validatePriority(priority)
    try requireWriteAccess()

    let targetCalendar = try resolveCalendar(list)
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.calendar = targetCalendar
    reminder.notes = notes
    reminder.url = url
    reminder.priority = priority
    if let dueAt { reminder.dueDateComponents = dateComponents(for: dueAt) }

    do {
      try store.save(reminder, commit: true)
    } catch {
      throw AppleProductivityError.backend(
        service: "Reminders", message: error.localizedDescription)
    }
    return Self.item(reminder)
  }

  public func update(
    id: String,
    title: String?,
    list: String?,
    notes: String?,
    url: URL?,
    dueAt: Date?,
    priority: Int?,
    ifCompleted: Bool?
  ) async throws -> ReminderItem {
    try requireWriteAccess()
    let reminder = try reminder(id: id)
    if let expected = ifCompleted, reminder.isCompleted != expected {
      throw AppleProductivityError.conflict(
        "Reminder completion state changed: expected \(expected), found \(reminder.isCompleted)."
      )
    }
    if let title {
      try validateTitle(title)
      reminder.title = title
    }
    if let list { reminder.calendar = try resolveCalendar(list) }
    if let notes { reminder.notes = notes }
    if let url { reminder.url = url }
    if let dueAt { reminder.dueDateComponents = dateComponents(for: dueAt) }
    if let priority {
      try validatePriority(priority)
      reminder.priority = priority
    }

    do {
      try store.save(reminder, commit: true)
    } catch {
      throw AppleProductivityError.backend(
        service: "Reminders", message: error.localizedDescription)
    }
    return Self.item(reminder)
  }

  public func setCompleted(id: String, completed: Bool) async throws -> ReminderItem {
    try requireWriteAccess()
    let reminder = try reminder(id: id)
    reminder.isCompleted = completed
    reminder.completionDate = completed ? Date() : nil
    do {
      try store.save(reminder, commit: true)
    } catch {
      throw AppleProductivityError.backend(
        service: "Reminders", message: error.localizedDescription)
    }
    return Self.item(reminder)
  }

  public func delete(id: String) async throws {
    try requireWriteAccess()
    let reminder = try reminder(id: id)
    do {
      try store.remove(reminder, commit: true)
    } catch {
      throw AppleProductivityError.backend(
        service: "Reminders", message: error.localizedDescription)
    }
  }

  private func requireReadAccess() throws {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    guard status == .fullAccess else {
      throw AppleProductivityError.permissionDenied(
        service: "Reminders",
        recovery:
          "Run `apple-notes-reminders authorize reminders`, then allow access in System Settings if prompted."
      )
    }
  }

  private func requireWriteAccess() throws {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    guard status == .fullAccess || status == .writeOnly else {
      throw AppleProductivityError.permissionDenied(
        service: "Reminders",
        recovery:
          "Run `apple-notes-reminders authorize reminders`, then allow access in System Settings if prompted."
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

  private func validatePriority(_ priority: Int) throws {
    guard (0...9).contains(priority) else {
      throw AppleProductivityError.invalidArguments("Priority must be between 0 and 9.")
    }
  }

  private func fetch(_ predicate: NSPredicate) async throws -> [EKReminder] {
    let box: UnsafeSendableReminders = await withCheckedContinuation { continuation in
      store.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: UnsafeSendableReminders(reminders ?? []))
      }
    }
    return box.value
  }

  private func reminder(id: String) throws -> EKReminder {
    if let exact = store.calendarItem(withIdentifier: id) as? EKReminder { return exact }
    throw AppleProductivityError.notFound(kind: "reminder", identifier: id)
  }

  private func resolveCalendars(_ query: String?) throws -> [EKCalendar]? {
    guard let query else { return nil }
    return [try resolveCalendar(query)]
  }

  private func resolveCalendar(_ query: String?) throws -> EKCalendar {
    guard let query else {
      if let calendar = store.defaultCalendarForNewReminders() { return calendar }
      throw AppleProductivityError.notFound(kind: "default reminder list", identifier: "default")
    }
    let calendars = store.calendars(for: .reminder)
    if let byID = calendars.first(where: { $0.calendarIdentifier == query }) { return byID }
    let matches = calendars.filter {
      $0.title.localizedCaseInsensitiveCompare(query) == .orderedSame
    }
    if matches.count == 1, let match = matches.first { return match }
    if matches.count > 1 {
      throw AppleProductivityError.ambiguous(
        kind: "reminder list",
        query: query,
        matches: matches.map(\.calendarIdentifier)
      )
    }
    throw AppleProductivityError.notFound(kind: "reminder list", identifier: query)
  }

  private func dateComponents(for date: Date) -> DateComponents {
    var components = calendar.dateComponents(in: calendar.timeZone, from: date)
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    return components
  }

  private static func item(_ reminder: EKReminder) -> ReminderItem {
    let dueAt = reminder.dueDateComponents.flatMap { components -> Date? in
      var calendar = components.calendar ?? .current
      if let timeZone = components.timeZone { calendar.timeZone = timeZone }
      return calendar.date(from: components)
    }
    return ReminderItem(
      id: reminder.calendarItemIdentifier,
      title: reminder.title,
      listID: reminder.calendar.calendarIdentifier,
      list: reminder.calendar.title,
      notes: reminder.notes,
      url: reminder.url,
      dueAt: dueAt,
      completedAt: reminder.completionDate,
      isCompleted: reminder.isCompleted,
      priority: reminder.priority
    )
  }

  private static func reminderSort(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
    if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
    let leftDue = lhs.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    let rightDue = rhs.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    switch (leftDue, rightDue) {
    case (let left?, let right?) where left != right: return left < right
    case (_?, nil): return true
    case (nil, _?): return false
    default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
  }
}

private struct UnsafeSendableReminders: @unchecked Sendable {
  let value: [EKReminder]
  init(_ value: [EKReminder]) { self.value = value }
}
