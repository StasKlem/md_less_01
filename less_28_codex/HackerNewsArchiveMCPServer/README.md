# HackerNewsArchiveMCPServer

Локальный MCP сервер для сохранения JSON в файлы и чтения 3 последних сохранений (`swift-mcp-sdk`, transport `stdio`).

## Tools

- `hackernews_archive_save_json`
  - Аргументы:
    - `json` (string, required): JSON payload для сохранения.
  - Сохраняет JSON в файл `hackernews_YYYYMMDD_HHMMSS_SSS.json`.

- `hackernews_archive_get_latest_files`
  - Аргументы: не принимает.
  - Возвращает 3 последних сохранённых JSON-файла вместе с содержимым.

## Переменные окружения

- `HACKERNEWS_ARCHIVE_STORAGE_DIR` (optional): директория для хранения файлов.
- `HACKERNEWS_ARCHIVE_LOG_LEVEL` (optional, default: `info`, values: `debug|info|warn|error`).

Если `HACKERNEWS_ARCHIVE_STORAGE_DIR` не задан, используется:
`~/Library/Application Support/HackerNewsArchiveMCPServer/storage`.

## Запуск

```bash
cd /Users/stasklem/project/Golang/md/less_19_codex/HackerNewsArchiveMCPServer
swift run HackerNewsArchiveMCPServer
```
