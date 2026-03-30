# OpenWeatherMCPServer

MCP сервер для OpenWeatherMap API на `swift-mcp-sdk` (`MCP`).

## Tools

- `weather_get_current`
  - Аргументы: `city` (required), `units` (`standard|metric|imperial`), `lang`
- `weather_get_forecast`
  - Аргументы: `city` (required), `units` (`standard|metric|imperial`), `lang`, `count` (`1...40`)

## Переменные окружения

- `OPENWEATHER_API_KEY` (optional for startup, required for actual weather tool calls)
- `OPENWEATHER_BASE_URL` (optional, default: `https://api.openweathermap.org`)
- `OPENWEATHER_DEFAULT_LANG` (optional)

## Запуск

```bash
cd /Users/stasklem/project/Golang/md/less_17_codex/OpenWeatherMCPServer
OPENWEATHER_API_KEY=your_key swift run OpenWeatherMCPServer
```

Сервер работает через MCP `stdio` transport.
