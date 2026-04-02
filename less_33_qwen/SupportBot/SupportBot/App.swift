//
//  App.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import TauTUI

// MARK: - Chat State

@MainActor
final class ChatState {
    var messages: [TUIMessage] = []
    var messageCount: Int { messages.count }
    var status: String = "Готов"
    var isTyping: Bool = false

    init() {
        messages.append(TUIMessage(
            text: "Добро пожаловать в SupportBot! Введите сообщение и нажмите Enter для отправки.",
            sender: .bot
        ))
    }

    func addMessage(_ text: String, sender: TUISender) {
        messages.append(TUIMessage(text: text, sender: sender))
    }

    func getHistoryText() -> String {
        var content = ""
        for message in messages {
            let timePrefix = "[\(message.formattedTime)]"
            let senderInfo = "\(message.sender.emoji) \(message.sender.displayName)"
            content += "\(timePrefix) \(senderInfo):\n  \(message.text)\n\n"
        }
        return content
    }

    func getInfoText(serviceStatus: ServiceStatus? = nil) -> String {
        let statusText = isTyping ? "⏳ Печатает..." : (serviceStatus?.isKnowledgeBaseIndexed == true ? "✅ Активен" : "⏳ Индексация...")
        let sessionText = serviceStatus?.sessionId.map { String($0.prefix(8)).uppercased() } ?? "N/A"
        let version = "v1.0.0"

        return """
        ╔══════════════════════════════════╗
        ║  📊 SupportBot Info              ║
        ╠══════════════════════════════════╣
        ║  💬 Сообщений: \(messageCount)
        ║  🟢 Статус: \(statusText)
        ║  🔑 Сессия: \(sessionText)
        ║  📦 Версия: \(version)
        ╠══════════════════════════════════╣
        ║  ⌨️  Команды:                    ║
        ║     /help - справка              ║
        ║     /clear - очистить историю    ║
        ║     /new - новая сессия          ║
        ║     /index - индексировать KB    ║
        ║     /status - статус             ║
        ║     Ctrl+C - выход               ║
        ╚══════════════════════════════════╝
        """
    }
}

// MARK: - Horizontal Layout Component

