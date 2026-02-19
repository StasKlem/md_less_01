# MacLlmTerminal

## Project Overview

**MacLlmTerminal** — это macOS-приложение на Swift, разработанное с использованием Cocoa framework. Проект создан в Xcode 26.2 и представляет собой нативное десктопное приложение для macOS.

### Технологии

- **Язык:** Swift 5.0
- **Фреймворк:** Cocoa (AppKit)
- **Минимальная версия macOS:** 26.1
- **IDE:** Xcode 26.2
- **Bundle ID:** `StasKlem.MacLlmTerminal`

### Структура проекта

```
MacLlmTerminal/
├── MacLlmTerminal/
│   ├── AppDelegate.swift          # Главный класс приложения
│   ├── ViewController.swift       # Контроллер основного окна
│   ├── Assets.xcassets/           # Ресурсы (иконки, цвета)
│   └── Base.lproj/
│       └── Main.storyboard        # UI-разметка основного окна
└── MacLlmTerminal.xcodeproj/      # Проект Xcode
```

## Building and Running

### Требования

- macOS 26.1 или новее
- Xcode 26.2 или новее

### Сборка и запуск

1. Откройте проект в Xcode:
   ```bash
   open MacLlmTerminal/MacLlmTerminal.xcodeproj
   ```

2. Запустите сборку и выполнение:
   - **Build & Run:** `Cmd + R`
   - **Build only:** `Cmd + B`
   - **Clean Build Folder:** `Cmd + Shift + K`

### Сборка через командную строку

```bash
# Сборка Debug-версии
xcodebuild -project MacLlmTerminal/MacLlmTerminal.xcodeproj -scheme MacLlmTerminal -configuration Debug build

# Сборка Release-версии
xcodebuild -project MacLlmTerminal/MacLlmTerminal.xcodeproj -scheme MacLlmTerminal -configuration Release build
```

## Development Conventions

### Код-стайл

- Swift-конвенции именования (camelCase для переменных/функций, PascalCase для типов)
- Использование `@main` для entry point класса
- Стандартные lifecycle-методы Cocoa: `applicationDidFinishLaunching`, `applicationWillTerminate`

### Архитектура

- **AppDelegate:** Управление жизненным циклом приложения
- **ViewController:** Логика основного окна
- **Storyboard:** UI-разметка через Interface Builder

### Подписывание кода

Проект настроен на автоматическое подписывание кода (`CODE_SIGN_STYLE = Automatic`) с использованием Development Team: `R48NAQ3X5H`.

### Безопасность

Включены следующие функции безопасности:
- App Sandbox
- Hardened Runtime
- Secure Restorable State

## Notes

- Проект находится на начальной стадии разработки
- Текущая версия: 1.0 (Marketing Version)
- Build Version: 1
