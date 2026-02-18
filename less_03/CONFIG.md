# Конфигурация LLM Chat Client

## Файл конфигурации

Приложение поддерживает загрузку конфигурации из JSON файла.

### Расположение файла

Файл конфигурации ищется в следующем порядке:
1. Путь, указанный во флаге `-config`
2. Переменная окружения `LLM_CLIENT_CONFIG`
3. `~/.llm-client/config.json`
4. `config.json` в текущей директории

### Пример конфигурации

```json
{
  "server": {
    "address": "http://localhost:11434",
    "api_endpoint": "/v1/chat/completions",
    "use_ollama": false
  },
  "model": {
    "name": "llama3",
    "system_prompt": "You are a helpful assistant.",
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 0
  },
  "ui": {
    "show_timestamps": false,
    "theme": "dark",
    "scroll_speed": 10
  },
  "log": {
    "enabled": true,
    "file_path": "/tmp/llm-client.log",
    "level": "info",
    "log_requests": true,
    "log_responses": true,
    "log_stream_chunks": false
  }
}
```

## Описание параметров

### Server (сервер)

| Параметр | Тип | Описание | По умолчанию |
|----------|-----|----------|--------------|
| `address` | string | Адрес LLM сервера | `http://localhost:11434` |
| `api_endpoint` | string | Эндпоинт API | `/v1/chat/completions` |
| `use_ollama` | bool | Использовать Ollama API | `false` |

### Model (модель)

| Параметр | Тип | Описание | Диапазон |
|----------|-----|----------|----------|
| `name` | string | Имя модели | - |
| `system_prompt` | string | Системный промпт | - |
| `temperature` | float | Температура генерации | 0.0-2.0 |
| `top_p` | float | Параметр top_p | 0.0-1.0 |
| `max_tokens` | int | Макс. токенов в ответе | 0 = без ограничений |

### UI (интерфейс)

| Параметр | Тип | Описание |
|----------|-----|----------|
| `show_timestamps` | bool | Показывать время в логах |
| `theme` | string | Тема: `light` или `dark` |
| `scroll_speed` | int | Скорость скролла |

### Log (логирование)

| Параметр | Тип | Описание |
|----------|-----|----------|
| `enabled` | bool | Включить логирование |
| `file_path` | string | Путь к файлу логов |
| `level` | string | Уровень: `debug`, `info`, `warn`, `error` |
| `log_requests` | bool | Логировать HTTP запросы |
| `log_responses` | bool | Логировать HTTP ответы |
| `log_stream_chunks` | bool | Логировать чанки стрима |

## Переменные окружения

| Переменная | Описание |
|------------|----------|
| `ROUTERAI_API_KEY` | API ключ для аутентификации |
| `LLM_CLIENT_CONFIG` | Путь к файлу конфигурации |
| `LLM_CLIENT_LOG` | Путь к файлу логов (переопределяет config) |

## Флаги командной строки

| Флаг | Описание |
|------|----------|
| `-config <path>` | Путь к файлу конфигурации |
| `-address <url>` | Адрес сервера (переопределяет config) |
| `-model <name>` | Имя модели (переопределяет config) |
| `-system <text>` | Системный промпт (переопределяет config) |
| `-temperature <float>` | Температура (переопределяет config) |
| `-top-p <float>` | Top P параметр (переопределяет config) |
| `-show-config` | Показать конфигурацию по умолчанию |
| `-init-config` | Создать файл конфигурации по умолчанию |

## Примеры использования

### Запуск с файлом конфигурации

```bash
./llm-client -config /path/to/config.json
```

### Запуск с переменной окружения

```bash
export LLM_CLIENT_CONFIG=~/.llm-client/config.json
./llm-client
```

### Создание конфигурации по умолчанию

```bash
./llm-client -init-config
```

### Показать конфигурацию по умолчанию

```bash
./llm-client -show-config
```

### Переопределение параметров из CLI

```bash
./llm-client \
  -config config.json \
  -address http://localhost:11434 \
  -model mistral \
  -temperature 0.8
```

### Логирование через переменную окружения

```bash
export LLM_CLIENT_LOG=/tmp/llm-client.log
./llm-client
```

## Команды в чате

| Команда | Описание |
|---------|----------|
| `/set <param> <value>` | Изменить параметр |
| `/clear` | Очистить историю |
| `/config` | Показать текущие настройки |
| `/save` | Сохранить настройки в config.json |
| `/help` | Показать справку |
| `/exit` | Выйти |

### Примеры команд

```
/set temperature 0.9
/set model llama3
/set system You are a coding assistant.
/save
```
