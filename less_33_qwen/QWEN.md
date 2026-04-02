# SupportBot

## Project Overview

**SupportBot** — это минималистичный CLI-проект на Swift для macOS, представляющий собой заготовку для консольного приложения. Проект создан 2 апреля 2026 года и использует Xcode в качестве IDE.

### Технологии

- **Язык:** Swift 5.0
- **Платформа:** macOS 26.2+
- **IDE:** Xcode 26.2+
- **Тип приложения:** Command-line tool (консольная утилита)

### Структура проекта

```
less_33_qwen/
└── SupportBot/
    ├── SupportBot/
    │   └── main.swift          # Точка входа приложения
    └── SupportBot.xcodeproj/   # Проект Xcode
        └── project.pbxproj
```

## Building and Running

### Запуск из Xcode

1. Откройте `SupportBot.xcodeproj` в Xcode
2. Нажмите `Cmd + R` для сборки и запуска

### Запуск из командной строки

```bash
# Перейдите в директорию проекта
cd SupportBot

# Сборка и запуск через xcodebuild
xcodebuild -project SupportBot.xcodeproj -scheme SupportBot build

# Или используйте swift напрямую (если настроен Swift Package Manager)
swift run
```

### Конфигурации сборки

Проект содержит две стандартные конфигурации:

- **Debug** — сборка с отладочной информацией, оптимизация отключена (`-Onone`)
- **Release** — оптимизированная сборка с DWARF с dSYM

## Development Conventions

### Код-стайл

- Swift 5.0 синтаксис
- Стандартные соглашения именования Swift (camelCase для переменных/функций, PascalCase для классов/протоколов)
- Автоматическое управление памятью через ARC

### Требования к компилятору

- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — включена поддержка concurrency
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — включена видимость импорта членов
- `CLANG_CXX_LANGUAGE_STANDARD = "gnu++20"` — стандарт C++ дляinterop
- `GCC_C_LANGUAGE_STANDARD = gnu17` — стандарт C

### Подписывание кода

Проект настроен на автоматическое подписывание (`CODE_SIGN_STYLE = Automatic`) с использованием development team: `R48NAQ3X5H`

## Current State

На данный момент проект содержит только базовую заготовку с выводом `"Hello, World!"` в консоль. Это отправная точка для разработки функциональности SupportBot.
