# Техническое Задание: LLM Client для macOS

## 1. Общее Описание

**Название проекта:** MacTerminalOpencode  
**Платформа:** macOS 26.2+  
**Язык:** Swift 5.0  
**UI Framework:** Cocoa (AppKit)  
**Bundle ID:** StasKlem.MacTerminalOpencode  
**Архитектура:** MVVM (Model-View-ViewModel) с Use Cases

### Назначение

Нативное macOS приложение для взаимодействия с LLM (Large Language Model) API в стиле чата. Поддерживает OpenAI-совместимые API (Ollama, LM Studio и др.), стриминг ответов, сохранение контекста и отображение метрик использования.

---

## 2. Архитектура Приложения

### Слои приложения

```
┌─────────────────────────────────────────────┐
│                 UI Layer                     │
│  (ViewControllers, Views, Storyboards)     │
├─────────────────────────────────────────────┤
│              ViewModel Layer                │
│  (ChatViewModel, SettingsViewModel, etc.)  │
├─────────────────────────────────────────────┤
│              UseCase Layer                  │
│  (SendMessageUseCase, FetchModelsUseCase)  │
├─────────────────────────────────────────────┤
│               Domain Layer                   │
│  (Entities, Protocols, Business Logic)      │
├─────────────────────────────────────────────┤
│                Data Layer                    │
│  (Network, Storage, External Services)      │
└─────────────────────────────────────────────┘
```

### Структура проекта

```
MacTerminalOpencode/
├── App/
│   ├── AppDelegate.swift
│   └── Constants.swift
├── Domain/
│   ├── Entities/
│   │   ├── AppError.swift
│   │   ├── ChatSession.swift
│   │   ├── LLMSettings.swift
│   │   ├── Message.swift
│   │   └── StreamingChunk.swift
│   └── UseCases/
│       ├── FetchModelsUseCase.swift
│       └── SendMessageUseCase.swift
├── Data/
│   ├── Network/
│   │   ├── LLMAPIClient.swift
│   │   ├── NetworkManager.swift
│   │   └── SSEParser.swift
│   └── Storage/
│       ├── ChatStorage.swift
│       ├── KeychainService.swift
│       └── SettingsStorage.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── MetricsViewModel.swift
│   └── SettingsViewModel.swift
└── UI/
    ├── Components/
    │   └── MarkdownAttributedString.swift
    ├── SplitView/
    │   └── MainSplitViewController.swift
    └── Views/
        ├── ChatPanelViewController.swift
        ├── MetricsPanelViewController.swift
        └── SettingsPanelViewController.swift
```

---

## 3. Функциональные Требования

### 3.1 Чат-панель (Chat Panel)

**Описание:** Основная панель для отправки сообщений и просмотра ответов.

**Компоненты:**
- `NSScrollView` с `NSTextView` для отображения сообщений
- `NSTextField` для ввода сообщения
- `NSButton` "Send" для отправки
- `NSButton` "Clear" для очистки чата
- `NSProgressIndicator` для индикации загрузки

**Функциональность:**
- Отправка сообщений по нажатию кнопки или Enter
- Перенос строк по Shift+Enter
- Автоматическая прокрутка к последнему сообщению
- Отображение сообщений с разделением по ролям (You / Assistant / System)
- Поддержка Markdown-форматирования в ответах
- Индикация ошибок красным цветом

### 3.2 Панель настроек (Settings Panel)

**Описание:** Панель для настройки подключения к LLM API.

**Параметры настройки:**
1. **Server URL** - URL LLM API (по умолчанию: `http://localhost:11434/v1`)
2. **Model** - Выбор модели из списка предустановленных
3. **Temperature** - Slider от 0 до 2 (по умолчанию: 0.7)
4. **Max Tokens** - Максимальное количество токенов (по умолчанию: 2048)
5. **Enable Streaming** - Включение/выключение стриминга
6. **System Prompt** - Системный промпт
7. **Save Context** - Сохранение контекста между сессиями
8. **API Key** - Секретный ключ API (хранится в Keychain)

**Предустановленные модели:**
- DeepSeek V3.2
- GPT-5.2
- Gemini 3.1 Pro
- qwen2.5-coder-7b-instruct
- deepseek-r1
- claude-sonnet-4.6
- minimax-m2.5

### 3.3 Панель метрик (Metrics Panel)

**Описание:** Панель для отображения статистики использования.

**Отображаемые метрики:**
- Количество запросов
- Общее количество токенов
- Среднее время отклика
- Текущая скорость (tokens/sec)

### 3.4 Сетевой клиент (LLM API Client)

**Требования:**
- Поддержка OpenAI-совместимого API
- Поддержка стриминга через Server-Sent Events (SSE)
- Аутентификация через Bearer token
- Таймаут запросов: 60 секунд (120 для стриминга)

**Эндпоинты:**
- `POST /chat/completions` - Отправка сообщений
- `GET /models` - Получение списка моделей

### 3.5 Хранение данных

**SettingsStorage (UserDefaults):**
- Server URL
- Model Name
- Temperature
- Max Tokens
- Enable Streaming
- System Prompt
- Save Context

**KeychainService:**
- API Key (безопасное хранение)

