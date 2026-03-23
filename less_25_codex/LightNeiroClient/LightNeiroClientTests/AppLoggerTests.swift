import XCTest
@testable import LightNeiroClient

final class AppLoggerTests: XCTestCase {
    private struct SamplePayload: CustomStringConvertible {
        let id: Int
        let title: String

        var description: String {
            "SamplePayload(id: \(id), title: \(title))"
        }
    }

    func testTimestampContainsMilliseconds() {
        let logger = AppLogger.shared
        let date = Date(timeIntervalSince1970: 1_710_000_123.456)

        let timestamp = logger.timestampString(from: date)

        XCTAssertEqual(timestamp.count, 23)
        XCTAssertEqual(timestamp.filter { $0 == "." }.count, 1)
        XCTAssertEqual(String(timestamp.suffix(4).prefix(1)), ".")
    }

    func testSharedReturnsSameInstance() {
        XCTAssertTrue(AppLogger.shared === AppLogger.shared)
    }

    func testLogLineContainsTimestampLevelCategoryAndMessage() {
        let logger = AppLogger.shared
        let date = Date(timeIntervalSince1970: 1_710_000_123.456)

        let line = logger.makeLogLine(level: .warning, category: "network", message: "Проверка", date: date)

        XCTAssertTrue(line.hasPrefix("["))
        XCTAssertTrue(line.contains("] [WARNING] [network] Проверка"))
        let timestampPart = line.split(separator: "]").first?.dropFirst() ?? ""
        XCTAssertEqual(timestampPart.count, 23)
    }

    func testStringifyObjectReturnsDescription() {
        let payload = SamplePayload(id: 7, title: "logger")

        let text = stringify(payload)

        XCTAssertEqual(text, "SamplePayload(id: 7, title: logger)")
    }
}
