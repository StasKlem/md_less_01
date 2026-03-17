import XCTest
import PDFKit
import AppKit
@testable import LightNeiroClient

@MainActor
final class RAGPipelineTests: XCTestCase {
    func testFixedSizeChunkerSplitsWithOverlap() throws {
        let document = ParsedDocument(
            source: "/tmp/doc.md",
            title: "doc",
            kind: .markdown,
            fullText: "abcdefghijklmnopqrstuvwxyz",
            sections: []
        )
        let chunker = FixedSizeChunker(chunkSize: 10, overlap: 2)

        let chunks = try chunker.makeChunks(document: document)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].content, "abcdefghij")
        XCTAssertEqual(chunks[1].offset, 8)
        XCTAssertEqual(chunks[2].offset, 16)
    }

    func testStructuralChunkerKeepsSectionMetadataAndFallbacks() throws {
        let longSectionText = String(repeating: "a", count: 40)
        let document = ParsedDocument(
            source: "/tmp/readme.md",
            title: "readme",
            kind: .markdown,
            fullText: "ignored",
            sections: [
                ParsedSection(title: "Intro", content: "short text", offset: 0),
                ParsedSection(title: "Details", content: longSectionText, offset: 20)
            ]
        )
        let chunker = StructuralChunker(maxSectionSize: 12, fallbackChunkSize: 10, fallbackOverlap: 2)

        let chunks = try chunker.makeChunks(document: document)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertEqual(chunks.first?.section, "Intro")
        XCTAssertTrue(chunks.dropFirst().allSatisfy { $0.section == "Details" })
        XCTAssertTrue(chunks.contains(where: { $0.offset > 20 }))
    }

    func testMarkdownParserBuildsSections() throws {
        let url = try makeTempFile(name: "doc.md", content: "# Header\nLine 1\n## Next\nLine 2")
        let parser = MarkdownDocumentParser()

        let document = try parser.parse(url: url)

        XCTAssertEqual(document.kind, .markdown)
        XCTAssertEqual(document.sections.count, 2)
        XCTAssertEqual(document.sections[0].title, "Header")
        XCTAssertEqual(document.sections[1].title, "Next")
    }

    func testCodeParserFindsSwiftSymbols() throws {
        let code = """
        import Foundation
        struct A {}
        func run() {
            print("x")
        }
        """
        let url = try makeTempFile(name: "code.swift", content: code)
        let parser = CodeDocumentParser()

        let document = try parser.parse(url: url)

        XCTAssertEqual(document.kind, .code)
        XCTAssertTrue(document.sections.contains(where: { ($0.title ?? "").hasPrefix("struct A") }))
        XCTAssertTrue(document.sections.contains(where: { ($0.title ?? "").hasPrefix("func run") }))
    }

    func testPDFParserParsesExistingPDF() throws {
        let url = try makeTempPDF(name: "sample.pdf")
        let parser = PDFDocumentParserAdapter()

        let document = try parser.parse(url: url)

        XCTAssertEqual(document.kind, .pdf)
        XCTAssertEqual(document.source, url.path)
        XCTAssertTrue((document.title ?? "").hasSuffix("sample"))
    }

    func testIndexAndSearchReturnRelevantChunk() async throws {
        let url = try makeTempFile(
            name: "guide.md",
            content: "# Intro\nSwift RAG index on macOS.\n## Details\nSQLite sqlite-vss integration."
        )
        let parser = CompositeDocumentParser()
        let chunkers: [ChunkingStrategyType: ChunkingStrategy] = [
            .fixed: FixedSizeChunker(chunkSize: 80, overlap: 10),
            .structural: StructuralChunker(maxSectionSize: 80, fallbackChunkSize: 60, fallbackOverlap: 10)
        ]
        let provider = DeterministicHashEmbeddingProvider(dimension: 64)
        let store = InMemoryVectorStore()
        let settings = RAGSettings(
            provider: .localONNX,
            embeddingModel: "test",
            embeddingDimension: 64,
            batchSize: 8,
            normalizeEmbeddings: true
        )

        let indexUseCase = IndexDocumentsUseCase(
            parser: parser,
            chunkingStrategies: chunkers,
            embeddingProvider: provider,
            vectorStore: store,
            settings: settings
        )
        let searchUseCase = SearchChunksUseCase(
            embeddingProvider: provider,
            vectorStore: store,
            settings: settings
        )

        let summary = try await indexUseCase.execute(documents: [url], strategy: .structural)
        let results = try await searchUseCase.execute(query: "sqlite integration", topK: 3)

        XCTAssertEqual(summary.documentCount, 1)
        XCTAssertGreaterThan(summary.chunkCount, 0)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.chunk.content.lowercased().contains("sqlite") }))
    }

    func testCompareChunkingStrategiesBuildsMetrics() async throws {
        let first = try makeTempFile(name: "a.md", content: "# Intro\nRAG with chunks.\n## Q\nFind answer.")
        let second = try makeTempFile(name: "b.swift", content: "struct A {}\nfunc run() {}\n")

        let useCase = CompareChunkingStrategiesUseCase(
            parser: CompositeDocumentParser(),
            chunkingStrategies: [
                .fixed: FixedSizeChunker(chunkSize: 20, overlap: 5),
                .structural: StructuralChunker(maxSectionSize: 20, fallbackChunkSize: 12, fallbackOverlap: 3)
            ],
            embeddingProvider: DeterministicHashEmbeddingProvider(dimension: 48),
            vectorStoreFactory: { InMemoryVectorStore() },
            settings: RAGSettings(
                provider: .localONNX,
                embeddingModel: "test",
                embeddingDimension: 48,
                batchSize: 8,
                normalizeEmbeddings: true
            )
        )

        let report = try await useCase.execute(
            strategies: [.fixed, .structural],
            dataset: [first, second],
            evaluationCases: [
                ChunkingEvaluationCase(
                    query: "where is struct",
                    expectedSourceContains: "b.swift",
                    expectedSectionContains: "struct"
                )
            ],
            topK: 3
        )

        XCTAssertEqual(report.metrics.count, 2)
        XCTAssertTrue(ChunkingStrategyType.allCases.contains(report.recommendedDefault))
    }

    func testSQLiteStoreWorksWithFallbackSearch() async throws {
        let dbURL = temporaryDirectoryURL().appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = SQLiteVSSVectorStore(databaseURL: dbURL)
        let chunk = DocumentChunk(
            id: UUID(),
            content: "Swift sqlite vector",
            embedding: [1, 0, 0, 0],
            source: "/tmp/doc.md",
            title: "doc",
            section: "intro",
            offset: 0
        )

        try await store.reset()
        try await store.upsert(chunks: [chunk])
        let results = try await store.search(queryEmbedding: [1, 0, 0, 0], topK: 1)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.chunk.source, "/tmp/doc.md")
    }

    func testFAISSStoreReturnsExplicitNotImplementedError() async {
        let store = FAISSVectorStore(mode: .pythonKit)

        do {
            _ = try await store.search(queryEmbedding: [0.1, 0.2], topK: 3)
            XCTFail("Expected FAISS adapter error")
        } catch {
            guard let localized = error as? LocalizedError else {
                XCTFail("Expected localized error")
                return
            }
            XCTAssertTrue((localized.errorDescription ?? "").contains("FAISS"))
        }
    }

    func testAppLLMEmbeddingProviderSendsEncodingFormatFloat() async throws {
        let httpClient = CapturingHTTPClient(
            responseData: """
            {
              "data": [
                { "index": 0, "embedding": [1.0, 2.0, 3.0] }
              ]
            }
            """.data(using: .utf8)!
        )
        let provider = AppLLMEmbeddingProvider(
            httpClient: httpClient,
            configuration: RouterAIConfiguration(
                endpoint: URL(string: "https://routerai.ru/api/v1/chat/completions")!,
                timeoutInterval: 30,
                apiKeyProvider: { "test-key" }
            )
        )

        _ = try await provider.embed(
            texts: ["hello"],
            settings: RAGSettings(
                provider: .appLLM,
                embeddingModel: "text-embedding-3-small",
                embeddingDimension: 3,
                batchSize: 8,
                normalizeEmbeddings: false
            )
        )

        let request = try XCTUnwrap(httpClient.lastRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["encoding_format"] as? String, "float")
    }

    private func makeTempFile(name: String, content: String) throws -> URL {
        let url = temporaryDirectoryURL().appendingPathComponent(UUID().uuidString + "-" + name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempPDF(name: String) throws -> URL {
        let image = NSImage(size: NSSize(width: 300, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 200)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "Sample PDF content").draw(
            in: NSRect(x: 20, y: 80, width: 260, height: 40),
            withAttributes: attributes
        )
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "RAGPipelineTests", code: 1)
        }

        let document = PDFDocument()
        document.insert(page, at: 0)

        let url = temporaryDirectoryURL().appendingPathComponent(UUID().uuidString + "-" + name)
        guard document.write(to: url) else {
            throw NSError(domain: "RAGPipelineTests", code: 2)
        }
        return url
    }

    private func temporaryDirectoryURL() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LightNeiroClientTests-RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

private final class CapturingHTTPClient: HTTPClientProtocol {
    private(set) var lastRequest: URLRequest?
    private let responseData: Data
    private let statusCode: Int

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