**ChatStorage (UserDefaults):**
- Сообщения чата (сериализация в JSON)
- Только при включённой опции Save Context

---

## 4. Нефункциональные Требования

### 4.1 UI/UX

- Использование AppKit (не SwiftUI)
- Storyboard для главного интерфейса
- Split View: чат слева, настройки/метрики справа
- Auto Layout для адаптивного интерфейса
- Поддержка Dark Mode через semantic colors

### 4.2 Безопасность

- API ключ хранится в Keychain
- App Sandbox с доступом только для чтения к выбранным пользователем файлам
- Hardened Runtime включён

### 4.3 Конкурентность

- Swift Concurrency (async/await)
- Swift Strict Concurrency Checking
- MainActor isolation по умолчанию
- Actor для ChatSession (потокобезопасность)

---

## 5. Техническая Реализация

### 5.1 Основные протоколы

```swift
// Send Message UseCase
protocol SendMessageUseCaseProtocol {
    func execute(
        content: String,
        settings: LLMSettings,
        onEvent: @escaping (SendMessageEvent) -> Void
    ) async
}

// Fetch Models UseCase
protocol FetchModelsUseCaseProtocol {
    func execute(settings: LLMSettings) async throws -> [String]
}

// Network Manager
protocol NetworkManagerProtocol {
    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T
    func performStreamingRequest(_ request: URLRequest) -> AsyncThrowingStream<Data, Error>
}

// Storage Protocols
protocol SettingsStorageProtocol {
    func loadSettings() -> LLMSettings
    func saveSettings(_ settings: LLMSettings)
}

protocol ChatStorageProtocol: AnyObject {
    func saveMessages(_ messages: [Message])
    func loadMessages() -> [Message]
    func clearMessages()
}

protocol KeychainServiceProtocol {
    func saveAPIKey(_ key: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}
```

### 5.2 Сущности (Entities)

```swift
// Message
struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var error: String?
}

enum MessageRole: String, Codable {
    case user, assistant, system
}

// LLMSettings
struct LLMSettings: Equatable {
    var serverURL: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var enableStreaming: Bool
    var systemPrompt: String
    var saveContext: Bool
}

// ChatSession (Actor)
actor ChatSession {
    private(set) var messages: [Message]
    // Methods: addMessage, updateMessage, appendToMessage, clearMessages, messagesForAPI
}
```

### 5.3 Обработка ошибок

```swift
enum AppError: LocalizedError {
    case network(NetworkError)
    case storage(StorageError)
    case validation(SettingsValidationError)
    case parsing(ParsingError)
    case unknown(String)
}
```

### 5.4 Markdown парсинг

Реализовать преобразование Markdown-текста в NSAttributedString:
- Жирный текст (**text**)
- Курсив (*text*)
- Заголовки (# text)
- Маркированные списки (- item)
- Однострочный код (`code`)
- Многострочный код (```code```)

---

## 6. Сборка и Запуск

### Сборка

```bash
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj \
  -scheme MacTerminalOpencode \
  -configuration Debug build
```

### Запуск

```bash
open MacTerminalOpencode/build/Debug/MacTerminalOpencode.app
```

### Тесты

```bash
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj \
  -scheme MacTerminalOpencode test
```

---

## 7. Требования к Среде

- macOS 26.2 или выше
- Xcode 17+
- Swift 5.0
- Keychain Access (для API ключа)
- Сетевое подключение к LLM серверу

---

## 8. Примеры API Запросов

### Chat Completion (Non-Streaming)

```json
POST /chat/completions
{
  "model": "llama3.2",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 2048,
  "stream": false
}
```

### Chat Completion (Streaming)

```json
POST /chat/completions
{
  "model": "llama3.2",
  "messages": [...],
  "temperature": 0.7,
  "max_tokens": 2048,
  "stream": true
}
```

Ответ в формате SSE:
```
data: {"id":"...","choices":[{"delta":{"content":"Hello"}}]}

data: [DONE]
```

---

## 9. Критерии Приёмки

1. ✅ Приложение запускается без ошибок
2. ✅ Чат работает с локальным Ollama сервером
3. ✅ Сообщения отображаются с Markdown форматированием
4. ✅ Стриминг работает корректно
5. ✅ Настройки сохраняются между сессиями
6. ✅ API ключ безопасно хранится в Keychain
7. ✅ Опция "Сохранять контекст" работает корректно
8. ✅ Метрики отображаются корректно
9. ✅ Проект собирается без warnings
10. ✅ SwiftLint не выявляет критических проблем

---

## 10. Gitignore

Для проекта необходимо добавить следующие игнорируемые файлы:

```gitignore
# Xcode
.DS_Store
*.xcuserstate
*.xcuserdatad
DerivedData/
build/
xcuserdata/
*.xcworkspace/xcuserdata/

# Swift
Packages/
.swiftpm/

# CocoaPods
Pods/
Podfile.lock

# macOS
.AppleDouble
.LSOverride
Icon?
.Trashes
```

---

## 11. Контакты и Ссылки

- **Bundle ID:** StasKlem.MacTerminalOpencode
- **Keychain Service:** com.stasklem.MacTerminalOpencode
- **Default Server:** http://localhost:11434/v1
