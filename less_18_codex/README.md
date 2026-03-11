# LightNeiroClient Monorepo

Монорепозиторий с macOS-клиентом `LightNeiroClient` (AppKit + MVVM) и локальными MCP-серверами `OpenWeatherMCPServer` и `HackerNewsMCPServer`.

## Что внутри

- `LightNeiroClient`: чат-клиент на `AppKit` с memory layers, метриками сессии и сценарным Vacation Planner.
- `OpenWeatherMCPServer`: MCP сервер (`stdio`) с инструментами погоды OpenWeather.
- `HackerNewsMCPServer`: MCP сервер (`stdio`) с инструментом случайной новости из Hacker News.

## Ключевые возможности LightNeiroClient

- чат с LLM;
- настройки модели (`model`, `temperature`, `windowSize`, API key, `plannerInvariants`);
- память контекста (short-term / working / long-term);
- экран метрик сессии (токены, запросы, задержка);
- Vacation Planner на базе конечного автомата (FSM);
- MCP интеграция: получение списка `tools` и погодных данных через `open-weather`.

## Vacation Planner FSM (актуально)

### Состояния

- `idle`
- `destinationRequest`
- `validatingDestination`
- `awaitingPlanApproval`
- `generateResult`
- `failed(reason)`

### Разрешенные переходы

1. `idle` + `started|userMessage` -> `destinationRequest`
2. `destinationRequest` + `userMessage` -> `validatingDestination`
3. `validatingDestination` + `questionnaireProcessed` (invalid) -> `destinationRequest`
4. `validatingDestination` + `questionnaireProcessed` (valid) -> `awaitingPlanApproval`
5. `awaitingPlanApproval` + `planApproved` -> `generateResult`
6. `awaitingPlanApproval` + `revisionRequested` -> `destinationRequest`
7. `generateResult` + `optionsGenerated|itineraryGenerated` -> `generateResult`
8. `generateResult` + `budgetCalculated` -> `idle`
9. `failed(reason)` + `started` -> `destinationRequest`
10. `failed(reason)` + `userMessage` -> `validatingDestination`
11. Любое состояние + `errorOccurred` -> `failed(reason)`

### Важно

- События `executionCompleted`, `validationPassed`, `validationFailed`, `finalizeRequested` есть в модели, но не имеют разрешенных переходов в текущем FSM.
- После `budgetCalculated` формируется `finalPlan`, блокируется редактирование результата и состояние возвращается в `idle`.

## Команды пользователя в чате

- `/vacation start` или `/vacation` - запуск сценария планировщика.
- `/vacation stop` - выход из режима планировщика.
- `approve` - подтверждение плана и запуск генерации результата.
- `revise: <комментарий>` - возврат к уточнению направления поездки.

## MCP интеграция (`open-weather`)

- Клиент использует endpoint `stdio://open-weather`.
- По умолчанию запускается локальный `OpenWeatherMCPServer` как subprocess.
- Для явного пути к серверу:
  - `OPENWEATHER_MCP_SERVER_PATH=/abs/path/to/OpenWeatherMCPServer`
- При старте Vacation Planner клиент:
  - подключается к MCP;
  - получает `tools/list`;
  - публикует системное сообщение со списком доступных инструментов.

## Архитектура

`LightNeiroClient` следует Clean Architecture:

- `Presentation`: AppKit контроллеры и ViewModel.
- `Domain`: сущности, контракты и use cases (включая FSM).
- `Data`: реализации сервисов/репозиториев (LLM, storage, keychain, MCP).

Зависимости направлены внутрь: outer layers зависят от абстракций `Domain`.

## Быстрый старт

### Требования

- macOS
- Xcode 15+ (для клиента)
- Swift 5.9+ (для MCP сервера)

### Запуск LightNeiroClient (Xcode)

1. Откройте `LightNeiroClient/LightNeiroClient.xcodeproj`.
2. Выберите схему `LightNeiroClient`.
3. Выполните `Run`.

### Сборка LightNeiroClient (CLI)

```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -configuration Debug build
```

### Тесты LightNeiroClient

```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -destination 'platform=macOS' test
```

### Запуск OpenWeatherMCPServer

```bash
cd OpenWeatherMCPServer
OPENWEATHER_API_KEY=your_key swift run OpenWeatherMCPServer
```

### Запуск HackerNewsMCPServer

```bash
cd HackerNewsMCPServer
swift run HackerNewsMCPServer
```

## Переменные окружения OpenWeatherMCPServer

- `OPENWEATHER_API_KEY` (для реальных weather вызовов)
- `OPENWEATHER_BASE_URL` (опционально, default `https://api.openweathermap.org`)
- `OPENWEATHER_DEFAULT_LANG` (опционально)

## Переменные окружения HackerNewsMCPServer

- `HACKERNEWS_BASE_URL` (опционально, default `https://hacker-news.firebaseio.com`)
- `HACKERNEWS_LOG_LEVEL` (опционально, default `info`, значения `debug|info|warn|error`)

## Структура репозитория

- `LightNeiroClient/` - macOS клиент.
- `OpenWeatherMCPServer/` - MCP сервер OpenWeather.
- `HackerNewsMCPServer/` - MCP сервер Hacker News.
- `AGENTS.md` - инженерные правила проекта.

## Ограничения текущей версии

- одна активная ветка диалога без UI для полноценного branch management;
- извлечение полей и генерация плана зависят от доступности LLM и корректного API-ключа;
- отдельной формы для анкеты Vacation Planner нет (используется чатовый pipeline).
