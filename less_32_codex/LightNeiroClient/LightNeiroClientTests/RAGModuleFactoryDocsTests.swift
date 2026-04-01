import XCTest
@testable import LightNeiroClient

final class RAGModuleFactoryDocsTests: XCTestCase {
    func testDefaultDocumentURLsIncludeReadmeAndMarkdownDocs() throws {
        let baseDirectory = temporaryDirectoryURL().appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docDirectory = baseDirectory.appendingPathComponent("LightNeiroClient/Doc", isDirectory: true)
        let docsDirectory = baseDirectory.appendingPathComponent("docs", isDirectory: true)

        try FileManager.default.createDirectory(at: docDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)

        let readmeURL = baseDirectory.appendingPathComponent("README.md")
        let docOneURL = docDirectory.appendingPathComponent("guide.md")
        let docTwoURL = docsDirectory.appendingPathComponent("overview.markdown")
        let ignoredURL = docDirectory.appendingPathComponent("notes.txt")

        try "README".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "DOC 1".write(to: docOneURL, atomically: true, encoding: .utf8)
        try "DOC 2".write(to: docTwoURL, atomically: true, encoding: .utf8)
        try "IGNORE".write(to: ignoredURL, atomically: true, encoding: .utf8)

        let urls = RAGModuleFactory.defaultDocumentURLs(baseDirectory: baseDirectory)
        let paths = Set(urls.map(\.standardizedFileURL.path))

        XCTAssertTrue(paths.contains(readmeURL.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(docOneURL.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(docTwoURL.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(ignoredURL.standardizedFileURL.path))
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
    }
}
