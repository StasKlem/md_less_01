# LightNeiroClient

LightNeiroClient — macOS-приложение на Swift (AppKit, MVVM, Clean Architecture) для диалогов с LLM, с поддержкой памяти, RAG-поиска по локальным документам и встроенных task-агентов.

## RAG и формат ответа (сначала главное)

### Как работает RAG в runtime

Когда `isRAGEnabled = true` и индекс готов, перед ответом LLM выполняется такой пайплайн:

1. Retrieval кандидатов: `topK = ragTopKBeforeFiltering` (по умолчанию `8`).
2. Пост-фильтрация по порогу: `score >= ragRelevanceThreshold` (по умолчанию `0.70`).
3. Финальное ограничение: `ragTopKAfterFiltering` (по умолчанию `4`).
4. Передача найденных фрагментов в блок `RAG_EVIDENCE` внутри system prompt.

Если `isRAGPostFilteringEnabled = false`, используется legacy-ветка без порога (поиск сразу с `topK = 4`).

### Контракт ответа от LLM в RAG-режиме

В RAG-режиме модель должна вернуть **только валидный JSON** без markdown:

```json
{
  "answer": "string",
  "sources": [
    { "source": "string", "section": "string|null", "chunk_id": "string" }
  ],
  "quotes": [
    { "chunk_id": "string", "source": "string", "section": "string|null", "text": "string" }
  ]
}
```

Правила контракта:

- `answer` не пустой.
- `sources` и `quotes` для ответа по данным RAG должны быть непустыми.
- Каждый `quotes[].chunk_id` обязан существовать в `sources[].chunk_id`.
- Дополнительные поля не допускаются.

Если модель вернула некорректный payload, приложение автоматически чинит ответ через `RAGPayloadCodec` (подставляет источники/цитаты из retrieval и формирует fallback answer).

### Как ответ отображается в UI

В чате JSON-пayload преобразуется в человекочитаемый вид:

- первая часть: `answer`;
- далее для каждой цитаты: строка источника (`источник : <path> — <section>`) и текст цитаты.

Если ответ ассистента не JSON, он показывается как есть.

## Ключевые возможности

- Чат с LLM через RouterAI-совместимый endpoint.
- Session-scoped настройки модели и генерации (модель, temperature, window size и т.д.).
- Поддержка памяти (short-term, working, long-term).
- RAG-пайплайн с индексом в SQLite и fallback-поиском.
- Пост-фильтрация RAG-чанков по порогу релевантности.
- Task-агенты в UI: Vacation Planner, Mock Task Agent, Counter Task Agent, Hacker News Task Agent.

## Технологический стек

- Swift 5
- AppKit (без SwiftUI)
- MVVM + Clean Architecture
- SQLite (`rag.sqlite`) + `sqlite-vss` (если доступен)
- Keychain для API-ключа
- MCP-клиент для discovery/call внешних инструментов

## Системные требования

- macOS 13.0+
- Xcode с поддержкой Swift 5

## Быстрый старт

### Сборка

```bash
xcodebuild -project LightNeiroClient.xcodeproj -scheme LightNeiroClient -destination 'platform=macOS' build
```

### Тесты

```bash
xcodebuild -project LightNeiroClient.xcodeproj -scheme LightNeiroClient -destination 'platform=macOS' test
```

## Настройка LLM

Клиент использует `RouterAIConfiguration` по умолчанию:

- Endpoint: `https://routerai.ru/api/v1/chat/completions`
- Таймаут: `120` секунд
- API-ключ: из Keychain (через экран настроек) или из переменной окружения `ROUTERAI_API_KEY`

При сохранении ключа в приложении используется Keychain service `StasKlem.LightNeiroClient`.

## RAG

### Документы для индексации

По умолчанию RAG индексирует:

- `LightNeiroClient/LightNeiroClient/Doc/ai.md`
- `LightNeiroClient/LightNeiroClient/Doc/habr.md`

Список задаётся в `RAGModuleFactory.defaultDocumentRelativePaths`.

### Пайплайн поиска

Если RAG включен и индекс готов:

1. Поиск кандидатов в vector store (`topK = ragTopKBeforeFiltering`, по умолчанию `8`).
2. Пороговая фильтрация (`score >= ragRelevanceThreshold`, по умолчанию `0.70`).
3. Ограничение итогового набора (`ragTopKAfterFiltering`, по умолчанию `4`).
4. Передача финальных чанков в системный контекст запроса.

Если пост-фильтрация отключена, используется legacy-режим без порога (поиск сразу с ограничением `topK = 4`).

### Параметры RAG по умолчанию

- `embeddingDimension = 1024`
- `batchSize = 150`
- `normalizeEmbeddings = true`
- `ragChunkingStrategy = structural`
- `isRAGEnabled = false`
- `isRAGPostFilteringEnabled = true`

### Где хранится индекс

- `~/Library/Application Support/LightNeiroClient/rag.sqlite`

### Логи RAG

Основные категории логов:

- `rag.embedding`
- `app.bootstrap.rag`
- `rag.vectorstore`

## Команды task-агентов в чате

### Vacation Planner

- Запуск: `/vacation start` или `/vacation`
- Остановка: `/vacation stop`

### Mock Task Agent

- Запуск: `/task start` или `/task`
- Остановка: `/task stop`

### Counter Task Agent

- Запуск: `/counter start` или `/counter`
- Запуск с интервалом: `/counter start <сек>`
- Смена интервала: `/counter interval <сек>`
- Остановка: `/counter stop`

### Hacker News Task Agent

- Запуск: `/hn start` или `/hn`
- Остановка: `/hn stop`

## MCP-интеграции

Для stdio-режима используются endpoint'ы вида `stdio://...` и автообнаружение локальных MCP-пакетов.

Поддерживаемые alias:

- `stdio://open-weather`
- `stdio://hackernews`
- `stdio://hackernews-translate`
- `stdio://hackernews-archive`

Переменные окружения для явного пути к серверу:

- `OPENWEATHER_MCP_SERVER_PATH`
- `HACKERNEWS_MCP_SERVER_PATH`
- `HACKERNEWS_TRANSLATE_MCP_SERVER_PATH`
- `HACKERNEWS_ARCHIVE_MCP_SERVER_PATH`

## Структура проекта

- `LightNeiroClient/Domain` — сущности, протоколы, use cases
- `LightNeiroClient/Data` — адаптеры (network, storage, rag, security)
- `LightNeiroClient/Presentation` — AppKit UI и ViewModel
- `LightNeiroClient/App` — bootstrap и сборка окружения
- `LightNeiroClientTests` — unit-тесты по use cases, RAG и форматированию

## Полезные документы

- [RAG-документ: ai.md](./LightNeiroClient/Doc/ai.md)
- [Доп. материал: habr.md](./LightNeiroClient/Doc/habr.md)
- [System design guide](./LightNeiroClient/Doc/mobile_system_design_guide.md)
