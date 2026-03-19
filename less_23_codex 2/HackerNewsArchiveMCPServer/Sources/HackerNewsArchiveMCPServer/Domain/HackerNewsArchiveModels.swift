import Foundation

struct ArchivedHackerNewsFile: Sendable, Equatable {
    let fileName: String
    let savedAt: Date
    let json: String
}
