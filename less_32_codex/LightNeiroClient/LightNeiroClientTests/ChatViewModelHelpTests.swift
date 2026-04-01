import XCTest
@testable import LightNeiroClient

@MainActor
final class ChatViewModelHelpTests: XCTestCase {
    func testSendRoutesHelpCommandWithoutInvokingSendMessageUseCase() async throws {
        await InMemoryChatStore.shared.reset()

        let session = ChatSession(
            id: UUID(),
            title: "Test",
            activeBranchID: UUID(),
            createdAt: Date()
        )
        let sendSpy = ChatSendMessageUseCaseSpy()
        let helpSpy = ChatProjectHelpUseCaseSpy(
            result: ProjectHelpExecutionResult(
                response: "Справка по проекту",
                systemMessage: "Не удалось получить текущую git-ветку через MCP: request failed"
            )
        )

        let viewModel = ChatViewModel(
            session: session,
            sendMessageUseCase: sendSpy,
            fetchMessagesUseCase: FetchMessagesUseCase(messageRepository: MockMessageRepository()),
            clearDialogUseCase: ClearDialogUseCase(
                messageRepository: MockMessageRepository(),
                shortTermRepository: MockShortTermMemoryRepository(),
                workingMemoryRepository: MockWorkingMemoryRepository(),
                longTermMemoryRepository: MockLongTermMemoryRepository(),
                metricsRepository: MockMetricsRepository()
            ),
            projectHelpUseCase: helpSpy
        )

        await Task.yield()
        await Task.yield()

        viewModel.send(text: "/help структура проекта")

        for _ in 0..<20 {
            let helpCount = await helpSpy.callCount
            if helpCount > 0,
               viewModel.dialogItems.last?.text == "Справка по проекту"
            {
                break
            }
            await Task.yield()
        }

        let sendCount = await sendSpy.callCount
        let helpCount = await helpSpy.callCount
        XCTAssertEqual(sendCount, 0)
        XCTAssertEqual(helpCount, 1)
        XCTAssertEqual(viewModel.chatMode, .default)
        XCTAssertEqual(viewModel.dialogItems.count, 2)
        XCTAssertEqual(viewModel.dialogItems.first?.kind, .system)
        XCTAssertTrue(viewModel.dialogItems.first?.text.contains("Не удалось получить текущую git-ветку через MCP") == true)
        XCTAssertEqual(viewModel.dialogItems.last?.kind, .assistant)
        XCTAssertEqual(viewModel.dialogItems.last?.text, "Справка по проекту")
    }
}

private actor ChatSendMessageUseCaseSpy: SendMessageUseCaseProtocol {
    private(set) var callCount = 0

    func execute(userText: String, assistantInstruction: String?) async throws -> ChatMessage {
        callCount += 1
        return ChatMessage(role: .assistant, content: "unexpected: \(userText)")
    }
}

private actor ChatProjectHelpUseCaseSpy: ProjectHelpUseCaseProtocol {
    private(set) var callCount = 0
    let result: ProjectHelpExecutionResult

    init(result: ProjectHelpExecutionResult) {
        self.result = result
    }

    func execute(question _: String?) async -> ProjectHelpExecutionResult {
        callCount += 1
        return result
    }
}
