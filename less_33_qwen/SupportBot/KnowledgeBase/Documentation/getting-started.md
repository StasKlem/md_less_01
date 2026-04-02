# KnowledgeBase/Documentation/getting-started.md - Начало работы

# SupportBot: Руководство по началу работы

## Установка

1. Клонируйте репозиторий:
```bash
git clone https://github.com/your-org/supportbot.git
cd supportbot/SupportBot
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
export OPENAI_API_KEY="your-api-key"
```

5. Запустите приложение:
```bash
swift run
```

## Первый запуск

При первом запуске SupportBot:
1. Создаст директорию для хранения данных
2. Проиндексирует документы из KnowledgeBase
3. Покажет приветственное сообщение

## Основные команды

- `/help` — показать справку
- `/clear` — очистить историю чата
- `/config` — показать конфигурацию
