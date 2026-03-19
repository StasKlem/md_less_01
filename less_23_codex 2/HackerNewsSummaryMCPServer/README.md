# HackerNewsSummaryMCPServer

Локальный MCP сервер (`stdio`) с инструментом:

- `hackernews_summarize_stories`
  - Принимает `stories` (массив строк) в формате вывода `hackernews_get_random_story`.
  - Делает LLM-суммаризацию и возвращает готовый текст.

## Требуемые переменные окружения

- `HACKERNEWS_SUMMARY_OPENAI_API_KEY`

## Опциональные переменные окружения

- `HACKERNEWS_SUMMARY_OPENAI_BASE_URL` (default `https://api.openai.com/v1`)
- `HACKERNEWS_SUMMARY_OPENAI_MODEL` (default `gpt-4o-mini`)
- `HACKERNEWS_SUMMARY_SYSTEM_PROMPT` (кастомный system prompt)
- `HACKERNEWS_SUMMARY_LOG_LEVEL` (`debug|info|warn|error`, default `info`)

## Запуск

```bash
cd /Users/stasklem/project/Golang/md/less_19_codex/HackerNewsSummaryMCPServer
HACKERNEWS_SUMMARY_OPENAI_API_KEY=your_key swift run HackerNewsSummaryMCPServer
```
