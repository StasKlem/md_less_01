# LightNeiroClient

[Документ для RAG: ai.md](./LightNeiroClient/Doc/ai.md)

macOS-приложение на Swift (AppKit, MVVM, Clean Architecture) с поддержкой RAG-поиска по локальным документам.

## Технологии

- Swift
- AppKit (без SwiftUI)
- SQLite (`rag.sqlite`) + опционально `sqlite-vss`
- RouterAI-совместимый endpoint для LLM/Embeddings

## RAG: как устроено сейчас

### 1. Индексация документов

- Документы берутся из `RAGModuleFactory.defaultDocumentRelativePaths`.
- На старте приложение пытается выполнить индексацию.
- Если индекс уже сохранен, стартовая индексация пропускается.

### 2. Генерация эмбеддингов

- Используется `AppLLMEmbeddingProvider`.
- Endpoint для эмбеддингов автоматически строится из `/chat/completions` в `/embeddings`.
- Эмбеддинги отправляются батчами (не по одному чанку).
- Размер батча настраивается через `RAGSettings.batchSize`.
- Значение по умолчанию: `150`.

### 3. Размерность эмбеддингов

- Текущая дефолтная размерность: `1024`.
- Валидируется:
  - соответствие числа эмбеддингов числу входных текстов;
  - единая размерность у всех векторов;
  - соответствие `settings.embeddingDimension`.

### 4. Поиск

- Основной путь: поиск через `sqlite-vss`.
- Fallback: косинусное сравнение по всем чанкам в SQLite.

## Диагностика

Логи RAG/Embeddings пишутся с категориями:

- `rag.embedding`
- `app.bootstrap.rag`
- `rag.vectorstore`

Примеры полезных сигналов:

- старт запроса эмбеддингов (`texts`, `batchSize`, `model`, `endpoint`);
- отправка/получение конкретного батча (`range=start..<end`);
- HTTP-ошибки embedding API с телом ответа;
- пропуск стартовой индексации при наличии сохраненного индекса.

## Где хранится индекс

Файл БД:

- `~/Library/Application Support/LightNeiroClient/rag.sqlite`

## Запуск сборки

```bash
xcodebuild -project LightNeiroClient.xcodeproj -scheme LightNeiroClient -destination 'platform=macOS' build
```
