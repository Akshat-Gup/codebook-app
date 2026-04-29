import Foundation

struct DiagramMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}
