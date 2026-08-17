import AppleProductivityCore
import Foundation

@main
struct ContractTests {
  static func main() async {
    do {
      try testFlexibleDate()
      try testEnvelope()
      try await testNotesArgumentIsolation()
      try await testBoundedNotesRead()
      try await testRelaxedNotesSearchPayload()
      try await testNotesColdStartRetry()
      print("6 contract tests passed")
    } catch {
      FileHandle.standardError.write(Data("contract test failed: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }

  static func testFlexibleDate() throws {
    let date = try FlexibleDateParser.parse("2026-08-17T10:30:00Z")
    try require(
      ISO8601DateFormatter().string(from: date) == "2026-08-17T10:30:00Z", "ISO-8601 parsing")
  }

  static func testEnvelope() throws {
    let data = try ProductivityCoding.encoder().encode(SuccessEnvelope(data: ["value": 1]))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    try require(object?["schema_version"] as? String == "1", "schema version")
    try require(object?["ok"] as? Bool == true, "success state")
  }

  static func testNotesArgumentIsolation() async throws {
    let hostile = "\"; Application('Finder').quit(); //"
    let executor = RecordingExecutor(
      response:
        #"{"id":"test","title":"Safe","account":null,"folder":null,"createdAt":null,"modifiedAt":null,"bodyHTML":"","plaintext":"","passwordProtected":false}"#
    )
    let service = NotesService(executor: executor)
    _ = try await service.create(title: "Safe", content: hostile, account: nil, folder: nil)
    guard let record = await executor.record else {
      throw ContractFailure("automation was not invoked")
    }
    try require(!record.script.contains(hostile), "content must not enter executable OSA source")
    try require(
      record.script.contains(#"Application(argv[2])"#),
      "Notes must receive its resolved application path as data")
    try require(
      record.arguments.count == 3 && record.arguments[2].hasSuffix("/Notes.app"),
      "Notes must resolve its installed application path")
    let payload =
      try JSONSerialization.jsonObject(with: Data(record.arguments[1].utf8)) as? [String: Any]
    try require(payload?["content"] as? String == hostile, "content must travel as serialized data")
  }

  static func testBoundedNotesRead() async throws {
    let executor = RecordingExecutor(response: "[]")
    let service = NotesService(executor: executor)
    do {
      _ = try await service.list(account: nil, folder: nil, limit: 1_001)
      throw ContractFailure("unbounded read was accepted")
    } catch is AppleProductivityError {
      let record = await executor.record
      try require(record == nil, "invalid read must fail before automation")
    }
  }

  static func testRelaxedNotesSearchPayload() async throws {
    let executor = RecordingExecutor(response: "[]")
    let service = NotesService(executor: executor)
    _ = try await service.search(
      query: "Проект анализ данных",
      account: nil,
      folder: nil,
      limit: 10
    )
    guard let record = await executor.record else {
      throw ContractFailure("search automation was not invoked")
    }
    let payload =
      try JSONSerialization.jsonObject(with: Data(record.arguments[1].utf8)) as? [String: Any]
    try require(
      payload?["queryTokens"] as? [String]
        == ["проект", "анализ", "данных"],
      "search must emit Unicode-normalized tokens")
  }

  static func testNotesColdStartRetry() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-notes-reminders-contract-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("mock-osascript")
    let script = #"""
      #!/bin/sh
      state="${0}.state"
      if [ ! -f "$state" ]; then
        : > "$state"
        printf '%s\n' "execution error: Application can't be found. (-2700)" >&2
        exit 1
      fi
      printf '[]'
      """#
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: executable.path
    )

    let executor = ProcessOSAExecutor(executableURL: executable)
    let output = try await executor.execute(script: "", arguments: [])

    try require(String(data: output, encoding: .utf8) == "[]", "cold-start retry output")
    try require(
      FileManager.default.fileExists(atPath: executable.path + ".state"),
      "cold-start failure must execute before the successful retry")
  }

  static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ContractFailure(message) }
  }
}

private struct ContractFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

private actor RecordingExecutor: OSAExecuting {
  struct Record: Sendable {
    let script: String
    let arguments: [String]
  }
  private(set) var record: Record?
  let response: String

  init(response: String) { self.response = response }

  func execute(script: String, arguments: [String]) async throws -> Data {
    record = Record(script: script, arguments: arguments)
    return Data(response.utf8)
  }
}
