# HackerNewsTranslateMCPServer

Локальный MCP сервер (`stdio`) с инструментом:

- `hackernews_translate_story`
  - Принимает `story` (строку) в формате вывода `hackernews_get_random_story`.
  - Делает LLM-перевод и возвращает переведенный текст.

## Требуемые переменные окружения

- `HACKERNEWS_TRANSLATE_OPENAI_API_KEY`

## Опциональные переменные окружения

- `HACKERNEWS_TRANSLATE_OPENAI_BASE_URL` (default `https://api.openai.com/v1`)
- `HACKERNEWS_TRANSLATE_OPENAI_MODEL` (default `gpt-4o-mini`)
- `HACKERNEWS_TRANSLATE_SYSTEM_PROMPT` (кастомный system prompt)
- `HACKERNEWS_TRANSLATE_LOG_LEVEL` (`debug|info|warn|error`, default `info`)

## Запуск

```bash
cd /Users/stasklem/project/Golang/md/less_19_codex/HackerNewsTranslateMCPServer
HACKERNEWS_TRANSLATE_OPENAI_API_KEY=your_key swift run HackerNewsTranslateMCPServer
```
