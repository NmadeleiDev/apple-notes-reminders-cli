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
      print("4 contract tests passed")
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
