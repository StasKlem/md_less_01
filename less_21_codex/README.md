# LightNeiroClient Monorepo

## Как работает RAG в приложении

RAG в `LightNeiroClient` включается настройкой `Enable RAG` и работает как часть обычного чата:

1. При первом запросе пользователя (для выбранной `RAG chunking` стратегии) клиент проверяет, готов ли индекс.
2. Если индекс не готов - выполняется индексация документов.
3. Для текущего сообщения пользователя строится embedding-запрос, выполняется поиск top-4 релевантных чанков.
4. Найденные фрагменты добавляются в `system prompt` как блок контекста (`source`, `section`, `offset`, `text`).

### 1) Разбиение документов на чанки

Пайплайн индексации:

- каждый документ сначала парсится в `ParsedDocument` (`fullText + sections`);
- затем выбранная chunking-стратегия превращает документ в массив `ChunkDraft` (`content`, `source`, `title`, `section`, `offset`).

По умолчанию для индекса используются документы:

- `README.md`
- `LightNeiroClient/LightNeiroClient/Doc/mobile_system_design_guide.md`

### 2) Генерация эмбеддингов

После chunking все `chunk.content` отправляются в embedding provider:

- по умолчанию используется `AppLLMEmbeddingProvider`;
- модель по умолчанию: `mistralai/mistral-embed-2312`;
- размерность по умолчанию: `768`;
- `normalizeEmbeddings = true` (векторы нормализуются к unit-length);
- запрос отправляется на endpoint `/embeddings` того же LLM-провайдера, что и основной чат.

Если количество эмбеддингов не совпадает с количеством чанков, индексация падает с ошибкой `invalidEmbeddingDimension`.

### 3) Сохранение индекса

Сгенерированные `DocumentChunk` сохраняются во `VectorStore` (по умолчанию `SQLiteVSSVectorStore`):

- БД: `~/Library/Application Support/LightNeiroClient/rag.sqlite`;
- таблица `document_chunks` хранит текст чанка, embedding (`BLOB`), метаданные источника и offset;
- при доступном `sqlite-vss` дополнительно заполняется virtual table `vss_document_chunks` для ANN-поиска;
- если `sqlite-vss` недоступен, поиск выполняется fallback-сканированием с `cosine similarity` по всем сохранённым чанкам.

Индекс строится лениво (on-demand) и кешируется в памяти по выбранной стратегии chunking: повторная индексация в той же сессии не выполняется, пока стратегия не изменится.

### Как работают стратегии chunking

Поддерживаются две стратегии (`ChunkingStrategyType`):

- `fixed`
- `structural`

#### `fixed` (FixedSizeChunker)

- Делит `fullText` на окна фиксированного размера.
- Параметры по умолчанию: `chunkSize = 800`, `overlap = 120`.
- Смещение (`offset`) каждого чанка считается от начала полного текста документа.
- `section` для таких чанков не заполняется (`nil`).

Когда подходит: равномерные документы без чёткой структуры, где важен предсказуемый размер чанков.

#### `structural` (StructuralChunker)

- Работает по `document.sections`, которые формируются парсером:
  - Markdown: секции по заголовкам `#`;
  - Code: секции по маркерам (`struct`, `class`, `func`, `protocol`, и т.д.);
  - PDF: секции по страницам (`Page N`);
  - Plain text: одна секция на весь файл.
- Если секция короткая (`<= maxSectionSize`), она становится одним чанком.
- Если секция длинная, она дополнительно дробится встроенным `FixedSizeChunker`.
- Параметры по умолчанию: `maxSectionSize = 1200`, fallback `chunkSize = 800`, `overlap = 120`.
- Для всех чанков сохраняется `section`, что улучшает трассировку источника в ответе.

Когда подходит: структурированные документы (техдоки, markdown, код), где важна семантика разделов.

## Hacker News Task Agent

`Hacker News Task Agent` работает в режиме `one-shot` (без таймеров и интервалов): один запуск = один полный цикл.

Последовательность выполнения:

1. получает новость через MCP tool `hackernews_get_random_story`;
2. получает перевод новости через MCP tool `hackernews_translate_story`;
3. сохраняет перевод через MCP tool `hackernews_archive_save_json`.

Важно: это три разных MCP-сервера (три отдельных subprocess):

