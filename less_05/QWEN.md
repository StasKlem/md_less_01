# MacTerminalQwen

## Project Overview

**MacTerminalQwen** — это macOS-приложение на Swift, разработанное как нативный клиент для взаимодействия с Qwen Code CLI. Приложение использует стандартный стек технологий Apple:

- **Язык:** Swift 5.0
- **Фреймворк:** Cocoa (AppKit)
- **Минимальная версия macOS:** 26.2
- **IDE:** Xcode 26.2+
- **Архитектура:** MVC с использованием Storyboard

### Структура проекта

```
MacTerminalQwen/
├── MacTerminalQwen/
│   ├── AppDelegate.swift          # Точка входа, управление жизненным циклом приложения
│   ├── ViewController.swift       # Основной контроллер представления
│   ├── Base.lproj/
│   │   └── Main.storyboard        # UI-интерфейс приложения
│   └── Assets.xcassets/           # Ресурсы (иконки, цвета)
└── MacTerminalQwen.xcodeproj/     # Проект Xcode
```

## Building and Running

### Требования

- macOS 26.2 или новее
- Xcode 26.2 или новее
- Apple Developer Team ID: `R48NAQ3X5H`

### Сборка и запуск

```bash
# Открыть проект в Xcode
open MacTerminalQwen/MacTerminalQwen.xcodeproj

# Сборка через командную строку (Debug)
xcodebuild -project MacTerminalQwen/MacTerminalQwen.xcodeproj -scheme MacTerminalQwen -configuration Debug build

# Сборка Release
xcodebuild -project MacTerminalQwen/MacTerminalQwen.xcodeproj -scheme MacTerminalQwen -configuration Release build

# Запуск приложения
xcodebuild -project MacTerminalQwen/MacTerminalQwen.xcodeproj -scheme MacTerminalQwen run
```

### Конфигурации сборки

| Конфигурация | Оптимизация | Debug Info | Назначение |
|-------------|-------------|------------|------------|
| Debug       | `-Onone`    | DWARF      | Разработка и отладка |
| Release     | `wholemodule` | DWARF with dSYM | Продакшен |

## Development Conventions

### Код-стайл

- **Именование:** CamelCase для классов и протоколов (`AppDelegate`, `ViewController`)
- **Структура файлов:** Каждый класс в отдельном файле с именем, совпадающим с именем класса
- **Комментарии:** Минимальные, только для объяснения сложной логики
- **Actor isolation:** `MainActor` по умолчанию для потокобезопасности UI

### Настройки Swift

```swift
SWIFT_VERSION = 5.0
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_EMIT_LOC_STRINGS = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
```

### Безопасность

- Включён App Sandbox
- Включён Hardened Runtime
- Code Signing: Automatic (Team: R48NAQ3X5H)
- Доступ к файлам: только выбранные пользователем (readonly)

### Bundle Information

- **Bundle Identifier:** `StasKlem.MacTerminalQwen`
- **Version:** 1.0 (Current Project Version: 1)
- **Principal Class:** `NSApplication`
- **Main Storyboard:** `Main`

## Testing

На текущий момент тесты не настроены. Для добавления тестов:

1. Создать target для тестов в Xcode
2. Добавить XCTest framework
3. Использовать команду:

```bash
xcodebuild test -project MacTerminalQwen/MacTerminalQwen.xcodeproj -scheme MacTerminalQwen -destination 'platform=macOS'
```

## Notes

- Проект использует string catalogs для локализации (`STRING_CATALOG_GENERATE_SYMBOLS = YES`)
- Включена поддержка string asset catalogs (`LOCALIZATION_PREFERS_STRING_CATALOGS = YES`)
- Приложение использует стандартное меню macOS с поддержкой File, Edit, View и других системных меню
