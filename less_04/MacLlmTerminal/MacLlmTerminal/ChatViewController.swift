import Cocoa

// MARK: - Chat View Controller

final class ChatViewController: NSViewController {
    
    private enum Constants {
        static let llmUrl = "https://routerai.ru/api/v1/chat/completions"
        static let longText = """
                               Отличный вопрос! Погода в Калининграде в апреле — это классическая \"весна с характером\", переходный месяц, когда зима окончательно сдаёт позиции, но капризы ещё возможны. Вот подробная характеристика:\n\n### 🌡️ Температура:\n- **Средняя дневная температура**: +8°C до +12°C, но возможны колебания от **0°C до +18°C**.\n- **Ночью**: +2°C до +5°C, иногда бывают слабые заморозки (особенно в начале месяца).\n- **К концу апреля** обычно становится ощутимо теплее, особенно в солнечные дни.\n\n### 🌧️ Осадки и облачность:\n- **Дожди** часты, но обычно непродолжительные (морось или кратковременные ливни). Апрель — один из самых **сухих** месяцев в году по сравнению с летом, но влажность высокая.\n- **Солнечных дней** становится больше, чем в марте, но переменная облачность — норма.\n- **Возможен мокрый снег или снежная крупа** в первой половине месяца, особенно ночью.\n\n### 💨 Ветер:\n- Ветер часто **умеренный или сильный** (Калининград находится у Балтийского моря, поэтому ветра — обычное явление).\n- Может ощущаться прохлада даже при плюсовой температуре из-за влажности и ветра (\"сырая погода\").\n\n### 🌸 Природа и световой день:\n- **Середина-конец апреля** — начало **цветения** (первоцветы, магнолии, позже — сакура в Ботаническом саду).\n- **Световой день** быстро увеличивается: к концу месяца солнце светит **около 14 часов**.\n- Море ещё **очень холодное** (+4°C...+6°C), купаться рано.\n\n### 📊 Статистика (средние показатели):\n- **Средняя температура месяца**: около +6°C.\n- **Количество солнечных дней**: 7–10 за месяц.\n- **Осадков**: 40–50 мм (меньше, чем летом).\n\n### ✅ Что важно знать туристам и жителям:\n1. **Одежда** — лучше **слоёная**: ветровка/дождевик, свитер, зонт. Обувь — непромокаемая.\n2. **Апрель непредсказуем** — утром может быть солнце, а после обеда — дождь с ветром.\n3. **Идеально для прогулок** без летней толкучки: парки (например, Центральный парк) начинают зеленеть, но комаров ещё нет.\n4. **Исторически** в апреле бывали как **аномально тёплые** дни (до +20°C), так и **поздние снегопады** (например, в 2017 году).\n\n### 🗺️ Контекст:\nКлимат Калининграда — **умеренный морской**, с мягкой зимой и прохладным летом. Апрель — это как \"облегчённая версия\" мая: уже не зима, но ещё не стабильное тепло. Если повезёт с антициклоном, погода может быть **удивительно солнечной и тёплой**.\n\n**Кратко:** Апрель в Калининграде — **прохладный, ветреный, с частой сменой солнца и дождей**. Весна здесь проявляется скорее в удлинении дня и цветах, чем в жаре. Лучше быть готовым ко всему! 😊\n\nНужны ли уточнения или интересны сравнения с другими городами?
            """
    }
    
    private var isDebugEnabled: Bool = false
    
    // MARK: - Properties
    
    private var messages: [Message] = []
    private var chatState: ChatState = .idle {
        didSet {
            updateStateUI()
        }
    }
    
    // MARK: - UI Elements
    
    private lazy var scrollView: NSScrollView = {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true       // Включаем вертикальный скролл
        scrollView.hasHorizontalScroller = false    // Выключаем горизонтальный (текст переносится)
        scrollView.autohidesScrollers = false       // Скролл виден всегда (можно поставить true)
        scrollView.borderType = .bezelBorder        // Рамка вокруг поля ввода
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Важно: разрешаем scrollView растягиваться по ширине
        scrollView.autoresizingMask = [.width, .height]
        return scrollView
    }()
    
