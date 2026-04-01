import XCTest
@testable import LightNeiroClient

final class ChatSidebarCommandCatalogTests: XCTestCase {
    func testGeneralCommandsContainsHelpButton() {
        XCTAssertEqual(ChatSidebarCommandCatalog.generalCommands.map(\.title), ["/help"])
        XCTAssertEqual(ChatSidebarCommandCatalog.generalCommands.map(\.command), ["/help"])
    }
}
