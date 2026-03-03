# Выводы

Сравните:
👉 качество ответа
👉 стабильность (не теряет ли важные детали)
👉 расход токенов
👉 удобство для пользователя

сравнивал две статегии Стратегия 1: Sliding Window, Стратегия 2: Sticky Facts / Key-Value Memory

## Общие выводы 
Sliding Window - тратит меньшье токенов но дает результат хуже. Из за того что первые сообщения постепенно удаляюся контекст задачи размывается, могут потеряться важные детали.

Sticky Facts / Key-Value Memory - тратиться больше токенов, но за счет хранения "важных сведений" диалог не теряет детали разговора.

## качество ответа
Sliding Window - качество ответа ниже, теряются детали
Sticky Facts / Key-Value Memory - качество ответа выше

## стабильность (не теряет ли важные детали)
Sliding Window - теряются детали
Sticky Facts / Key-Value Memory - сохраняются важные детали разговора

## расход токенов
Sliding Window - меньше
Sticky Facts / Key-Value Memory - значительно больше

## удобство для пользователя
Sliding Window - может быть удобнее если важна скорость ответов
Sticky Facts / Key-Value Memory - может быть удобнее если важна точнось выводов и результат


# LightNeiroClient

## Context Strategy и логика переключения веток (главное)

### Context Strategy: как формируется контекст для LLM

В проекте есть три режима контекста (`ContextStrategy`):

1. `normal`
- Источник логики: `BuildContextUseCase.execute(...)`.
- В контекст отправляются все сообщения активной ветки, кроме `system`.
- `facts` не используются.
- Поведение: максимальная полнота истории, но и максимальная нагрузка по токенам.

2. `slidingWindow`
- Источник логики: `BuildContextUseCase.execute(...)`.
- В контекст отправляются только последние `windowSize` сообщений (после фильтрации `system`).
- `facts` не используются.
- Поведение: контролируемая стоимость/латентность, но ранний контекст постепенно теряется.

3. `stickyFacts`
- Источник логики: `BuildContextUseCase.execute(...)` + `UpdateFactsUseCase.execute(...)`.
- В контекст отправляются:
  - `facts`: извлечённые устойчивые факты по всей сессии (`sessionID`),
  - сообщения: последние `windowSize` сообщений активной ветки.
- При отправке нового сообщения `SendMessageUseCase` перед основным ответом запускает `UpdateFactsUseCase` (через `try?`, то есть без блокировки ответа при сбое извлечения фактов).
- `UpdateFactsUseCase`:
  - берёт последнее сообщение пользователя,
  - берёт последний ответ ассистента в ветке,
  - вызывает LLM в режиме JSON extraction,
  - мержит результат с текущими фактами,
  - всегда обновляет факт `last-user-message`.
- Поведение: короткий диалоговый контекст + долгоживущая память по сессии.

### Важная деталь: стратегия хранится по веткам

`LLMSettings` хранит `contextStrategyByBranch: [UUID: ContextStrategy]`.
- `contextStrategy(for: branchID)` возвращает стратегию ветки или fallback на общее `contextStrategy`.
- `setContextStrategy(_, for:)` обновляет:
  - запись конкретной ветки,
  - общее поле `contextStrategy` (для корректного отображения текущего выбранного режима в UI).

Это даёт независимую стратегию на каждую ветку внутри одной сессии.

### Логика переключения веток

Переключение веток реализовано в `ChatViewModel.selectHistoryItem(at:)` и `SwitchBranchUseCase`.

Последовательность:
1. Пользователь выбирает ветку в таблице истории.
2. `ChatViewModel` валидирует:
- нет активной отправки (`isSending == false`),
- индекс валиден,
- ветка не совпадает с текущей.
3. Вызывается `SwitchBranchUseCase.execute(sessionID, targetBranchID)`:
- загружается `ChatSession`,
- обновляется `activeBranchID`,
- сессия сохраняется в репозиторий.
4. Если успех:
- `ChatViewModel.activeBranchID` обновляется,
- вызывается `onActiveBranchChanged`.
5. `MainViewModel` на `onActiveBranchChanged` синхронизирует остальные зоны:
- `SettingsViewModel.switchActiveBranch(to:)` переключает branch context в настройках и персистит,
- `SessionInfoViewModel.switchActiveBranch(to:)` переключает branch для метрик,
- `SessionInfoViewModel.refresh()` пересчитывает статистику по новой ветке.
6. `ChatViewModel` обновляет UI:
- перечитывает ветки (`refreshHistoryItems`),
- загружает диалог выбранной ветки (`loadDialog(for:)`).

Если переключение не удалось, в диалог добавляется системное сообщение с текстом ошибки.

### Логика создания ветки и автоматического перехода на неё

Создание ветки выполняется в `ChatViewModel.createBranch()`.

Последовательность:
1. Генерируется имя `branch-N` (`nextBranchName()`).
2. Запоминается текущая (source) ветка.
3. Создаётся новая ветка (`CreateBranchUseCase`).
4. Диалог source-ветки клонируется в новую (`CloneDialogToBranchUseCase`), но только если новая ветка ещё пуста.
5. Выполняется переключение сессии на новую ветку (`SwitchBranchUseCase`).
6. В новую ветку добавляется `system`-сообщение `создана ветка от [source]` (`AddBranchCreatedSystemMessageUseCase`).
7. Обновляется `activeBranchID`, вызывается `onActiveBranchChanged`, обновляются история и диалог UI.

