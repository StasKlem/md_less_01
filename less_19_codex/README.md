# LightNeiroClient Monorepo

## HackerNewsMCPServer (MCP)

`HackerNewsMCPServer` - локальный MCP сервер (transport `stdio`) с инструментом:

- `hackernews_get_random_story` - возвращает случайную статью из top stories Hacker News (title, id, author, score, time, url).

Запуск сервера:

```bash
cd HackerNewsMCPServer
swift run HackerNewsMCPServer
```

Переменные окружения сервера:

- `HACKERNEWS_BASE_URL` (опционально, по умолчанию `https://hacker-news.firebaseio.com`)
- `HACKERNEWS_LOG_LEVEL` (опционально, `debug|info|warn|error`, по умолчанию `info`)

## Hacker News Task Agent

В `LightNeiroClient` добавлен task-агент `Hacker News Task Agent`:

- каждые `N` секунд (по умолчанию `5`, настраивается) вызывает MCP tool `hackernews_get_random_story`;
- каждую полученную статью сохраняет в JSON-файл в `Application Support/LightNeiroClient/task_flow/hacker_news_articles/...`;
- выводит короткое системное сообщение по статье;
- каждые 5 запросов отправляет LLM-запрос с суммаризацией последних статей и показывает результат в чате.

Команды агента:

- `/hn start` - запуск с интервалом по умолчанию (5 сек)
- `/hn start <сек>` - запуск с заданным интервалом
- `/hn interval <сек>` - изменить интервал
- `/hn stop` - остановить агент

Для явного пути к MCP-серверу можно задать:

- `HACKERNEWS_MCP_SERVER_PATH=/abs/path/to/HackerNewsMCPServer`

Монорепозиторий с macOS-клиентом `LightNeiroClient` (AppKit + MVVM) и локальными MCP-серверами `OpenWeatherMCPServer`, `HackerNewsMCPServer`, `HackerNewsArchiveMCPServer` и `HackerNewsSummaryMCPServer`.

## Что внутри

- `LightNeiroClient`: чат-клиент на `AppKit` с memory layers, метриками сессии и сценарным Vacation Planner.
- `OpenWeatherMCPServer`: MCP сервер (`stdio`) с инструментами погоды OpenWeather.
- `HackerNewsMCPServer`: MCP сервер (`stdio`) с инструментом случайной новости из Hacker News.
- `HackerNewsArchiveMCPServer`: MCP сервер (`stdio`) для сохранения JSON в файл и чтения 3 последних сохранений.
- `HackerNewsSummaryMCPServer`: MCP сервер (`stdio`) для LLM-суммаризации списка новостей Hacker News.

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

### Запуск HackerNewsArchiveMCPServer

```bash
cd HackerNewsArchiveMCPServer
swift run HackerNewsArchiveMCPServer
```

### Запуск HackerNewsSummaryMCPServer

```bash
cd HackerNewsSummaryMCPServer
HACKERNEWS_SUMMARY_OPENAI_API_KEY=your_key swift run HackerNewsSummaryMCPServer
```

## Переменные окружения OpenWeatherMCPServer

- `OPENWEATHER_API_KEY` (для реальных weather вызовов)
- `OPENWEATHER_BASE_URL` (опционально, default `https://api.openweathermap.org`)
- `OPENWEATHER_DEFAULT_LANG` (опционально)

## Переменные окружения HackerNewsMCPServer

- `HACKERNEWS_BASE_URL` (опционально, default `https://hacker-news.firebaseio.com`)
- `HACKERNEWS_LOG_LEVEL` (опционально, default `info`, значения `debug|info|warn|error`)

## Переменные окружения HackerNewsArchiveMCPServer

- `HACKERNEWS_ARCHIVE_STORAGE_DIR` (опционально, директория хранения JSON файлов)
- `HACKERNEWS_ARCHIVE_LOG_LEVEL` (опционально, default `info`, значения `debug|info|warn|error`)

## Переменные окружения HackerNewsSummaryMCPServer

- `HACKERNEWS_SUMMARY_OPENAI_API_KEY` (обязательно для вызова LLM)
- `HACKERNEWS_SUMMARY_OPENAI_BASE_URL` (опционально, default `https://api.openai.com/v1`)
- `HACKERNEWS_SUMMARY_OPENAI_MODEL` (опционально, default `gpt-4o-mini`)
- `HACKERNEWS_SUMMARY_SYSTEM_PROMPT` (опционально, кастомный system prompt)
- `HACKERNEWS_SUMMARY_LOG_LEVEL` (опционально, default `info`, значения `debug|info|warn|error`)

## Структура репозитория

- `LightNeiroClient/` - macOS клиент.
- `OpenWeatherMCPServer/` - MCP сервер OpenWeather.
- `HackerNewsMCPServer/` - MCP сервер Hacker News.
- `HackerNewsArchiveMCPServer/` - MCP сервер архива JSON для Hacker News.
- `HackerNewsSummaryMCPServer/` - MCP сервер суммаризации новостей Hacker News через LLM.
- `AGENTS.md` - инженерные правила проекта.

## Ограничения текущей версии

- одна активная ветка диалога без UI для полноценного branch management;
- извлечение полей и генерация плана зависят от доступности LLM и корректного API-ключа;
- отдельной формы для анкеты Vacation Planner нет (используется чатовый pipeline).
