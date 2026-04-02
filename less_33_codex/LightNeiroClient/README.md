# LightNeiroClient

- [Подробная цепочка обработки пользовательского сообщения](./LightNeiroClient/Doc/message_processing_pipeline.md)

LightNeiroClient — macOS-приложение на Swift для диалогов с LLM. Интерфейс построен на AppKit, архитектура следует MVVM и Clean Architecture, UI собран полностью кодом без SwiftUI, Storyboards и XIB.

## `/help`

Команда `/help` запускает review-task для незакоммиченных изменений в текущем рабочем дереве.

Пайплайн task-а:

1. Получает diff и список изменённых файлов через MCP.
2. Пытается собрать RAG-контекст по локальной документации.
3. Анализирует изменения и генерирует текст ревью.
4. Если RAG или LLM недоступны, переключается на локальный fallback-разбор.

При смене состояния task-а в диалог добавляется системное сообщение. Состояния:

- `Не запущена`
- `Получение diff и изменённых файлов`
- `Работа с RAG`
- `Анализ изменений и генерация текста ревью`

## Что умеет приложение

- Чат с LLM через RouterAI-совместимый endpoint.
- Настройки сессии: backend, модель, temperature, window size, включение памяти и RAG.
- Настройки RAG: chunking strategy, post-filtering, top-K до и после фильтрации, порог релевантности.
- Редактирование инвариантов планировщика поездки прямо из UI.
- Очистка embeddings-базы из экрана настроек.
- Память диалога: short-term, working и long-term.
- RAG по локальным документам с SQLite-хранилищем и fallback-поиском.
- Сценарий Vacation Planner с анкетой, согласованием плана и поддержкой MCP-интеграции для погоды.
- Встроенные task-агенты, управляемые командами в чате.
- Экран настроек, панель session info и основной split-view интерфейс.

## Архитектура

- `LightNeiroClient/Domain` — сущности, протоколы и use case'ы.
- `LightNeiroClient/Data` — реализации репозиториев, сетевые клиенты, хранилища и RAG-адаптеры.
- `LightNeiroClient/Presentation` — AppKit UI и ViewModel.
- `LightNeiroClient/App` — bootstrap и сборка окружения приложения.
- Основной интерфейс разделен на левую чат-область и правую панель с настройками, инвариантами и session info.

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

В экране настроек можно выбрать backend:

- `RouterAI`
- `localhost`

Для `RouterAI` используется endpoint `https://routerai.ru/api/v1/chat/completions`, а API key берется из Keychain через экран настроек или из переменной окружения `ROUTERAI_API_KEY`.

Для `localhost` используется endpoint `http://localhost:1234/v1/chat/completions`, API key не требуется.

Таймаут запроса по умолчанию: `120` секунд.

При сохранении ключа используется Keychain service `StasKlem.LightNeiroClient`.

### Дефолты сессии

- `backend = RouterAI`
- `model = bytedance-seed/seed-2.0-mini`
- `temperature = 0.4`
- `windowSize = 3`
- `isRAGEnabled = true`
- `ragChunkingStrategy = structural`
- `isRAGPostFilteringEnabled = true`
- `ragTopKBeforeFiltering = 8`
- `ragTopKAfterFiltering = 4`
- `ragRelevanceThreshold = 0.70`
- `isMemoryEnabled = true`

### Доступные модели

- `bytedance-seed/seed-2.0-mini`
- `deepseek/deepseek-v3.2`
- `openai/gpt-5.4-nano`
- `google/gemma-3-4b`
- `gpt-4o-mini`
- `gpt-4o`

## RAG

### Источники для индексации

По умолчанию индексируются:

- `LightNeiroClient/Doc/ai.md`
- `LightNeiroClient/Doc/habr.md`

Список задается в `LightNeiroClient/Data/RAG/RAGModuleFactory.swift`.
При старте приложение пытается переиспользовать сохраненный индекс, а если его нет, выполняет стартовую индексацию этих документов.

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

- `provider = appLLM`
- `embeddingModel = baai/bge-m3`
- `embeddingDimension = 1024`
- `batchSize = 150`
- `normalizeEmbeddings = true`

### Хранилище

- база индекса: `~/Library/Application Support/LightNeiroClient/rag.sqlite`
- `sqlite-vss` используется, если расширение доступно; иначе работает fallback-поиск

### Логи

Основные категории логов:

- `rag.embedding`
- `app.bootstrap.rag`
- `rag.vectorstore`

## Планировщик поездки

- запуск: `/vacation start` или `/vacation`
- остановка: `/vacation stop`

Планировщик использует анкету, строит план поездки и может запрашивать погоду через MCP-интеграцию.

## Task-агенты

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

### Ассистент проекта

- запуск: `/help`
- запуск с вопросом: `/help <вопрос>`
- запускает review-task для незакоммиченных изменений
- получает diff через MCP, использует RAG и формирует текст ревью
- если RAG или LLM недоступны, использует локальный fallback-разбор без падения task-а

## MCP-интеграции

Для stdio-режима используются alias'ы вида `stdio://...` и автообнаружение локальных MCP-пакетов.
Для `stdio://project` приложение ищет `ProjectMCPServer` в текущем дереве репозитория и принимает `PROJECT_MCP_SERVER_PATH` как путь к папке пакета или к корню репозитория, внутри которого лежит `ProjectMCPServer`.

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
- `PROJECT_MCP_SERVER_PATH`

## Структура проекта

- `LightNeiroClient/App` — bootstrap и composition root
- `LightNeiroClient/Domain` — доменные модели, протоколы и use case'ы
- `LightNeiroClient/Data` — network/storage/rag/security адаптеры
- `LightNeiroClient/Presentation` — AppKit UI, ViewModel и представления правой панели
- `LightNeiroClient/Doc` — локальные документы для RAG и сопроводительные материалы
- `LightNeiroClientTests` — unit-тесты для use case'ов, RAG и ViewModel

## Полезные документы

- [ai.md](./LightNeiroClient/Doc/ai.md)
- [habr.md](./LightNeiroClient/Doc/habr.md)
- [mobile_system_design_guide.md](./LightNeiroClient/Doc/mobile_system_design_guide.md)