    private lazy var chatTextView: NSTextView = {
        let textView = NSTextView()
        
        // --- КРИТИЧЕСКИ ВАЖНЫЕ НАСТРОЙКИ ДЛЯ СКРОЛЛА И ПЕРЕНОСА ---
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true               // Простой текст (легче настраивать перенос)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Настройки контейнера текста
        textView.textContainer?.widthTracksTextView = true   // Ширина зависит от ScrollView
        textView.textContainer?.heightTracksTextView = false // ❗ Высота НЕ зависит (иначе скролл не сработает)
        textView.textContainer?.lineBreakMode = .byWordWrapping // Перенос по словам
        
        // Разрешаем TextView расти по вертикали внутри скролла
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width] // Растягиваем по ширине скролла
        
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        
        return textView
    }()
    
    private lazy var inputView: MessageInputView = {
        let view = MessageInputView()
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = NSColor.systemRed
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        if isDebugEnabled {
            setupDebug()
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        scrollView.documentView = chatTextView
        
        view.addSubview(scrollView)
        view.addSubview(inputView)
        view.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            // Chat area
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputView.topAnchor),
            
            // Input area
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: inputView.bottomAnchor, constant: 5),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
        ])
    }
    
    // MARK: - Actions

    private func sendMessage(_ text: String) {
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)

        appendMessageToChat(userMessage)
        scrollToBottom()

        chatState = .loading
        inputView.isSending = true

        // Get settings and API key from parent
        let settings = (parent as? SplitViewController)?.settingsViewController?.getSettings() ?? ChatSettings.default
        let apiKey = (parent as? SplitViewController)?.settingsViewController?.getApiKey() ?? ""

        // Configure NetworkManager
        NetworkManager.shared.configure(apiURL: Constants.llmUrl, apiKey: apiKey)

        // Prepare messages with system prompt
        var apiMessages: [Message] = []
        if !settings.systemPrompt.isEmpty {
            apiMessages.append(Message(role: .system, content: settings.systemPrompt))
        }
        apiMessages.append(contentsOf: messages)

        NetworkManager.shared.sendMessage(
            messages: apiMessages,
            settings: settings,
            onToken: { [weak self] token in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print(token)
                    self?.appendTokenToLastAssistantMessage(token)
                }
            },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let content):
                        if self?.messages.last?.role != "assistant" {
                            let message = Message(role: .assistant, content: content)
                            self?.messages.append(message)
                            self?.appendMessageToChat(message)
                        }
                        self?.chatState = .idle
                        self?.inputView.isSending = false

                    case .failure(let error):
                        self?.chatState = .error(error.localizedDescription)
                        self?.inputView.isSending = false
                    }
                }
            }
        )
    }
    
    @objc private func stopStreamingTapped() {
        NetworkManager.shared.cancelStreaming()
        chatState = .idle
        inputView.isSending = false
    }
    
    // MARK: - Public Methods
    
    func clearChat() {
        clearChatTapped()
    }
    
    @objc private func clearChatTapped() {
        messages.removeAll()
        chatTextView.string = ""
        statusLabel.isHidden = true
        statusLabel.stringValue = ""
    }
    
    // MARK: - Chat UI Updates
    
    private func appendMessageToChat(_ message: Message) {
        let prefix: String
        let color: NSColor
        
        switch message.role {
        case "user":
            prefix = "👤 Вы"
            color = NSColor.systemBlue
        case "assistant":
            prefix = "🤖 Ассистент"
            color = NSColor.systemGreen
        case "system":
            prefix = "⚙️ Система"
            color = NSColor.systemGray
        default:
            prefix = message.role
            color = NSColor.textColor
        }
        
        let attributedString = NSMutableAttributedString()
        
        let roleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: color
        ]
        attributedString.append(NSAttributedString(string: "\n\(prefix):\n", attributes: roleAttributes))
        
        
        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        attributedString.append(NSAttributedString(string: message.content, attributes: contentAttributes))
        
        chatTextView.textStorage?.append(attributedString)
        scrollToBottom()
    }
    
    
    
    private func appendTokenToLastAssistantMessage(_ token: String) {
        if messages.last?.role != "assistant" {
            messages.append(Message(role: .assistant, content: token))
            
            let attributedString = NSMutableAttributedString()
            let roleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.systemGreen
            ]
            attributedString.append(NSAttributedString(string: "\n🤖 Ассистент:\n", attributes: roleAttributes))
            
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            attributedString.append(NSAttributedString(string: token, attributes: contentAttributes))
            
            chatTextView.textStorage?.append(attributedString)
        } else {
            messages[messages.count - 1].content += token
            
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            let attributedString = NSAttributedString(string: token, attributes: contentAttributes)
            chatTextView.textStorage?.append(attributedString)
        }
        
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        let range = NSRange(location: max(0, chatTextView.string.count - 1), length: 1)
        chatTextView.scrollRangeToVisible(range)
    }
    
    private func updateStateUI() {
        switch chatState {
        case .idle:
            inputView.isSending = false
            statusLabel.isHidden = true
        case .loading:
            inputView.isSending = true
            statusLabel.isHidden = true
        case .error(let message):
            inputView.isSending = false
            statusLabel.isHidden = false
            statusLabel.stringValue = "❌ \(message)"
        }
    }
}

// MARK: - MessageInputViewDelegate

extension ChatViewController: MessageInputViewDelegate {
    func messageInputView(_ view: MessageInputView, didSubmitMessage message: String) {
        sendMessage(message)
    }

    func messageInputViewDidTapStop(_ view: MessageInputView) {
        stopStreamingTapped()
    }

    func messageInputViewDidTapClear(_ view: MessageInputView) {
        clearChatTapped()
    }
}


private extension ChatViewController {
    private func setupDebug() {
        appendMessageToChat(Message(role: .user, content: "что то ввел"))
        appendMessageToChat(Message(role: .assistant, content: Constants.longText))
    }
}
