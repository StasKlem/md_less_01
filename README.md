# Go Chat CLI

Консольное приложение на Golang для взаимодействия с API chatGPT через RouterAI.

## Установка

1. Клонируйте репозиторий:
```bash
git clone <repo-url>
cd Golang/md
```

2. Убедитесь, что у вас установлен Go.

## Настройка

Создайте файл `.env` или экспортируйте переменную окружения с API ключом:

```bash
export ROUTERAI_API_KEY="your-api-key"
```

## Запуск

```bash
go run main.go
```

## Использование

1. Запустите приложение
2. Введите сообщение
3. Нажмите Enter для отправки
4. Получите ответ от AI

## Пример работы

```
Введите сообщение: Привет!
→ Request:
{
  "model": "deepseek/deepseek-v3.2",
  "messages": [
    {
      "role": "user",
      "content": "Привет!"
    }
  ]
}
← Response time: 1.234s, status: 200
← Response:
{
  "id": "...",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Привет! Как я могу вам помочь?"
      }
    }
  ]
}
→ Answer: Привет! Как я могу вам помочь?
```

## Требования

- Go 1.18+
- API ключ RouterAI
