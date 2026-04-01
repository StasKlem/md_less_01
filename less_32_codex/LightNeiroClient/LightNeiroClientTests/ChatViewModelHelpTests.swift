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
        let reviewSpy = ChatProjectReviewUseCaseSpy(
            result: ProjectReviewTaskTurnResult(
                snapshot: ProjectReviewTaskSnapshot(
                    schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
                    sessionID: session.id,
                    branchID: session.activeBranchID,
                    state: .idle,
                    context: ProjectReviewTaskContext(
                        focus: "структура проекта",
                        changedFiles: ["README.md"],
                        diff: "diff --git a/README.md b/README.md",
                        evidence: [],
                        reviewText: "Ревью готово",
                        updatedAt: Date()
                    ),
                    updatedAt: Date()
                ),
                reviewText: "Ревью готово",
                systemMessages: []
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
            projectReviewUseCase: reviewSpy
        )

        await Task.yield()
        await Task.yield()

        viewModel.send(text: "/help структура проекта")

        for _ in 0..<20 {
            let reviewCount = await reviewSpy.callCount
            if reviewCount > 0,
               viewModel.dialogItems.last?.text == "Ревью готово"
            {
                break
            }
            await Task.yield()
        }

        let sendCount = await sendSpy.callCount
        let helpCount = await reviewSpy.callCount
        XCTAssertEqual(sendCount, 0)
        XCTAssertEqual(helpCount, 1)
        XCTAssertEqual(viewModel.chatMode, .default)
        XCTAssertEqual(viewModel.dialogItems.count, 2)
        XCTAssertEqual(viewModel.dialogItems.first?.kind, .system)
        XCTAssertTrue(viewModel.dialogItems.first?.text.contains("Состояния review task-агента") == true)
        XCTAssertEqual(viewModel.dialogItems.last?.kind, .assistant)
        XCTAssertEqual(viewModel.dialogItems.last?.text, "Ревью готово")
    }
}

private actor ChatSendMessageUseCaseSpy: SendMessageUseCaseProtocol {
    private(set) var callCount = 0

    func execute(userText: String, assistantInstruction: String?) async throws -> ChatMessage {
        callCount += 1
        return ChatMessage(role: .assistant, content: "unexpected: \(userText)")
    }
}

private actor ChatProjectReviewUseCaseSpy: StartProjectReviewTaskUseCaseProtocol {
    private(set) var callCount = 0
    let result: ProjectReviewTaskTurnResult

    init(result: ProjectReviewTaskTurnResult) {
        self.result = result
    }

    func execute(sessionID _: UUID, branchID _: UUID, focus _: String?) async -> ProjectReviewTaskTurnResult {
        callCount += 1
        return result
    }
}
