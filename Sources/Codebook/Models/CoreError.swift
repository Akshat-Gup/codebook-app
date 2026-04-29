import Foundation

enum CodebookError: LocalizedError {
    case gitUnavailable
    case invalidRepository(String)
    case noLocalChanges(String)
    case malformedPrompt(String)
    case automation(String)
    case sqlite(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "Git is unavailable on this machine."
        case .invalidRepository(let path):
            return "\(path) is not a valid Git repository."
        case .noLocalChanges(let repositoryName):
            return "No local changes found in \(repositoryName)."
        case .malformedPrompt(let message):
            return message
        case .automation(let message):
            return message
        case .sqlite(let message):
            return message
        case .network(let message):
            return message
        }
    }
}
