//
//  App.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import TauTUI

// MARK: - Models

/// Сообщение чата
struct Message {
    let id: UUID
    let text: String
    let sender: Sender
    let timestamp: Date

    init(text: String, sender: Sender) {
        self.id = UUID()
        self.text = text
        self.sender = sender
        self.timestamp = Date()
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

/// Отправитель сообщения
enum Sender {
    case user
    case bot

    var displayName: String {
        switch self {
        case .user: return "Вы"
        case .bot: return "SupportBot"
        }
    }

    var emoji: String {
        switch self {
        case .user: return "🔵"
        case .bot: return "🟢"
        }
    }
}

// MARK: - Chat State

@MainActor
final class ChatState {
    var messages: [Message] = []
    var messageCount: Int { messages.count }

    init() {
        messages.append(Message(
            text: "Добро пожаловать в SupportBot! Введите сообщение и нажмите Enter для отправки.",
            sender: .bot
        ))
    }

    func addMessage(_ text: String, sender: Sender) {
        messages.append(Message(text: text, sender: sender))
    }

    func getHistoryText() -> String {
        var content = ""
        for message in messages {
            content += "[\(message.formattedTime)] \(message.sender.emoji) [\(message.sender.displayName)]: \(message.text)\n\n"
        }
        return content
    }

    func getInfoText() -> String {
        return """
        ╔═══════════════════════════╗
        ║     SupportBot Info       ║
        ╠═══════════════════════════╣
        ║ Сообщений: \(String(format: "%-17d", messageCount))║
        ║ Статус: \(String(format: "%-20s", "Активен"))║
        ║ Версия: 1.0.0\(String(format: "%-16s", ""))║
        ╠═══════════════════════════╣
        ║ Клавиши:                  ║
        ║ Enter - отправить         ║
        ║ Ctrl+C - выход            ║
        ╚═══════════════════════════╝
        """
    }
}

// MARK: - Horizontal Layout Component

/// Простой горизонтальный лейаут для размещения компонентов рядом
@MainActor
final class HorizontalLayout: @MainActor Component {
    var children: [Component] = []
    private let ratio: CGFloat

    init(ratio: CGFloat = 0.75) {
        self.ratio = ratio
    }

    func addChild(_ child: Component) {
        children.append(child)
    }

    func render(width: Int) -> [String] {
        guard children.count == 2 else {
            return children.flatMap { $0.render(width: width) }
        }

        let leftWidth = Int(CGFloat(width) * ratio)
        let rightWidth = width - leftWidth

        let leftLines = children[0].render(width: leftWidth)
        let rightLines = children[1].render(width: rightWidth)

        var result: [String] = []
        let maxLines = max(leftLines.count, rightLines.count)

        for i in 0..<maxLines {
            let leftLine = i < leftLines.count ? leftLines[i] : String(repeating: " ", count: leftWidth)
            let rightLine = i < rightLines.count ? rightLines[i] : ""
            result.append(leftLine + rightLine)
        }

        return result
    }

    func handle(input: TerminalInput) {
        for child in children {
            child.handle(input: input)
        }
    }
}

// MARK: - Main Application

@MainActor
@main
struct SupportBotApp {
    static let state = ChatState()
    static var chatHistory: Text!
    static var infoText: Text!
    static var inputField: Input!
    static var mainBox: Box!
    static var infoBox: Box!

    static func main() throws {
        let terminal = ProcessTerminal()
        let tui = TUI(terminal: terminal)

        // Создаём историю чата
        chatHistory = Text(text: state.getHistoryText(), paddingX: 1, paddingY: 1)

        // Создаём поле ввода
        inputField = Input(value: "")

        // Создаём информационную панель
        infoText = Text(text: state.getInfoText(), paddingX: 1, paddingY: 1)

        // Основной контейнер с историей и вводом
        mainBox = Box(paddingX: 1, paddingY: 1)
        mainBox.addChild(chatHistory)
        mainBox.addChild(inputField)

        // Информационная панель
        infoBox = Box(paddingX: 1, paddingY: 1)
        infoBox.addChild(infoText)

        // Горизонтальный лейаут через кастомный компонент
        let horizontalLayout = HorizontalLayout()
        horizontalLayout.addChild(mainBox)
        horizontalLayout.addChild(infoBox)

        // Заголовок приложения
        let title = Text(text: " SupportBot v1.0.0 - TUI Chat Application ", paddingX: 1, paddingY: 0)

        // Верхний контейнер с заголовком
        let rootBox = Box(paddingX: 0, paddingY: 0)
        rootBox.addChild(title)
        rootBox.addChild(horizontalLayout)

        // Добавляем в TUI
        tui.addChild(rootBox)

        // Устанавливаем фокус на поле ввода
        tui.setFocus(inputField)

        // Обработчик Ctrl+C
        tui.onControlC = {
            tui.stop()
            exit(0)
        }

        // Обработчик отправки сообщения
        inputField.onSubmit = { value in
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                // Добавляем сообщение пользователя
                state.addMessage(value, sender: .user)
                chatHistory.text = state.getHistoryText()
                infoText.text = state.getInfoText()

                // Очищаем поле ввода
                inputField.setValue("")

                // Запрашиваем перерисовку
                tui.requestRender()

                // Генерируем ответ бота
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let botResponse = generateResponse(to: value)
                    state.addMessage(botResponse, sender: .bot)
                    chatHistory.text = state.getHistoryText()
                    infoText.text = state.getInfoText()
                    tui.requestRender()
                }
            }
        }

        // Запускаем TUI
        try tui.start()
        RunLoop.main.run()
    }

    /// Генерация ответа бота
    static func generateResponse(to message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("привет") || lowercased.contains("здравствуй") {
            return "Здравствуйте! Чем я могу вам помочь сегодня?"
        } else if lowercased.contains("как дела") || lowercased.contains("как жизнь") {
            return "У меня всё отлично! Я виртуальный помощник, всегда готов помочь вам!"
        } else if lowercased.contains("что ты умеешь") || lowercased.contains("возможности") {
            return "Я умею отвечать на вопросы, поддерживать беседу и помогать с базовыми запросами. Спрашивайте!"
        } else if lowercased.contains("спасибо") {
            return "Пожалуйста! Всегда рад помочь!"
        } else if lowercased.contains("пока") || lowercased.contains("до свидания") {
            return "До свидания! Обращайтесь ещё!"
        } else if lowercased.contains("кто ты") || lowercased.contains("что ты") {
            return "Я SupportBot - виртуальный помощник, созданный для демонстрации TUI на Swift с использованием TauTUI."
        } else if lowercased.contains("помощь") || lowercased.contains("help") {
            return "Просто напишите сообщение и нажмите Enter. Я постараюсь ответить!"
        } else if lowercased.contains("время") || lowercased.contains("дата") {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            return "Сейчас: \(formatter.string(from: Date()))"
        } else {
            let responses = [
                "Интересный вопрос! Расскажите подробнее.",
                "Понял вас. Есть ещё вопросы?",
                "Хорошо, я вас услышал. Чем ещё могу помочь?",
                "Спасибо за сообщение! Я продолжаю учиться.",
                "Принято! Жду ваших следующих вопросов."
            ]
            return responses.randomElement() ?? "Я вас понял!"
        }
    }
}