- шаг 1: `stdio://hackernews` -> `HackerNewsMCPServer`;
- шаг 2: `stdio://hackernews-translate` -> `HackerNewsTranslateMCPServer`;
- шаг 3: `stdio://hackernews-archive` -> `HackerNewsArchiveMCPServer`.

Системные сообщения в чате приходят сразу (потоково): перед каждым шагом и после него с результатом.

Особенности:

- `start` не запускает фоновый таймер, а выполняет один цикл и завершает агент в `idle`;
- каждые 5 выполнений дополнительно строится LLM-сводка последних новостей;
- перевод использует тот же API key и модель, что и приложение (`Settings` + keychain), и совместимый base URL LLM-провайдера.

Команды агента:

- `/hn start` - выполнить один цикл `fetch -> translate -> save`
- `/hn stop` - остановить агент

Для явных путей к MCP-серверам можно задать:

- `HACKERNEWS_MCP_SERVER_PATH=/abs/path/to/HackerNewsMCPServer`
- `HACKERNEWS_TRANSLATE_MCP_SERVER_PATH=/abs/path/to/HackerNewsTranslateMCPServer`
- `HACKERNEWS_ARCHIVE_MCP_SERVER_PATH=/abs/path/to/HackerNewsArchiveMCPServer`

Если пути не заданы, клиент пытается автоматически найти локальные пакеты MCP-серверов в workspace и запускать их через `swift run`.

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

Монорепозиторий с macOS-клиентом `LightNeiroClient` (AppKit + MVVM) и локальными MCP-серверами `OpenWeatherMCPServer`, `HackerNewsMCPServer`, `HackerNewsArchiveMCPServer`, `HackerNewsSummaryMCPServer` и `HackerNewsTranslateMCPServer`.

## Что внутри

- `LightNeiroClient`: чат-клиент на `AppKit` с memory layers, метриками сессии и сценарным Vacation Planner.
- `OpenWeatherMCPServer`: MCP сервер (`stdio`) с инструментами погоды OpenWeather.
- `HackerNewsMCPServer`: MCP сервер (`stdio`) с инструментом случайной новости из Hacker News.
- `HackerNewsArchiveMCPServer`: MCP сервер (`stdio`) для сохранения JSON в файл и чтения 3 последних сохранений.
- `HackerNewsSummaryMCPServer`: MCP сервер (`stdio`) для LLM-суммаризации списка новостей Hacker News.
- `HackerNewsTranslateMCPServer`: MCP сервер (`stdio`) для LLM-перевода одной новости Hacker News в формате `hackernews_get_random_story`.

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

### Запуск HackerNewsTranslateMCPServer

```bash
cd HackerNewsTranslateMCPServer
HACKERNEWS_TRANSLATE_OPENAI_API_KEY=your_key swift run HackerNewsTranslateMCPServer
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

## Переменные окружения HackerNewsTranslateMCPServer

- `HACKERNEWS_TRANSLATE_OPENAI_API_KEY` (обязательно для вызова LLM)
- `HACKERNEWS_TRANSLATE_OPENAI_BASE_URL` (опционально, default `https://api.openai.com/v1`)
- `HACKERNEWS_TRANSLATE_OPENAI_MODEL` (опционально, default `gpt-4o-mini`)
- `HACKERNEWS_TRANSLATE_SYSTEM_PROMPT` (опционально, кастомный system prompt)
- `HACKERNEWS_TRANSLATE_LOG_LEVEL` (опционально, default `info`, значения `debug|info|warn|error`)

## Структура репозитория

- `LightNeiroClient/` - macOS клиент.
- `OpenWeatherMCPServer/` - MCP сервер OpenWeather.
- `HackerNewsMCPServer/` - MCP сервер Hacker News.
- `HackerNewsArchiveMCPServer/` - MCP сервер архива JSON для Hacker News.
- `HackerNewsSummaryMCPServer/` - MCP сервер суммаризации новостей Hacker News через LLM.
- `HackerNewsTranslateMCPServer/` - MCP сервер перевода новости Hacker News через LLM.
- `AGENTS.md` - инженерные правила проекта.

## Ограничения текущей версии

- одна активная ветка диалога без UI для полноценного branch management;
- извлечение полей и генерация плана зависят от доступности LLM и корректного API-ключа;
- отдельной формы для анкеты Vacation Planner нет (используется чатовый pipeline).
