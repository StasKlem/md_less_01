# KnowledgeBase/FAQ/technical.md - Технические вопросы

## Системные требования

SupportBot работает на macOS 26.2 и выше. Требуется:
- Процессор Apple Silicon (M1+) или Intel
- Минимум 4GB RAM
- 100MB свободного места на диске

## Как обновить SupportBot?

Для обновления используйте команду:
```bash
git pull origin main
swift build
```

## Где хранятся данные?

Данные хранятся в:
- История чатов: `~/Library/Application Support/SupportBot/bot.db`
- Логи: `~/Library/Logs/SupportBot/app.log`
- База знаний: `./KnowledgeBase/`

## Как добавить свои документы в базу знаний?

Поместите Markdown-файлы в директорию `KnowledgeBase/` и перезапустите приложение. Документы будут автоматически проиндексированы.

## Поддерживается ли работа offline?

Да, при использовании локальной LLM модели (Ollama, MLX). Для OpenAI API требуется подключение к интернету.
