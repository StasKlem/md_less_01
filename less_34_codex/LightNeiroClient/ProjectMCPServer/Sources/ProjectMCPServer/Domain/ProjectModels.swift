import Foundation

struct ProjectFile: Sendable, Equatable {
    let relativePath: String
}

struct ProjectUncommittedChanges: Sendable, Equatable {
    let files: [ProjectFile]
    let diff: String
}

struct ProjectFileReadResult: Sendable, Equatable {
    let relativePath: String
    let content: String
    let lineCount: Int
}

struct ProjectFileSearchMatch: Sendable, Codable, Equatable {
    let relativePath: String
    let lineNumber: Int
    let lineText: String
}

struct ProjectFileSearchResult: Sendable, Equatable {
    let query: String
    let matches: [ProjectFileSearchMatch]
    let isTruncated: Bool
}

struct ProjectFileWriteResult: Sendable, Equatable {
    let relativePath: String
    let created: Bool
    let changed: Bool
    let diff: String
}
