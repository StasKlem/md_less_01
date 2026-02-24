# KBJU Bot — Telegram бот для учёта калорий и КБЖУ

[![Go Version](https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat&logo=go)](https://golang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?style=flat&logo=docker)](https://www.docker.com/)

Профессиональный Telegram бот для отслеживания потребления калорий, белков, жиров и углеводов (КБЖУ) с использованием искусственного интеллекта для анализа текста и распознавания голосовых сообщений.

## 📖 Оглавление

- [Возможности](#-возможности)
- [Архитектура](#-архитектура)
- [Структура проекта](#-структура-проекта)
- [Быстрый старт](#-быстрый-старт)
- [Настройка](#-настройка)
- [Контроль доступа](#-контроль-доступа)
- [Команды бота](#-команды-бота)
- [База данных](#-база-данных)
- [Масштабирование](#-масштабирование)
- [Разработка](#-разработка)
- [Деплой](#-деплой)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)

---

## ✨ Возможности

### Основные функции

| Функция | Описание |
|---------|----------|
| 📝 **Текстовый ввод** | Анализ описания еды через LLM |
| 🎤 **Голосовые сообщения** | Распознавание речи через Whisper API |
| 📊 **Ежедневная статистика** | Подсчёт суммарных КБЖУ за день |
| 📈 **Авто-отчёты** | Ежедневные отчёты в заданное время |
| 💡 **Рекомендации** | Советы по балансу питания |
| 🔒 **Контроль доступа** | Whitelist или публичный режим |

### Технические особенности

- **Clean Architecture** — разделение на слои (Handlers → UseCases → Repositories)
- **12-Factor App** — конфигурация через ENV переменные
- **Graceful Shutdown** — корректное завершение работы с сохранением данных
- **Structured Logging** — логирование через `slog` с уровнями
- **Unit Tests** — тесты для бизнес-логики с моками
- **Docker Ready** — multi-stage сборка, non-root пользователь

---

## 🏗 Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                   Presentation Layer                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Handlers  │  │ Middleware  │  │    Scheduler        │  │
│  │  (commands) │  │  (access)   │  │   (daily reports)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Business Layer                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  KBJUService                            ││
│  │  • ProcessTextMessage  • ProcessVoiceMessage            ││
│  │  • GetDailyStats       • ResetDay                       ││
│  │  • GenerateReport      • generateRecommendations        ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     Data Layer                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   User      │  │  DailyRec   │  │   MessageLog        │  │
│  │ Repository  │  │ Repository  │  │   Repository        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   SQLite    │  │  LLM Client │  │   Telegram Bot      │  │
│  │   (gorm)    │  │  (OpenAI)   │  │     (telebot)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Поток данных

1. **Пользователь** отправляет сообщение → **Telegram API**
2. **Middleware** проверяет доступ (whitelist/public)
3. **Handler** принимает сообщение → передаёт в **KBJUService**
4. **KBJUService**:
   - Создаёт/обновляет пользователя
   - Отправляет текст/аудио в **LLM Provider**
   - Получает JSON с КБЖУ
   - Сохраняет в **SQLite** через **Repository**
   - Логирует в **MessageLog**
5. **Ответ** возвращается пользователю

---

## 📁 Структура проекта

```
kbju-bot/
├── cmd/
│   └── bot/
│       └── main.go              # Точка входа, DI, graceful shutdown
├── internal/
│   ├── bot/                     # Telegram bot слой
│   │   ├── handlers.go          # Обработчики команд и сообщений
│   │   └── scheduler.go         # Планировщик ежедневных отчётов
│   ├── config/                  # Конфигурация
│   │   ├── config.go            # Структуры и загрузка из ENV
│   │   └── config_test.go       # Тесты конфигурации
│   ├── domain/                  # Бизнес-модели
│   │   └── models.go            # User, DailyRecord, MessageLog, KBJUResult
│   ├── llm/                     # LLM провайдер
│   │   └── client.go            # Интерфейс и OpenAI клиент
│   ├── logger/                  # Логирование
│   │   └── logger.go            # Structured logger на slog
│   ├── repository/              # Репозитории
│   │   ├── repository.go        # Интерфейсы
│   │   └── sqlite/              # SQLite реализация
│   │       ├── db.go            # Подключение, миграции, WAL
│   │       ├── user_repository.go
│   │       ├── daily_record_repository.go
│   │       └── message_log_repository.go
│   └── services/                # Бизнес-логика
│       ├── kbju_service.go      # Основная логика
│       └── kbju_service_test.go # Unit тесты
├── tests/
│   └── mocks/                   # Mock реализации
│       └── repository_mock.go
├── Dockerfile                   # Multi-stage Docker build
├── docker-compose.yml           # Docker Compose с volume
├── Makefile                     # Build automation
├── .env.example                 # Шаблон ENV переменных
├── .gitignore                   # Git ignore правила
├── go.mod                       # Go модуль
├── go.sum                       # Зависимости
└── README.md                    # Документация
```

---

## 🚀 Быстрый старт

### 1. Требования

| Зависимость | Версия | Назначение |
|-------------|--------|------------|
| Go | 1.24+ | Компиляция |
| Docker | 20.10+ | Контейнеризация |
| Docker Compose | 2.0+ | Оркестрация |
| Telegram Bot Token | — | Доступ к Bot API |
| LLM API Key | — | OpenAI или совместимый |

### 2. Получение токенов

#### Telegram Bot Token
1. Откройте [@BotFather](https://t.me/BotFather)
2. Отправьте `/newbot`
3. Следуйте инструкциям
4. Скопируйте токен (выглядит как `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

#### LLM API Key (OpenAI)
1. Зарегистрируйтесь на [platform.openai.com](https://platform.openai.com)
2. Перейдите в **API Keys**
3. Создайте новый ключ
4. Скопируйте ключ (начинается с `sk-`)

### 3. Установка и запуск

```bash
# Клонирование репозитория
git clone <repository-url>
cd kbju-bot

# Копирование конфигурации
cp .env.example .env

# Редактирование .env (укажите ваши токены)
nano .env  # или любой редактор

# Запуск через Docker Compose
docker-compose up -d --build

# Просмотр логов
docker-compose logs -f

# Остановка
docker-compose down
```

### 4. Локальная разработка

```bash
# Установка зависимостей
go mod download

# Запуск в режиме разработки
go run ./cmd/bot

# Сборка
go build -o bin/kbju-bot ./cmd/bot

# Запуск тестов
go test -v ./...

# Запуск с покрытием
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

---

## ⚙️ Настройка

### Переменные окружения

Создайте файл `.env` на основе `.env.example`:

```bash
cp .env.example .env
```

#### Обязательные переменные

| Переменная | Описание | Пример |
|------------|----------|--------|
| `TELEGRAM_BOT_TOKEN` | Токен Telegram бота | `123456789:ABCdef...` |
| `LLM_API_KEY` | Ключ LLM API | `sk-abc123...` |

#### Telegram настройки

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `TELEGRAM_TIMEOUT` | `30s` | Таймаут запросов к Telegram |

#### LLM настройки

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `LLM_PROVIDER` | `openai` | Провайдер (openai, anthropic) |
| `LLM_MODEL` | `deepseek/deepseek-v3.2` | Модель для запросов |
| `LLM_BASE_URL` | `https://routerai.ru/api/v1` | Базовый URL API |
| `LLM_TIMEOUT` | `60s` | Таймаут запросов к LLM |

#### Пример настройки для routerai.ru

```env
LLM_API_KEY=your_routerai_api_key
LLM_MODEL=deepseek/deepseek-v3.2
LLM_BASE_URL=https://routerai.ru/api/v1
```

#### Пример настройки для OpenAI

```env
LLM_API_KEY=sk-your-openai-key
LLM_MODEL=gpt-4o-mini
LLM_BASE_URL=https://api.openai.com/v1
```

#### База данных

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `DATABASE_PATH` | `./data/kbju.db` | Путь к SQLite файлу |
| `DATABASE_MAX_OPEN_CONNS` | `1` | Макс. открытых соединений |
| `DATABASE_MAX_IDLE_CONNS` | `1` | Макс. простых соединений |
| `DATABASE_CONN_MAX_LIFETIME` | `5m` | Время жизни соединения |

#### Отчёты

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `REPORT_SEND_TIME` | `21:00` | Время отчёта (HH:MM) |
| `REPORT_TIMEZONE` | `Europe/Moscow` | Часовой пояс |

#### Логирование

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `LOG_LEVEL` | `info` | debug, info, warn, error |
| `LOG_FORMAT` | `text` | text или json |

---

## 🔒 Контроль доступа

Бот поддерживает два режима контроля доступа.

### Public режим (доступ всем)

Любой пользователь может использовать бота:

```env
ACCESS_CONTROL_MODE=public
```

### Whitelist режим (ограниченный доступ)

Доступ разрешён только указанным пользователям:

```env
ACCESS_CONTROL_MODE=whitelist
ACCESS_CONTROL_ALLOWED_USER_IDS=123456789,987654321,555666777
```

#### Как узнать Telegram ID

1. Отправьте сообщение боту [@userinfobot](https://t.me/userinfobot)
2. Или используйте [@RawDataBot](https://t.me/RawDataBot)
3. Скопируйте числовой ID из ответа

#### Пример настройки whitelist

```env
ACCESS_CONTROL_MODE=whitelist
ACCESS_CONTROL_ALLOWED_USER_IDS=123456789,987654321
```

В этом режиме:
- ✅ Пользователи из списка имеют полный доступ
- ❌ Остальные получают сообщение «Доступ запрещен»

---

## 📟 Команды бота

| Команда | Описание | Пример ответа |
|---------|----------|---------------|
| `/start` | Начало работы, приветствие | 👋 Привет, @user! Я бот для учёта КБЖУ... |
| `/help` | Справка по использованию | 📖 Справка по боту КБЖУ... |
| `/stats` | Статистика за сегодня | 📊 Статистика за сегодня: 🔥 2500 ккал... |
| `/reset_day` | Сброс записей за сегодня | ✅ Все записи за сегодня удалены |

### Обработка сообщений

#### Текстовое сообщение

```
Овсянка с молоком и бананом, 200г
```

**Ответ:**
```
🍽️ Овсянка с молоком и бананом

🔥 Калории: 350 ккал
🥩 Белки: 12.5 г
🥑 Жиры: 8.2 г
🍞 Углеводы: 55.0 г

✅ Запись сохранена!
```

#### Голосовое сообщение

Отправьте голосовое: _«На завтрак съел бутерброд с колбасой и кофе»_

**Ответ:**
```
🎤 Распознано: Бутерброд с колбасой и кофе

🔥 Калории: 280 ккал
🥩 Белки: 10.0 г
🥑 Жиры: 15.0 г
🍞 Углеводы: 25.0 г

✅ Запись сохранена!
```

#### Ежедневный отчёт

Отправляется автоматически в заданное время:

```
📊 Отчет за 23.02.2024

🔥 Калории: 2200 ккал
🥩 Белки: 120.0 г
🥑 Жиры: 70.0 г
🍞 Углеводы: 280.0 г

📝 Записей: 5

✅ Хороший баланс! Продолжайте в том же духе.
```

---

## 🗄 База данных

### Схема БД

```sql
-- Пользователи
CREATE TABLE users (
    id INTEGER PRIMARY KEY,          -- Telegram ID
    username TEXT,
    first_name TEXT,
    last_name TEXT,
    created_at DATETIME,
    updated_at DATETIME
);

-- Ежедневные записи КБЖУ
CREATE TABLE daily_records (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,                 -- Ссылка на users.id
    date DATE,                       -- Дата записи
    calories INTEGER,                -- Калории
    proteins REAL,                   -- Белки (г)
    fats REAL,                       -- Жиры (г)
    carbs REAL,                      -- Углеводы (г)
    food_name TEXT,                  -- Название блюда
    raw_message TEXT,                -- Исходное сообщение
    created_at DATETIME,
    updated_at DATETIME,
    INDEX idx_user_date (user_id, date)
);

-- Логи сообщений
CREATE TABLE message_logs (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,                 -- Ссылка на users.id
    message_type TEXT,               -- text, voice, audio
    content TEXT,                    -- Содержание
    llm_response TEXT,               -- Ответ LLM
    error TEXT,                      -- Ошибка (если была)
    created_at DATETIME
);
```

### SQLite оптимизации

Проект использует SQLite с настройками для конкурентной работы:

```go
// WAL режим для лучшей производительности
_journal_mode=WAL

// Таймаут ожидания блокировки (5 секунд)
_busy_timeout=5000

// Внешние ключи
_foreign_keys=ON

// Ограничение пула соединений
SetMaxOpenConns(1)   // SQLite лучше работает с 1 соединением на запись
SetMaxIdleConns(1)
```

### Почему gorm?

| Преимущество | Описание |
|--------------|----------|
| **Автоматические миграции** | `AutoMigrate()` создаёт таблицы |
| **Абстракция SQL** | Легкая смена БД в будущем |
| **Транзакции** | Встроенная поддержка `Transaction()` |
| **Безопасность** | Защита от SQL injection |

---

## 📈 Масштабирование

### Переход на PostgreSQL

При росте нагрузки (≥10K записей/день) рекомендуется перейти на PostgreSQL.

#### 1. Создание PostgreSQL репозитория

```bash
mkdir -p internal/repository/postgres
```

#### 2. Конфигурация PostgreSQL

Добавьте в `internal/config/config.go`:

```go
type PostgresConfig struct {
    Host            string        `mapstructure:"host"`
    Port            int           `mapstructure:"port"`
    User            string        `mapstructure:"user"`
    Password        string        `mapstructure:"password"`
    DBName          string        `mapstructure:"dbname"`
    SSLMode         string        `mapstructure:"sslmode"`
    MaxOpenConns    int           `mapstructure:"max_open_conns"`
    MaxIdleConns    int           `mapstructure:"max_idle_conns"`
    ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
}
```

#### 3. Подключение PostgreSQL

```go
// internal/repository/postgres/db.go
import "gorm.io/driver/postgres"

func New(cfg config.PostgresConfig) (*DB, error) {
    dsn := fmt.Sprintf(
        "host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
        cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode,
    )
    
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    // ...
}
```

#### 4. Выбор БД в main.go

```go
var db *sqlite.DB
dbType := os.Getenv("DB_TYPE")

switch dbType {
case "postgres":
    db, err = postgres.New(cfg.Postgres)
default:
    db, err = sqlite.New(cfg.Database)
}
```

#### 5. Docker Compose для PostgreSQL

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: kbju
      POSTGRES_USER: kbju_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kbju_user"]
      interval: 10s
      timeout: 5s
      retries: 5

  kbju-bot:
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - DB_TYPE=postgres
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      # ...

volumes:
  postgres-data:
```

### Сравнение SQLite и PostgreSQL

| Характеристика | SQLite | PostgreSQL |
|----------------|--------|------------|
| **Макс. записей/день** | ~10K | ~1M+ |
| **Конкурентная запись** | Ограничена | Полная |
| **Репликация** | Нет | Да |
| **Шардирование** | Нет | Да |
| **Сложность деплоя** | Низкая | Средняя |

---

## 👨‍💻 Разработка

### Makefile команды

| Команда | Описание |
|---------|----------|
| `make build` | Сборка бинарного файла |
| `make run` | Сборка и запуск |
| `make run-dev` | Запуск в режиме разработки (`go run`) |
| `make test` | Запуск всех тестов |
| `make test-coverage` | Тесты с отчётом о покрытии |
| `make clean` | Очистка артефактов |
| `make lint` | Запуск линтера (golangci-lint) |
| `make fmt` | Форматирование кода |
| `make migrate` | Запуск миграций БД |
| `make docker-build` | Сборка Docker образа |
| `make docker-run` | Запуск контейнера |
| `make docker-stop` | Остановка контейнера |
| `make docker-restart` | Пересборка и перезапуск |
| `make docker-logs` | Просмотр логов |
| `make mocks` | Генерация mock'ов |
| `make deps` | Установка зависимостей |
| `make help` | Справка по командам |

### Запуск тестов

```bash
# Все тесты
go test -v ./...

# С покрытием
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Конкретный пакет
go test -v ./internal/services

# Конкретный тест
go test -v ./internal/services -run TestKBJUService_ProcessTextMessage
```

### Генерация mock'ов

```bash
# Установка mockgen
go install github.com/golang/mock/mockgen@latest

# Генерация
make mocks
```

### Code Style

Проект следует [Google Go Style Guide](https://google.github.io/styleguide/go/):

- Имена переменных: `camelCase` для локальных, `PascalCase` для экспортируемых
- Обработка ошибок: ошибки оборачиваются с контекстом
- Комментарии: только для экспортируемых функций
- Форматирование: `go fmt` обязательно

---

## 🚢 Деплой

### Docker Compose (Production)

```bash
# Сборка
docker-compose -f docker-compose.yml build

# Запуск
docker-compose -f docker-compose.yml up -d

# Проверка статуса
docker-compose ps

# Логи
docker-compose logs -f kbju-bot
```

### Переменные для production

```env
# .env.production
TELEGRAM_BOT_TOKEN=your_production_token
LLM_API_KEY=your_production_key
ACCESS_CONTROL_MODE=whitelist
ACCESS_CONTROL_ALLOWED_USER_IDS=123456789
LOG_LEVEL=warn
LOG_FORMAT=json
REPORT_SEND_TIME=21:00
REPORT_TIMEZONE=Europe/Moscow
```

### Backup базы данных

```bash
# Копирование файла БД из контейнера
docker cp kbju-bot:/app/data/kbju.db ./backup/kbju-$(date +%Y%m%d).db

# Автоматический backup (cron)
0 2 * * * docker cp kbju-bot:/app/data/kbju.db /backups/kbju-$(date +\%Y\%m\%d).db
```

### Обновление

```bash
# Pull новых изменений
git pull

# Пересборка и перезапуск
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

## 🔧 Troubleshooting

### Бот не запускается

**Проблема:** `Failed to load config: telegram.bot_token is required`

**Решение:** Проверьте `.env` файл:
```bash
cat .env | grep TELEGRAM_BOT_TOKEN
```

### Ошибки LLM

**Проблема:** `LLM API error: invalid_api_key`

**Решение:**
1. Проверьте ключ в `.env`
2. Убедитесь, что есть баланс на счёте OpenAI
3. Проверьте доступность API:
```bash
curl -H "Authorization: Bearer $LLM_API_KEY" https://api.openai.com/v1/models
```

### SQLite блокировки

**Проблема:** `database is locked`

**Решение:**
1. Убедитесь, что `DATABASE_MAX_OPEN_CONNS=1`
2. Проверьте, нет ли других процессов с БД
3. Удалите WAL файлы при остановке:
```bash
rm ./data/kbju.db-wal ./data/kbju.db-shm
```

### Пользователь заблокировал бота

Бот автоматически игнорирует ошибку 403 (пользователь заблокировал бота) при отправке отчёта.

---

## ❓ FAQ

### Как изменить время отправки отчёта?

```env
REPORT_SEND_TIME=09:00  # 9 утра
```

### Как сменить часовой пояс?

```env
REPORT_TIMEZONE=Asia/Yekaterinburg
```

Список поясов: [Time Zone Database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)

### Можно ли использовать локальную LLM?

Да, укажите кастомный URL:

```env
LLM_BASE_URL=http://localhost:11434/v1
LLM_MODEL=llama2
```

### Как сбросить все данные пользователя?

Удалите запись из БД:
```sql
DELETE FROM daily_records WHERE user_id = 123456789;
DELETE FROM message_logs WHERE user_id = 123456789;
```

### Бот отвечает медленно

1. Проверьте скорость интернета
2. Уменьшите `LLM_TIMEOUT`
3. Используйте более быструю модель (`gpt-3.5-turbo`)

---

## 📄 Лицензия

MIT License — см. файл [LICENSE](LICENSE)

## 🤝 Вклад

Pull Request приветствуются! Для крупных изменений откройте Issue для обсуждения.

## 📞 Контакты

- **Issues:** [GitHub Issues](../../issues)
- **Email:** your.email@example.com

---

<div align="center">

**KBJU Bot** — следите за питанием с умом! 🍎

[![Go](https://img.shields.io/badge/Made%20with-Go-00ADD8?style=flat&logo=go)](https://golang.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Bot-26A5E4?style=flat&logo=telegram)](https://telegram.org/)

</div>
