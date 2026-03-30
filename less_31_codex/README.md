# LightNeiroClient

- [Подробная цепочка обработки пользовательского сообщения](./LightNeiroClient/LightNeiroClient/Doc/message_processing_pipeline.md)

LightNeiroClient — macOS-приложение на Swift для диалогов с LLM. Интерфейс построен на AppKit, архитектура следует MVVM и Clean Architecture, UI собран полностью кодом без SwiftUI, Storyboards и XIB.

## Что умеет приложение

- Чат с LLM через RouterAI-совместимый endpoint.
- Настройки сессии: модель, параметры генерации, окно памяти, включение RAG.
- Память диалога: short-term, working и long-term.
- RAG по локальным документам с SQLite-хранилищем и fallback-поиском.
- Task-агенты, управляемые командами в чате.
- Экран настроек, панель сессии и основной split-view интерфейс.

## Архитектура

- `LightNeiroClient/Domain` — сущности, протоколы и use case'ы.
- `LightNeiroClient/Data` — реализации репозиториев, сетевые клиенты, хранилища и RAG-адаптеры.
- `LightNeiroClient/Presentation` — AppKit UI и ViewModel.
- `LightNeiroClient/App` — bootstrap и сборка окружения приложения.

Принципы проекта:

- зависимости направлены внутрь;
- бизнес-логика живет в domain/use case слоях;
- внешние системы подключаются через абстракции;
- код UI и логика разделены.

## Требования

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

По умолчанию используется конфигурация RouterAI:

- endpoint: `https://routerai.ru/api/v1/chat/completions`
- timeout: `120` секунд
- API key: из Keychain через экран настроек или из переменной окружения `ROUTERAI_API_KEY`

При сохранении ключа используется Keychain service `StasKlem.LightNeiroClient`.

## RAG

### Источники для индексации

По умолчанию индексируются:

- `LightNeiroClient/Doc/ai.md`
- `LightNeiroClient/Doc/habr.md`

Список задается в `LightNeiroClient/Data/RAG/RAGModuleFactory.swift`.

### Пайплайн

Если RAG включен и индекс готов, приложение:

1. Ищет кандидатов в vector store.
2. При включенной пост-фильтрации отбрасывает чанки ниже порога релевантности.
3. Ограничивает финальный набор по `ragTopKAfterFiltering`.
4. Передает контекст в system prompt через блок `RAG_EVIDENCE`.

Если пост-фильтрация выключена, используется legacy-режим с прямым поиском по `topK = 4`.

### Контракт ответа

В RAG-режиме LLM должна вернуть только валидный JSON без markdown. Если payload некорректный, приложение пытается восстановить ответ через `RAGPayloadCodec`.

### Значения по умолчанию

- `embeddingDimension = 1024`
- `batchSize = 150`
- `normalizeEmbeddings = true`
- `ragChunkingStrategy = structural`
- `isRAGEnabled = false`
- `isRAGPostFilteringEnabled = true`

### Хранилище

- база индекса: `~/Library/Application Support/LightNeiroClient/rag.sqlite`
- `sqlite-vss` используется, если расширение доступно; иначе работает fallback-поиск

### Логи

Основные категории логов:

- `rag.embedding`
- `app.bootstrap.rag`
- `rag.vectorstore`

## Task-агенты

### Vacation Planner

- запуск: `/vacation start` или `/vacation`
- остановка: `/vacation stop`

### Mock Task Agent

- запуск: `/task start` или `/task`
- остановка: `/task stop`

### Counter Task Agent

- запуск: `/counter start` или `/counter`
- запуск с интервалом: `/counter start <сек>`
- изменение интервала: `/counter interval <сек>`
- остановка: `/counter stop`

### Hacker News Task Agent

- запуск: `/hn start` или `/hn`
- остановка: `/hn stop`

## MCP-интеграции

Для stdio-режима используются alias'ы вида `stdio://...` и автообнаружение локальных MCP-пакетов.

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

- `LightNeiroClient/App` — bootstrap и composition root
- `LightNeiroClient/Domain` — доменные модели, протоколы и use case'ы
- `LightNeiroClient/Data` — network/storage/rag/security адаптеры
- `LightNeiroClient/Presentation` — AppKit UI и ViewModel
- `LightNeiroClient/Doc` — локальные документы для RAG и сопроводительные материалы
- `LightNeiroClientTests` — unit-тесты для use case'ов, RAG и ViewModel

## Полезные документы

- [ai.md](./LightNeiroClient/Doc/ai.md)
- [habr.md](./LightNeiroClient/Doc/habr.md)
- [mobile_system_design_guide.md](./LightNeiroClient/Doc/mobile_system_design_guide.md)
