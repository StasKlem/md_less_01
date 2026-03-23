import Foundation
import Testing
@testable import HackerNewsMCPServer

struct HackerNewsAPIRepositoryTests {
    @Test
    func randomStoryReturnsStoryFromTopList() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let topStoriesURL = try #require(URL(string: "https://example.com/v0/topstories.json"))
        let itemURL = try #require(URL(string: "https://example.com/v0/item/101.json"))

        let httpClient = MockHTTPClient(responses: [
            topStoriesURL: #"[101,102]"#,
            itemURL: #"{"id":101,"type":"story","title":"Ship Swift 6","by":"alice","url":"https://news.ycombinator.com","score":99,"time":1700000000}"#
        ])

        let repository = HackerNewsAPIRepository(
            baseURL: baseURL,
            httpClient: httpClient,
            randomGenerator: FixedRandomNumberGenerator(value: 0)
        )

        let story = try await repository.randomStory()

        #expect(story.id == 101)
        #expect(story.title == "Ship Swift 6")
        #expect(story.author == "alice")
        #expect(story.score == 99)
    }

    @Test
    func randomStoryThrowsWhenNoValidStoriesFound() async {
        let baseURL = URL(string: "https://example.com")!
        let topStoriesURL = URL(string: "https://example.com/v0/topstories.json")!
        let itemURL = URL(string: "https://example.com/v0/item/101.json")!

        let httpClient = MockHTTPClient(responses: [
            topStoriesURL: #"[101]"#,
            itemURL: #"{"id":101,"type":"job","title":"Hiring"}"#
        ])

        let repository = HackerNewsAPIRepository(
            baseURL: baseURL,
            httpClient: httpClient,
            randomGenerator: FixedRandomNumberGenerator(value: 0),
            maxAttempts: 1
        )

        await #expect(throws: HackerNewsToolError.noStoriesFound) {
            _ = try await repository.randomStory()
        }
    }
}

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let responses: [URL: String]

    init(responses: [URL: String]) {
        self.responses = responses
    }

    func get(url: URL) async throws -> Data {
        guard let body = responses[url] else {
            throw HackerNewsToolError.upstreamFailure("Missing mock response for \(url.absoluteString)")
        }
        return Data(body.utf8)
    }
}

private struct FixedRandomNumberGenerator: RandomNumberGenerating {
    let value: Int

    func int(in range: Range<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound - 1)
    }
}
