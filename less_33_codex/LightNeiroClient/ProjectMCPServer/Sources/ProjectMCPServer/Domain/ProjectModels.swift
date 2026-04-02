import Foundation

struct ProjectFile: Sendable, Equatable {
    let relativePath: String
}

struct ProjectUncommittedChanges: Sendable, Equatable {
    let files: [ProjectFile]
    let diff: String
}
