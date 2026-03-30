# HackerNewsMCPServer

Простой MCP сервер для получения случайной новости из Hacker News API (`swift-mcp-sdk`, transport `stdio`).

## Tool

- `hackernews_get_random_story`
  - Аргументы: не принимает аргументы
  - Возвращает одну случайную top story (заголовок, id, автор, score, время, URL)

## Переменные окружения

- `HACKERNEWS_BASE_URL` (optional, default: `https://hacker-news.firebaseio.com`)
- `HACKERNEWS_LOG_LEVEL` (optional, default: `info`, values: `debug|info|warn|error`)

## Запуск

```bash
cd /Users/stasklem/project/Golang/md/less_18_codex/HackerNewsMCPServer
swift run HackerNewsMCPServer
```
