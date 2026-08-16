import Foundation

public enum ProductivityCoding {
  public static func encoder(pretty: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting =
      pretty
      ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      : [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public struct SuccessEnvelope<Value: Codable>: Codable {
  public let schemaVersion = AppleProductivitySchema.version
  public let ok = true
  public let data: Value

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case ok
    case data
  }

  public init(data: Value) { self.data = data }
}

public struct ErrorDetail: Codable {
  public let code: String
  public let message: String
}

public struct ErrorEnvelope: Codable {
  public let schemaVersion = AppleProductivitySchema.version
  public let ok = false
  public let error: ErrorDetail

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case ok
    case error
  }

  public init(_ error: AppleProductivityError) {
    self.error = ErrorDetail(code: error.code, message: error.localizedDescription)
  }
}

public enum FlexibleDateParser {
  public static func parse(_ value: String, now: Date = Date(), calendar: Calendar = .current)
    throws -> Date
  {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "now": return now
    case "today": return calendar.startOfDay(for: now)
    case "tomorrow":
      guard let result = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
      else {
        throw AppleProductivityError.invalidArguments(
          "Could not calculate tomorrow in the current calendar.")
      }
      return result
    default: break
    }

    let isoWithFraction = ISO8601DateFormatter()
    isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoWithFraction.date(from: value) { return date }

    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }

    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      if let date = formatter.date(from: value) { return date }
    }

    throw AppleProductivityError.invalidArguments(
      "Invalid date '\(value)'. Use ISO-8601, yyyy-MM-dd, yyyy-MM-dd HH:mm, today, tomorrow, or now."
    )
  }
}
