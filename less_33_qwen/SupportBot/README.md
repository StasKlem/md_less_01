# SupportBot — AI-ассистент для работы с файлами и RAG

Интеллектуальный CLI-ассистент для macOS с использованием RAG (Retrieval-Augmented Generation) и файловых инструментов.

## Возможности

- 🤖 **Умные ответы** — использует RAG для поиска по базе знаний
- 📚 **База знаний** — поддержка FAQ и документации в Markdown
- 💬 **Контекстная память** — помнит историю диалога
- 🎨 **TUI интерфейс** — красивый текстовый интерфейс
- ⚙️ **Гибкая конфигурация** — настройка через YAML
- 📁 **Работа с файлами** — чтение, поиск, анализ, создание файлов
- 🔬 **Анализ проекта** — статистика, структура, зависимости
- ✅ **Проверка правил** — инварианты и рекомендации

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

### Вариант 1: RouterAI API (DeepSeek)
```yaml
llm:
  provider: routerai
  api_key: ${ROUTERAI_API_KEY}
  model: deepseek/deepseek-v3.2
  base_url: https://routerai.ru/api/v1
  
embeddings:
  provider: local
  model: text-embedding-bge-m3
  base_url: http://127.0.0.1:1234/v1
```

### Вариант 2: OpenAI API
```yaml
llm:
  provider: openai
  api_key: ${OPENAI_API_KEY}
  model: gpt-4o-mini
  
embeddings:
  provider: openai
  model: text-embedding-3-small
```

### Вариант 3: Локальный API (Ollama, LM Studio, etc.)
```yaml
llm:
  provider: local
  model: local-model
  
embeddings:
  provider: local
  model: text-embedding-bge-m3
  base_url: http://127.0.0.1:1234/v1
```

Для локального API используется формат, совместимый с OpenAI API.

## Команды

### Основные
- `/help` — показать справку
- `/clear` — очистить историю чата
- `/new` — начать новую сессию
- `/index` — переиндексировать базу знаний
- `/status` — показать статус сервиса

### Работа с файлами
- `/files <path>` — прочитать файл или директорию
- `/search <pattern> [path]` — поиск по содержимому файлов
- `/list [path]` — список файлов в директории
- `/analyze` — анализ структуры проекта
- `/invariants` — проверка соответствия правилам

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
├── Config/                         # Конфигурация YAML
│   ├── config.yaml                 # Активная конфигурация
│   └── config.example.yaml         # Пример конфигурации
├── KnowledgeBase/                  # База знаний (Markdown)
├── CHANGELOG.md                    # История изменений
├── README.md                       # Документация
└── SupportBot/
    ├── App.swift                   # Точка входа + TUI компоненты
    ├── Core/                       # Сервисы приложения
    │   ├── SupportBotService.swift # Главный сервис (оркестратор)
    │   ├── ChatService.swift       # Управление чатом и сессиями
    │   ├── RAGService.swift        # RAG пайплайн (поиск + генерация)
    │   └── ContextManager.swift    # Управление контекстом диалога
    ├── Models/                     # Модели данных
    │   ├── Message.swift           # Сообщение чата
    │   ├── ChatSession.swift       # Сессия диалога
    │   ├── Document.swift          # Документ базы знаний
    │   ├── Chunk.swift             # Чанк документа
    │   ├── Embedding.swift         # Векторное представление
    │   └── FileTool.swift          # Модель инструментов
    ├── Data/                       # Работа с данными
    │   ├── ConfigManager.swift     # Загрузка и парсинг YAML
    │   ├── ChatHistoryDB.swift     # SQLite история чата
    │   ├── DocumentDB.swift        # SQLite документы
    │   ├── VectorStore.swift       # SQLite векторное хранилище
    │   ├── DocumentIndexer.swift   # Индексация Markdown файлов
    │   ├── FileService.swift       # Сервис работы с файлами
    │   └── ProjectAnalyzer.swift   # Анализатор проекта
    ├── LLM/                        # LLM провайдеры
    │   ├── LLMProvider.swift       # Протокол и конфигурация
    │   ├── OpenAIProvider.swift    # Реализация (OpenAI-совместимый API)
    │   └── PromptBuilder.swift     # Построение промптов с контекстом
    ├── Embeddings/                 # Модели эмбеддингов
    │   ├── EmbeddingModel.swift    # Протокол embedding модели
    │   ├── OpenAIEmbedding.swift   # OpenAI embedding
    │   └── LocalEmbedding.swift    # Локальная embedding модель
    ├── TUI/                        # Компоненты интерфейса
    │   └── TUIMessage.swift        # Сообщение TUI
    └── Utils/                      # Утилиты
        ├── Logger.swift            # Логирование
        └── Extensions/
            └── String+Chunks.swift # Разбиение текста на чанки
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

## Примеры использования файловых инструментов

### Сценарий 1: Поиск всех мест использования компонента
```
/search LLMProvider SupportBot/
```
Результат: найдёт все файлы с упоминанием `LLMProvider`, покажет номера строк.

### Сценарий 2: Анализ структуры проекта
```
/analyze
```
Результат: статистика файлов, дерево проекта, зависимости, рекомендации.

### Сценарий 3: Чтение файла
```
/files SupportBot/App.swift
```
Результат: содержимое файла с нумерацией строк.

### Сценарий 4: Проверка инвариантов
```
/invariants
```
Результат: проверка наличия README, CHANGELOG, .gitignore, точки входа, TODO.

### Сценарий 5: Список файлов
```
/list SupportBot/Core
```
Результат: список файлов в директории с иконками.

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
