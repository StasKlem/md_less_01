import Foundation

struct HackerNewsStoryInputParser {
    func parseMany(_ rawStories: [String]) throws -> [HackerNewsStoryForSummary] {
        try rawStories.enumerated().map { index, rawStory in
            do {
                return try parseOne(rawStory)
            } catch {
                if let error = error as? HackerNewsSummaryToolError {
                    throw HackerNewsSummaryToolError.parsingFailure("index \(index): \(error.localizedDescription)")
                }
                throw HackerNewsSummaryToolError.parsingFailure("index \(index): invalid format")
            }
        }
    }

    private func parseOne(_ rawStory: String) throws -> HackerNewsStoryForSummary {
        let normalized = rawStory
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            throw HackerNewsSummaryToolError.invalidArguments("Story text cannot be empty.")
        }

        let title = value(for: "- Title:", in: normalized)
        guard let title, !title.isEmpty else {
            throw HackerNewsSummaryToolError.invalidArguments("Story must include '- Title: ...'.")
        }

        let id = value(for: "- ID:", in: normalized).flatMap(Int.init)
        let author = value(for: "- Author:", in: normalized)
        let score = value(for: "- Score:", in: normalized).flatMap(Int.init)
        let time = value(for: "- Time:", in: normalized)
        let urlValue = value(for: "- URL:", in: normalized)
        let url = parseURL(urlValue)

        return HackerNewsStoryForSummary(
            id: id,
            title: title,
            author: author,
            score: score,
            publishedAtUTC: time,
            url: url,
            rawText: normalized
        )
    }

    private func value(for prefix: String, in story: String) -> String? {
        guard let line = story
            .components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) })
        else {
            return nil
        }

        let value = line
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespaces)

        return value.isEmpty ? nil : value
    }

    private func parseURL(_ rawURL: String?) -> String? {
        guard let rawURL, !rawURL.isEmpty else {
            return nil
        }
        if rawURL == "(no external URL)" {
            return nil
        }
        return rawURL
    }
}