Итог: пользователь сразу продолжает работу уже в новой ветке с копией контекста исходной ветки.

---

## Что это за проект

`LightNeiroClient` — desktop macOS-клиент чата с LLM на `AppKit`, построенный по `Clean Architecture` и `MVVM`.

Ключевые возможности:
- чат с ассистентом;
- несколько веток диалога в рамках одной сессии;
- переключение модели/температуры/размера окна контекста;
- режимы контекста (`normal`, `slidingWindow`, `stickyFacts`);
- сбор метрик по токенам/латентности на ветку;
- хранение API ключа в Keychain.

## Архитектура

Слои:
1. `Domain`
- сущности (`ChatMessage`, `ChatBranch`, `ChatSession`, `LLMSettings`, `StickyFact`);
- протоколы репозиториев и сервисов;
- use case’ы (бизнес-логика).

2. `Data`
- адаптеры внешнего мира:
  - `RouterAILLMClient` (HTTP-клиент к RouterAI),
  - `KeychainAPIKeyStore`,
  - mock-репозитории на in-memory actor (`InMemoryChatStore`).

3. `Presentation`
- `ViewModel` + `NSViewController` на AppKit;
- экраны: Chat, Settings, SessionInfo;
- composition и синхронизация через `MainViewModel`.

4. `App`
- `AppEnvironment.bootstrap()` собирает зависимости и начальные данные (`session`, `main` branch, default settings).

Правило зависимостей соблюдено: внешние детали зависят от domain-абстракций, а не наоборот.

## Структура проекта

- `LightNeiroClient/LightNeiroClient/App` — сборка окружения приложения.
- `LightNeiroClient/LightNeiroClient/Domain` — сущности, протоколы, use case’ы.
- `LightNeiroClient/LightNeiroClient/Data` — сетевой клиент, keychain, mock-хранилища.
- `LightNeiroClient/LightNeiroClient/Presentation` — UI и MVVM.
- `LightNeiroClient/LightNeiroClient/main.swift` — вход в macOS-приложение.

## Поток отправки сообщения

1. UI вызывает `ChatViewModel.send(text:)`.
2. `SendMessageUseCase` сохраняет пользовательское сообщение в ветку.
3. Загружаются настройки сессии.
4. Если активен `stickyFacts`, запускается обновление фактов.
5. `BuildContextUseCase` формирует `(facts, messages)` для LLM.
6. `RouterAILLMClient` отправляет запрос.
7. Ответ ассистента сохраняется в ветку.
8. Метрики запроса сохраняются (`input/output tokens`, `latency`).
9. UI обновляет диалог и блок метрик.

## Настройки и их влияние

`LLMSettings`:
- `model` — модель для RouterAI;
- `contextStrategy` — текущая стратегия контекста (с учётом branch mapping);
- `temperature` — хранится и передаётся в доменную модель запроса (готово для расширения провайдера);
- `windowSize` — размер окна для `slidingWindow`/`stickyFacts`;
- `contextStrategyByBranch` — map стратегий по веткам.

## Интеграция с RouterAI

- Endpoint по умолчанию: `https://routerai.ru/api/v1/chat/completions`.
- Ключ читается из Keychain (через `apiKeyProvider`) или из переменной окружения `ROUTERAI_API_KEY` в default-конфигурации.
- Ошибки API и валидации payload обрабатываются через `RouterAILLMClientError`.

## Хранение данных

Сейчас используется in-memory реализация (`Mock*Repository` + `InMemoryChatStore`):
- данные живут в памяти процесса;
- после перезапуска приложения история/ветки/факты/метрики очищаются;
- API-ключ сохраняется отдельно, в Keychain macOS.

## UI-композиция

- `MainSplitViewController`:
  - слева: `ChatSidebarViewController` (история веток + диалог + ввод);
  - справа: `RightPaneSplitViewController` с:
    - `SettingsViewController`,
    - `SessionInfoViewController`.

Это обеспечивает независимость экранов и синхронизацию состояния через `MainViewModel`.

## Запуск проекта

Требования:
- macOS;
- Xcode 15+ (рекомендуется актуальная версия).

Сборка в Xcode:
1. Открыть `LightNeiroClient/LightNeiroClient.xcodeproj`.
2. Выбрать схему `LightNeiroClient`.
3. Запустить `Run`.

CLI-сборка:
```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -configuration Debug build
```

## Текущее состояние тестов

На текущий момент в репозитории нет отдельного test target и unit-тестов (`XCTest`).
Для соблюдения инженерных правил рекомендуется добавить:
- тесты use case’ов (`BuildContextUseCase`, `SendMessageUseCase`, `SwitchBranchUseCase`);
- тесты edge/failure сценариев (ошибка API, пустой ввод, переключение на несуществующую ветку);
- тесты для branch-specific настроек (`contextStrategyByBranch`).

## Ограничения и ближайшие улучшения

Ограничения текущей реализации:
- нет персистентного хранения сессий/веток/фактов/метрик (кроме API ключа);
- нет стриминга токенов (ответ приходит целиком);
- checkpoint-ветвление в UI пока не используется (есть доменная модель и use case).

Практичные следующие шаги:
1. Вынести хранилище из `Mock*` в персистентный адаптер (например, SQLite/CoreData).
2. Добавить unit-тесты доменного слоя.
3. Подключить стриминговый вывод ответа в `DialogHistoryViewController`.
4. Реализовать UI для checkpoint-ветвления и управления фактической иерархией веток.
