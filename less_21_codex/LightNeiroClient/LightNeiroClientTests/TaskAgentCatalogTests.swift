import XCTest
@testable import LightNeiroClient

final class TaskAgentCatalogTests: XCTestCase {
    func testCatalogContainsExpectedTaskAgents() {
        let catalog = TaskAgentCatalog.all

        XCTAssertEqual(catalog.map(\.id), [.mock, .counter, .hackerNews])
        XCTAssertEqual(catalog.map(\.name), ["Mock Task Agent", "Counter Task Agent", "Hacker News Task Agent"])
        XCTAssertEqual(catalog.map(\.startCommand), ["/task start", "/counter start", "/hn start"])
    }

    func testEveryTaskAgentHasControlButtonsFromCommonProtocol() {
        let catalog = TaskAgentCatalog.all

        XCTAssertEqual(catalog.first(where: { $0.id == .mock })?.controls.map(\.title), ["Стоп"])
        XCTAssertEqual(
            catalog.first(where: { $0.id == .counter })?.controls.map(\.title),
            ["Стоп", "Интервал 1с", "Интервал 5с"]
        )
        XCTAssertEqual(
            catalog.first(where: { $0.id == .hackerNews })?.controls.map(\.title),
            ["Стоп"]
        )
    }
}
