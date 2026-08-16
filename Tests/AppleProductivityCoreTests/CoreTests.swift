import Foundation
import Testing

@testable import AppleProductivityCore

@Suite("Core contracts")
struct CoreTests {
  @Test("Flexible dates parse ISO-8601")
  func flexibleDateParsesISO8601() throws {
    let date = try FlexibleDateParser.parse("2026-08-17T10:30:00Z")
    #expect(ISO8601DateFormatter().string(from: date) == "2026-08-17T10:30:00Z")
  }

  @Test("Success envelopes expose a versioned snake-case schema")
  func successEnvelopeUsesVersionedSnakeCaseSchema() throws {
    let data = try ProductivityCoding.encoder().encode(SuccessEnvelope(data: ["value": 1]))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["schema_version"] as? String == "1")
    #expect(object["ok"] as? Bool == true)
  }

  @Test("Notes values travel as arguments and are never interpolated into OSA source")
  func notesPayloadPassesContentAsArgument() async throws {
    let hostile = "\"; Application('Finder').quit(); //"
    let executor = RecordingOSAExecutor(
      response:
        #"{"id":"test","title":"Safe","account":null,"folder":null,"createdAt":null,"modifiedAt":null,"bodyHTML":"","plaintext":"","passwordProtected":false}"#
    )
    let service = NotesService(executor: executor)

    _ = try await service.create(title: "Safe", content: hostile, account: nil, folder: nil)
    let record = try #require(await executor.record)
    #expect(!record.script.contains(hostile))
    let payload = try #require(
      JSONSerialization.jsonObject(with: Data(record.arguments[1].utf8)) as? [String: Any])
    #expect(payload["content"] as? String == hostile)
  }

  @Test("Notes rejects unbounded limits before invoking automation")
  func notesRejectsUnboundedLimitBeforeAutomation() async throws {
    let executor = RecordingOSAExecutor(response: "[]")
    let service = NotesService(executor: executor)
    await #expect(throws: AppleProductivityError.self) {
      _ = try await service.list(account: nil, folder: nil, limit: 1_001)
    }
    #expect(await executor.record == nil)
  }
}

private actor RecordingOSAExecutor: OSAExecuting {
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