/// Горизонтальный лейаут для размещения компонентов рядом
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
        let maxLines = Swift.max(leftLines.count, rightLines.count)

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
    static var state = ChatState()
    static var chatHistory: Text!
    static var infoText: Text!
    static var inputField: Input!
    static var mainBox: Box!
    static var infoBox: Box!
    static var supportBotService: SupportBotService!
    static var isInitialized = false
    static var tui: TUI!

    static func main() {
        print("=== SupportBot запускается ===")

        let terminal = ProcessTerminal()
        let tuiInstance = TUI(terminal: terminal)
        self.tui = tuiInstance

        print("Создание UI компонентов...")

        // Создаём UI компоненты
        chatHistory = Text(text: state.getHistoryText(), paddingX: 2, paddingY: 1)
        inputField = Input(value: "")

        // Основной контейнер с историей и вводом
        mainBox = Box(paddingX: 0, paddingY: 0)
        mainBox.addChild(chatHistory)
        mainBox.addChild(inputField)

        // Информационная панель
        infoText = Text(text: state.getInfoText(), paddingX: 1, paddingY: 1)
        infoBox = Box(paddingX: 0, paddingY: 0)
        infoBox.addChild(infoText)

        // Горизонтальный лейаут (75% чат, 25% инфо)
        let horizontalLayout = HorizontalLayout(ratio: 0.75)
        horizontalLayout.addChild(mainBox)
        horizontalLayout.addChild(infoBox)

        // Заголовок приложения
        let title = Text(text: " ══ SupportBot v1.0.0 - AI Support Assistant with RAG ══ ", paddingX: 0, paddingY: 1)
        title.background = Text.Background(red: 62, green: 72, blue: 104)

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
            print("Получен сигнал Ctrl+C")
            tui.stop()
            exit(0)
        }

        // Обработчик отправки сообщения
        inputField.onSubmit = { value in
            print("Получено сообщение: \(value)")
            handleUserInput(value)
        }

        print("UI создан, запуск TUI...")

        // Инициализация сервиса в Task
        Task {
            print("Начало инициализации сервиса...")
            do {
                try await initializeService()
                print("✓ SupportBot готов к работе!")
            } catch {
                print("✗ Ошибка инициализации: \(error)")
                await MainActor.run {
                    state.addMessage("Ошибка инициализации: \(error.localizedDescription)", sender: .bot)
                    chatHistory.text = state.getHistoryText()
                    tui?.requestRender()
                }
            }
        }

        // Запускаем TUI
        do {
            print("Запуск TUI цикла...")
            try tui.start()
        } catch {
            print("Ошибка запуска TUI: \(error)")
            exit(1)
        }

        print("Запуск RunLoop...")
        RunLoop.current.run()
    }
    
    /// Инициализация сервиса
    static func initializeService() async throws {
        // Загружаем конфигурацию
        let config = try ConfigManager.shared.load()

        // Создаем сервис
        supportBotService = try SupportBotService(config: config)

        // Инициализируем
        try supportBotService.initialize()

        // Индексируем базу знаний
        print("Индексация базы знаний...")
        state.status = "Индексация..."
        try await supportBotService.indexKnowledgeBase()
        print("База знаний проиндексирована")

        isInitialized = true
    }
    
    /// Обработка ввода пользователя
    static func handleUserInput(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        let input = value.trimmingCharacters(in: .whitespaces)

        // Проверяем команды
        if input.hasPrefix("/") {
            handleCommand(input)
            inputField.setValue("")
            return
        }

        // === Обновление истории: ДОБАВЛЕНО СООБЩЕНИЕ ПОЛЬЗОВАТЕЛЯ ===
        state.addMessage(value, sender: .user)
        chatHistory.text = state.getHistoryText()
        infoText.text = state.getInfoText(serviceStatus: supportBotService?.getServiceStatus())
        inputField.setValue("")
        self.tui?.requestRender()
        // ============================================================

        // Устанавливаем статус "печатает"
        state.isTyping = true

        // Генерируем ответ бота
        Task {
            do {
                guard let service = supportBotService else {
                    throw ServiceError.notInitialized
                }

                let botResponse = try await service.processMessage(value)

                // === Обновление истории: ПОЛУЧЕН ОТВЕТ БОТА ===
                await MainActor.run {
                    state.addMessage(botResponse, sender: .bot)
                    chatHistory.text = state.getHistoryText()
                    state.isTyping = false
                    infoText.text = state.getInfoText(serviceStatus: service.getServiceStatus())
                    self.tui?.requestRender()
                }
                // ================================================
            } catch {
                // === Обновление истории: ПРОИЗОШЛА ОШИБКА ===
                await MainActor.run {
                    state.addMessage("Ошибка: \(error.localizedDescription)", sender: .bot)
                    state.isTyping = false
                    infoText.text = state.getInfoText(serviceStatus: supportBotService?.getServiceStatus())
                    chatHistory.text = state.getHistoryText()
                    self.tui?.requestRender()
                }
                // ==============================================
            }
        }
    }

    /// Обработка команд
    static func handleCommand(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = parts[0].lowercased()
        
        switch cmd {
        case "/help":
            let helpText = """
            Доступные команды:
            /help - показать эту справку
            /clear - очистить историю чата
            /new - начать новую сессию
            /index - переиндексировать базу знаний
            /status - показать статус сервиса
            
            Просто введите вопрос для получения ответа.
            """
            state.addMessage(helpText, sender: .bot)
            
        case "/clear":
            do {
                try supportBotService?.clearChat()
                state.messages.removeAll()
                state.addMessage("История чата очищена", sender: .bot)
                chatHistory.text = state.getHistoryText()
            } catch {
                state.addMessage("Ошибка очистки: \(error.localizedDescription)", sender: .bot)
            }
            
        case "/new":
            do {
                try supportBotService?.newSession()
                state.messages.removeAll()
                state.addMessage("Начата новая сессия", sender: .bot)
                chatHistory.text = state.getHistoryText()
            } catch {
                state.addMessage("Ошибка: \(error.localizedDescription)", sender: .bot)
            }
            
        case "/index":
            Task {
                do {
                    state.addMessage("Начинаю индексацию базы знаний...", sender: .bot)
                    chatHistory.text = state.getHistoryText()
                    try await supportBotService?.indexKnowledgeBase()
                    state.addMessage("Индексация завершена успешно", sender: .bot)
                    chatHistory.text = state.getHistoryText()
                } catch {
                    state.addMessage("Ошибка индексации: \(error.localizedDescription)", sender: .bot)
                    chatHistory.text = state.getHistoryText()
                }
            }
            
        case "/status":
            if let status = supportBotService?.getServiceStatus() {
                let statusText = """
                Статус сервиса:
                - Инициализирован: \(status.isInitialized ? "Да" : "Нет")
                - База знаний: \(status.isKnowledgeBaseIndexed ? "Проиндексирована" : "Не проиндексирована")
                - Сообщений: \(status.messageCount)
                - Сессия: \(status.sessionId ?? "N/A")
                """
                state.addMessage(statusText, sender: .bot)
                chatHistory.text = state.getHistoryText()
            }
            
        default:
            state.addMessage("Неизвестная команда: \(cmd). Введите /help для справки.", sender: .bot)
        }
        
        infoText.text = state.getInfoText(serviceStatus: supportBotService?.getServiceStatus())
    }
}
