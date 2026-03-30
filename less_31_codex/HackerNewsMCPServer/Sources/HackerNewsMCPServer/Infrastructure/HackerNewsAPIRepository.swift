import Foundation

struct HackerNewsAPIRepository: HackerNewsRepository {
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let randomGenerator: RandomNumberGenerating
    private let logger: Logger?
    private let decoder: JSONDecoder
    private let maxAttempts: Int

    init(
        baseURL: URL,
        httpClient: HTTPClient,
        randomGenerator: RandomNumberGenerating,
        logger: Logger? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        maxAttempts: Int = 5
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.randomGenerator = randomGenerator
        self.logger = logger
        self.decoder = decoder
        self.maxAttempts = maxAttempts
    }

    func randomStory() async throws -> HackerNewsStory {
        let topStoriesURL = try makeURL(path: "/v0/topstories.json")

        let topStoriesData = try await httpClient.get(url: topStoriesURL)
        let topStoryIDs: [Int]
        do {
            topStoryIDs = try decoder.decode([Int].self, from: topStoriesData)
        } catch {
            throw HackerNewsToolError.decodingFailure(error.localizedDescription)
        }
        logger?.debug("Loaded top stories count: \(topStoryIDs.count)")

        guard !topStoryIDs.isEmpty else {
            throw HackerNewsToolError.noStoriesFound
        }

        let attemptCount = min(maxAttempts, topStoryIDs.count)
        logger?.debug("Searching random story, max attempts: \(attemptCount)")
        for _ in 0..<attemptCount {
            let randomIndex = randomGenerator.int(in: 0..<topStoryIDs.count)
            let storyID = topStoryIDs[randomIndex]
            logger?.debug("Trying story id: \(storyID)")

            if let story = try await fetchStory(id: storyID) {
                logger?.info("Selected random story id: \(story.id)")
                return story
            }
        }

        logger?.warn("Failed to find valid story after \(attemptCount) attempts")
        throw HackerNewsToolError.noStoriesFound
    }

    private func fetchStory(id: Int) async throws -> HackerNewsStory? {
        let itemURL = try makeURL(path: "/v0/item/\(id).json")
        let itemData = try await httpClient.get(url: itemURL)

        let dto: HackerNewsItemDTO
        do {
            dto = try decoder.decode(HackerNewsItemDTO.self, from: itemData)
        } catch {
            throw HackerNewsToolError.decodingFailure(error.localizedDescription)
        }

        guard dto.type == "story", let title = dto.title, !title.isEmpty else {
            logger?.debug("Item \(id) skipped: type=\(dto.type ?? "nil"), hasTitle=\(dto.title?.isEmpty == false)")
            return nil
        }

        return HackerNewsStory(
            id: dto.id,
            title: title,
            author: dto.by,
            url: dto.url.flatMap(URL.init(string:)),
            score: dto.score,
            timestamp: dto.time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func makeURL(path: String) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else {
            throw HackerNewsToolError.upstreamFailure("Could not build request URL.")
        }
        return url
    }
}

private struct HackerNewsItemDTO: Decodable {
    let id: Int
    let type: String?
    let title: String?
    let by: String?
    let url: String?
    let score: Int?
    let time: Int?
}
