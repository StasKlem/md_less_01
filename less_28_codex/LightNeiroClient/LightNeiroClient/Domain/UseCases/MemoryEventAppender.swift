import Foundation

protocol MemoryEventAppending {
    /// Добавляет системные сообщения для набора событий записи памяти.
    func appendEvents(events: [MemoryWriteEvent]) async throws

    /// Добавляет одно системное сообщение о событии записи памяти.
    func appendEvent(event: MemoryWriteEvent) async throws
}

enum MemoryEventAppenderFactory {
    /// Создает appender системных сообщений о записи памяти.
    static func make(messageRepository: MessageRepositoryProtocol) -> MemoryEventAppending {
        MemoryEventAppender(messageRepository: messageRepository)
    }
}

fileprivate final class MemoryEventAppender: MemoryEventAppending {
    private let messageRepository: MessageRepositoryProtocol

    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    func appendEvents(events: [MemoryWriteEvent]) async throws {
        for event in events {
            try await appendEvent(event: event)
        }
    }

    func appendEvent(event: MemoryWriteEvent) async throws {
        let systemMessage = ChatMessage(
            role: .system,
            content: "Память [\(event.layer.rawValue)] \(event.details)"
        )
        try await messageRepository.saveMessage(systemMessage)
    }
}
