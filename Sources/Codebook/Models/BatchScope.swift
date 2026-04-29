import Foundation

enum BatchScope: Hashable, Sendable {
    case commit(sha: String)
    case day(key: String)
    case thread(key: String)
    case repo
}
