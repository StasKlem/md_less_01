# SupportBot — Ассистент поддержки с RAG

Интеллектуальный CLI-ассистент поддержки для macOS с использованием RAG (Retrieval-Augmented Generation).

## Возможности

- 🤖 **Умные ответы** — использует RAG для поиска по базе знаний
- 📚 **База знаний** — поддержка FAQ и документации в Markdown
- 💬 **Контекстная память** — помнит историю диалога
- 🎨 **TUI интерфейс** — красивый текстовый интерфейс
- ⚙️ **Гибкая конфигурация** — настройка через YAML

## Требования

- macOS 26.2+
- Xcode 26.2+
- Swift 6.2+
- API ключ OpenAI (или локальная LLM)

## Установка

1. Клонируйте репозиторий:
```bash
cd SupportBot
```

2. Установите зависимости:
```bash
swift package resolve
```

3. Настройте конфигурацию:
```bash
cp Config/config.example.yaml Config/config.yaml
```

4. Установите API ключ OpenAI:
```bash
export OPENAI_API_KEY="sk-your-api-key"
```

5. Запустите приложение:
```bash
swift run
```

## Конфигурация

Откройте `Config/config.yaml` и настройте параметры:

```yaml
llm:
  provider: openai
  api_key: ${OPENAI_API_KEY}
  model: gpt-4o-mini
  
embeddings:
  provider: openai
  model: text-embedding-3-small

rag:
  chunk_size: 500
  chunk_overlap: 50
  top_k: 5
  min_score: 0.7
```

## Команды

- `/help` — показать справку
- `/clear` — очистить историю чата
- `/new` — начать новую сессию
- `/index` — переиндексировать базу знаний
- `/status` — показать статус сервиса

## Добавление документов

Поместите Markdown-файлы в директорию `KnowledgeBase/`:

```
KnowledgeBase/
├── FAQ/
│   ├── general.md
│   └── technical.md
└── Documentation/
    ├── getting-started.md
    └── features.md
```

При запуске документы автоматически индексируются.

## Архитектура

```
SupportBot/
├── Config/                 # Конфигурация YAML
├── KnowledgeBase/          # База знаний (Markdown)
└── SupportBot/
    ├── Core/               # Сервисы приложения
    │   ├── SupportBotService.swift
    │   ├── ChatService.swift
    │   ├── RAGService.swift
    │   └── ContextManager.swift
    ├── Models/             # Модели данных
    ├── Data/               # Работа с данными
    │   ├── ConfigManager.swift
    │   ├── ChatHistoryDB.swift
    │   ├── DocumentDB.swift
    │   ├── VectorStore.swift
    │   └── DocumentIndexer.swift
    ├── LLM/                # LLM провайдеры
    │   ├── LLMProvider.swift
    │   ├── OpenAIProvider.swift
    │   └── PromptBuilder.swift
    ├── Embeddings/         # Модели эмбеддингов
    └── TUI/                # Компоненты интерфейса
```

## RAG Пайплайн

1. **Индексация**:
   - Загрузка документов из KnowledgeBase
   - Разбиение на чанки (chunking)
   - Создание эмбеддингов (OpenAI API)
   - Сохранение в VectorStore

2. **Поиск и генерация**:
   - Получение запроса пользователя
   - Создание эмбеддинга запроса
   - Поиск релевантных чанков (косинусное сходство)
   - Построение промпта с контекстом
   - Генерация ответа через LLM

## Технологии

- **TUI**: [TauTUI](https://github.com/steipete/TauTUI)
- **HTTP**: AsyncHTTPClient
- **БД**: SQLite.swift
- **YAML**: Yams
- **Логирование**: swift-log
- **LLM**: OpenAI API (GPT-4o-mini)
- **Embeddings**: OpenAI API (text-embedding-3-small)

## Лицензия

MIT
