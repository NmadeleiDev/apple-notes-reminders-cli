import Foundation

public enum AppleProductivityError: Error, Equatable, Sendable {
  case invalidArguments(String)
  case permissionDenied(service: String, recovery: String)
  case notFound(kind: String, identifier: String)
  case ambiguous(kind: String, query: String, matches: [String])
  case conflict(String)
  case backend(service: String, message: String)
  case unsupported(String)
}

extension AppleProductivityError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidArguments(let message): message
    case .permissionDenied(let service, let recovery):
      "Permission denied for \(service). \(recovery)"
    case .notFound(let kind, let identifier): "No \(kind) found for identifier '\(identifier)'."
    case .ambiguous(let kind, let query, let matches):
      "Ambiguous \(kind) query '\(query)'; matches: \(matches.joined(separator: ", "))."
    case .conflict(let message): message
    case .backend(let service, let message): "\(service) backend failed: \(message)"
    case .unsupported(let message): message
    }
  }

  public var code: String {
    switch self {
    case .invalidArguments: "invalid_arguments"
    case .permissionDenied: "permission_denied"
    case .notFound: "not_found"
    case .ambiguous: "ambiguous"
    case .conflict: "conflict"
    case .backend: "backend_failure"
    case .unsupported: "unsupported"
    }
  }

  public var exitCode: Int32 {
    switch self {
    case .invalidArguments: 2
    case .permissionDenied: 3
    case .notFound: 4
    case .ambiguous: 5
    case .conflict: 6
    case .backend: 7
    case .unsupported: 8
    }
  }
}

extension Error {
  public var appleProductivityError: AppleProductivityError {
    if let error = self as? AppleProductivityError { return error }
    return .backend(service: "unknown", message: localizedDescription)
  }
}
