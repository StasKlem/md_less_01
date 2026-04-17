import Foundation

struct FileSystemProjectWorkspaceRepository: ProjectWorkspaceRepositoryProtocol {
    let rootDirectory: URL

    func readFile(relativePath: String) throws -> ProjectFileReadResult {
        let fileURL = try resolveFileURL(relativePath: relativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ProjectWorkspaceError.fileOperationFailed("File not found: \(relativePath)")
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return ProjectFileReadResult(
                relativePath: relativePath,
                content: content,
                lineCount: content.lineCount
            )
        } catch {
            throw ProjectWorkspaceError.fileOperationFailed("Failed to read file \(relativePath).")
        }
    }

    func searchFiles(query: String, files: [ProjectFile]) throws -> ProjectFileSearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw ProjectWorkspaceError.invalidSearchQuery
        }

        let loweredQuery = trimmedQuery.lowercased()
        var matches: [ProjectFileSearchMatch] = []
        let maximumMatches = 200

        for file in files {
            guard matches.count < maximumMatches else {
                return ProjectFileSearchResult(query: trimmedQuery, matches: matches, isTruncated: true)
            }

            let content: String
            do {
                content = try readFile(relativePath: file.relativePath).content
            } catch {
                continue
            }

            for (index, line) in content.lines.enumerated() {
                let haystack = line.lowercased()
                guard haystack.contains(loweredQuery) else {
                    continue
                }

                matches.append(
                    ProjectFileSearchMatch(
                        relativePath: file.relativePath,
                        lineNumber: index + 1,
                        lineText: line
                    )
                )

                if matches.count >= maximumMatches {
                    return ProjectFileSearchResult(query: trimmedQuery, matches: matches, isTruncated: true)
                }
            }
        }

        return ProjectFileSearchResult(query: trimmedQuery, matches: matches, isTruncated: false)
    }

    func writeFile(relativePath: String, contents: String) throws -> ProjectFileWriteResult {
        let fileURL = try resolveFileURL(relativePath: relativePath)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let previousContent = fileExists ? (try? String(contentsOf: fileURL, encoding: .utf8)) : nil

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ProjectWorkspaceError.fileOperationFailed("Failed to write file \(relativePath).")
        }

        let changed = previousContent != contents
        let diff = changed ? unifiedDiff(oldContent: previousContent, newContent: contents, relativePath: relativePath) : ""

        return ProjectFileWriteResult(
            relativePath: relativePath,
            created: !fileExists,
            changed: changed,
            diff: diff
        )
    }

    private func resolveFileURL(relativePath: String) throws -> URL {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw ProjectWorkspaceError.invalidRelativePath(relativePath)
        }

        let resolvedRoot = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        let fileURL = rootDirectory
            .appendingPathComponent(trimmedPath)
            .standardizedFileURL

        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : "\(resolvedRoot.path)/"
        guard fileURL.path == resolvedRoot.path || fileURL.path.hasPrefix(rootPath) else {
            throw ProjectWorkspaceError.invalidRelativePath(relativePath)
        }

        return fileURL
    }

    private func unifiedDiff(oldContent: String?, newContent: String, relativePath: String) -> String {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectMCPServer-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )

            let oldURL = temporaryDirectory.appendingPathComponent("old.txt")
            let newURL = temporaryDirectory.appendingPathComponent("new.txt")

            try (oldContent ?? "").write(to: oldURL, atomically: true, encoding: .utf8)
            try newContent.write(to: newURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = [
                "diff",
                "--no-index",
                "--no-ext-diff",
                "--unified=3",
                "--",
                oldURL.path,
                newURL.path
            ]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return ""
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
                return ""
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let rawDiff = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !rawDiff.isEmpty else {
                return ""
            }

            return rawDiff.replacingOccurrences(of: "a\(oldURL.path)", with: "a/\(relativePath)")
                .replacingOccurrences(of: "b\(newURL.path)", with: "b/\(relativePath)")
        } catch {
            return ""
        }
    }
}

private extension String {
    var lineCount: Int {
        guard !isEmpty else {
            return 0
        }

        return split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var lines: [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
