# KBJU Bot - Telegram бот для подсчета КБЖУ

Профессиональный Telegram бот на Go для учета калорий, белков, жиров и углеводов. Поддерживает текстовые и голосовые сообщения с интеграцией LLM для распознавания речи и анализа питания.

## Возможности

- 📝 **Текстовые сообщения** - отправьте описание еды, бот посчитает КБЖУ
- 🎤 **Голосовые сообщения** - бот распознает речь и определит КБЖУ
- 📊 **Статистика** - просмотр дневной и недельной статистики
- ⏰ **Ежедневные отчеты** - автоматическая отправка сводки в конце дня
- 🔐 **Контроль доступа** - режимы whitelist и public
- 🐳 **Docker** - готов к развертыванию в контейнерах

## Архитектура

Проект построен на принципах Clean Architecture:

```
cmd/bot/main.go           # Точка входа
internal/
├── bot/handlers.go      # Обработчики Telegram
├── config/config.go     # Конфигурация (viper)
├── llm/client.go       # Интеграция с LLM
├── repository/sqlite/   # Слой доступа к данным
└── services/            # Бизнес-логика
pkg/logger/             # Логирование
```

## Требования

- Go 1.21+
- Telegram бот (получить у @BotFather)
- LLM API ключ (routerai.ru)

## Быстрый старт

### 1. Клонирование и настройка

```bash
git clone <repository-url>
cd kbju-bot
cp .env.example .env
```

### 2. Настройка переменных окружения

Отредактируйте `.env` файл:

```env
# Обязательные параметры
BOT_TOKEN=your_telegram_bot_token
LLM_API_KEY=your_routerai_api_key

# Опционально (значения по умолчанию)
DB_PATH=./data/kbju.db
LLM_BASE_URL=https://routerai.ru/api/v1
LLM_MODEL=deepseek/deepseek-v3.2
ACCESS_MODE=public
LOG_LEVEL=info
LOG_FORMAT=json
```

### 3. Запуск

#### Локально
```bash
go run ./cmd/bot
# или через make
make run
```

#### Docker
```bash
make docker-build
make docker-run
```

### 4. Использование бота

Отправьте боту команды:

| Команда | Описание |
|---------|----------|
| `/start` | Регистрация в боте |
| `/help` | Справка |
| `/stats` | Статистика за сегодня |
| `/week_stats` | Статистика за неделю |
| `/reset_day` | Сбросить дневную статистику |

Примеры сообщений:
- `съел 200г куриной грудки`
- `яблоко 150 грамм`
- `бутерброд с сыром`

## Конфигурация

### Параметры доступа

```env
# Режим доступа: public или whitelist
ACCESS_MODE=whitelist

# Список разрешенных ID пользователей (через запятую)
ALLOWED_USER_IDS=123456789,987654321
```

### Параметры LLM

```env
LLM_API_KEY=your_api_key
LLM_BASE_URL=https://routerai.ru/api/v1
LLM_MODEL=deepseek/deepseek-v3.2
LLM_TIMEOUT_SECONDS=60
```

### Параметры базы данных

```env
DB_PATH=./data/kbju.db
DB_WAL_MODE=true
```

### Параметры планировщика

```env
SCHEDULER_REPORT_TIME=21:00
SCHEDULER_REPORT_TICKER_MINUTES=60
```

## Структура базы данных

### Таблица users
| Поле | Тип | Описание |
|------|-----|----------|
| id | int64 | ID пользователя Telegram |
| username | string | Username |
| first_name | string | Имя |
| last_name | string | Фамилия |
| is_active | bool | Активен |

### Таблица daily_records
| Поле | Тип | Описание |
|------|-----|----------|
| id | int64 | ID записи |
| user_id | int64 | ID пользователя |
| date | date | Дата |
| calories | float64 | Калории |
| proteins | float64 | Белки |
| fats | float64 | Жиры |
| carbs | float64 | Углеводы |

### Таблица message_logs
| Поле | Тип | Описание |
|------|-----|----------|
| id | int64 | ID записи |
| user_id | int64 | ID пользователя |
| type | string | Тип (text/audio) |
| content | string | Содержание |
| kbju_data | text | JSON данные КБЖУ |
| raw_llm_resp | text | Ответ LLM |

## Docker

### Сборка образа

```bash
docker build -t kbju-bot:latest .
```

### Запуск с docker-compose

```bash
docker-compose up -d
```

### Просмотр логов

```bash
docker-compose logs -f
```

### Остановка

```bash
docker-compose down
```

## Makefile

| Команда | Описание |
|---------|----------|
| `make build` | Собрать бинарник |
| `make run` | Запустить локально |
| `make test` | Запустить тесты |
| `make lint` | Запустить линтер |
| `make docker-build` | Собрать Docker образ |
| `make docker-run` | Запустить в Docker |
| `make docker-stop` | Остановить контейнер |

## Расширение

### Добавление новой команды

1. Добавьте новый хендлер в `internal/bot/handlers.go`:

```go
func (h *BotHandler) HandleNewCommand(ctx context.Context, b *tgbot.Bot, update *models.Update) {
    // Ваша логика
}
```

2. Зарегистрируйте в `cmd/bot/main.go`:

```go
tb.RegisterHandlerMatchFunc(
    func(update *models.Update) bool {
        return update.Message != nil && update.Message.Text == "/newcommand"
    },
    botHandler.HandleNewCommand,
)
```

### Замена базы данных

Для перехода на PostgreSQL:

1. Замените драйвер в `go.mod`:
```go
gorm.io/driver/postgres
```

2. Обновите `internal/repository/sqlite/repository.go`:
```go
import "gorm.io/driver/postgres"

dsn := "host=user port=5432 dbname=kbju user=postgres password=secret"
db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
```

## Безопасность

- Токены и API ключи хранятся только в переменных окружения
- Все ошибки обрабатываются без panic
- Graceful shutdown при получении сигналов SIGINT/SIGTERM
- Валидация входных данных от LLM

## Лицензия

MIT
