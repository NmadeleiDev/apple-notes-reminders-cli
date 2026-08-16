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
    let service = NotesService(
      executor: executor,
      applicationLocator: StubNotesApplicationLocator(path: "/System/Applications/Notes.app")
    )

    _ = try await service.create(title: "Safe", content: hostile, account: nil, folder: nil)
    let record = try #require(await executor.record)
    #expect(!record.script.contains(hostile))
    #expect(record.script.contains(#"Application(argv[2])"#))
    #expect(record.arguments[2] == "/System/Applications/Notes.app")
    let payload = try #require(
      JSONSerialization.jsonObject(with: Data(record.arguments[1].utf8)) as? [String: Any])
    #expect(payload["content"] as? String == hostile)
  }

  @Test("Notes search normalizes punctuation and connector-word-tolerant tokens")
  func notesSearchEmitsNormalizedTokens() async throws {
    let executor = RecordingOSAExecutor(response: "[]")
    let service = NotesService(
      executor: executor,
      applicationLocator: StubNotesApplicationLocator(path: "/System/Applications/Notes.app")
    )

    _ = try await service.search(
      query: "Проект анализ данных",
      account: nil,
      folder: nil,
      limit: 10
    )

    let record = try #require(await executor.record)
    let payload = try #require(
      JSONSerialization.jsonObject(with: Data(record.arguments[1].utf8)) as? [String: Any])
    #expect(
      payload["queryTokens"] as? [String]
        == ["проект", "анализ", "данных"])
  }

  @Test("Notes automation retries one cold-start application-resolution failure")
  func notesAutomationRetriesColdStartFailure() async throws {
    let runner = SequencedOSAProcessRunner(results: [
      OSAProcessResult(
        standardOutput: Data(),
        standardError: Data("execution error: Application can't be found. (-2700)".utf8),
        terminationStatus: 1
      ),
      OSAProcessResult(
        standardOutput: Data("[]".utf8),
        standardError: Data(),
        terminationStatus: 0
      ),
    ])
    let executor = ProcessOSAExecutor(
      processRunner: runner,
      coldStartRetryDelayNanoseconds: 0
    )

    let output = try await executor.execute(script: "", arguments: [])

    #expect(String(data: output, encoding: .utf8) == "[]")
    #expect(await runner.callCount == 2)
  }

  @Test("Notes automation does not retry permission failures")
  func notesAutomationDoesNotRetryPermissionFailure() async throws {
    let runner = SequencedOSAProcessRunner(results: [
      OSAProcessResult(
        standardOutput: Data(),
        standardError: Data("Not authorized to send Apple events. (-1743)".utf8),
        terminationStatus: 1
      )
    ])
    let executor = ProcessOSAExecutor(
      processRunner: runner,
      coldStartRetryDelayNanoseconds: 0
    )

    await #expect(throws: AppleProductivityError.self) {
      _ = try await executor.execute(script: "", arguments: [])
    }
    #expect(await runner.callCount == 1)
  }

  @Test("Notes rejects unbounded limits before invoking automation")
  func notesRejectsUnboundedLimitBeforeAutomation() async throws {
    let executor = RecordingOSAExecutor(response: "[]")
    let service = NotesService(
      executor: executor,
      applicationLocator: StubNotesApplicationLocator(path: "/System/Applications/Notes.app")
    )
    await #expect(throws: AppleProductivityError.self) {
      _ = try await service.list(account: nil, folder: nil, limit: 1_001)
    }
    #expect(await executor.record == nil)
  }

  @Test("Notes reports an unavailable application before invoking automation")
  func notesReportsUnavailableApplication() async throws {
    let executor = RecordingOSAExecutor(response: "[]")
    let service = NotesService(
      executor: executor,
      applicationLocator: StubNotesApplicationLocator(path: nil)
    )

    await #expect(throws: AppleProductivityError.self) {
      _ = try await service.accounts()
    }
    #expect(await executor.record == nil)
  }
}

private struct StubNotesApplicationLocator: NotesApplicationLocating {
  let path: String?

  func applicationPath() -> String? { path }
}

private actor SequencedOSAProcessRunner: OSAProcessRunning {
  private var results: [OSAProcessResult]
  private(set) var callCount = 0

  init(results: [OSAProcessResult]) { self.results = results }

  func run(executableURL: URL, arguments: [String], standardInput: Data) async throws
    -> OSAProcessResult
  {
    callCount += 1
    return results.removeFirst()
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
