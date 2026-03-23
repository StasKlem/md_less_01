import XCTest
@testable import LightNeiroClient

final class MemoryEventAppenderTests: XCTestCase {
    func testAppendEventsWritesSystemMessagesInOrder() async throws {
        let repository = MessageRepositorySpy()
        let appender = MemoryEventAppenderFactory.make(messageRepository: repository)
        let events = [
            MemoryWriteEvent(layer: .shortTerm, details: "сохранено: user: привет"),
            MemoryWriteEvent(layer: .working, details: "сохранено: task.goal=написать тест")
        ]

        try await appender.appendEvents(events: events)

        let messages = await repository.savedMessages
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .system)
        XCTAssertEqual(messages[0].content, "Память [краткосрочная] сохранено: user: привет")
        XCTAssertEqual(messages[1].content, "Память [рабочая] сохранено: task.goal=написать тест")
    }

    func testAppendEventWritesSingleSystemMessage() async throws {
        let repository = MessageRepositorySpy()
        let appender = MemoryEventAppenderFactory.make(messageRepository: repository)

        try await appender.appendEvent(
            event: MemoryWriteEvent(layer: .longTerm, details: "сохранено: knowledge.summary=факт")
        )

        let messages = await repository.savedMessages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content, "Память [долговременная] сохранено: knowledge.summary=факт")
    }
}

private actor MessageRepositorySpy: MessageRepositoryProtocol {
    private(set) var savedMessages: [ChatMessage] = []

    func fetchMessages() async throws -> [ChatMessage] {
        savedMessages
    }

    func saveMessage(_ message: ChatMessage) async throws {
        savedMessages.append(message)
    }
}
