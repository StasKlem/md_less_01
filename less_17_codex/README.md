# LightNeiroClient

macOS клиент на `AppKit` (MVVM, без SwiftUI) с чатом, memory layers и встроенным Vacation Planner.

## Конечный автомат (FSM): этапы и переходы

### Состояния (этапы)
- `idle`: планировщик не выполняет активный шаг.
- `destinationRequest`: запрос/уточнение направления поездки (`destination`).
- `validatingDestination`: извлечение и валидация пользовательского ответа.
- `awaitingPlanApproval`: ожидание подтверждения (`approve`) или правки (`revise: ...`).
- `generateResult`: генерация опций, маршрута, бюджета и финального плана.
- `failed(reason)`: ошибка перехода/инварианта/сервиса.

### Разрешённые переходы
1. `idle` + `started` -> `destinationRequest`
2. `idle` + `userMessage` -> `destinationRequest`
3. `destinationRequest` + `userMessage` -> `validatingDestination`
4. `validatingDestination` + `questionnaireProcessed` (destination невалиден) -> `destinationRequest`
5. `validatingDestination` + `questionnaireProcessed` (destination валиден) -> `awaitingPlanApproval`
6. `awaitingPlanApproval` + `planApproved` -> `generateResult`
7. `awaitingPlanApproval` + `revisionRequested` -> `destinationRequest`
8. `generateResult` + `optionsGenerated` -> `generateResult`
9. `generateResult` + `itineraryGenerated` -> `generateResult`
10. `generateResult` + `budgetCalculated` -> `idle` (финальный план сформирован и зафиксирован)
11. `failed(reason)` + `started` -> `destinationRequest`
12. `failed(reason)` + `userMessage` -> `validatingDestination`
13. Любое состояние + `errorOccurred` -> `failed(reason)`

### Невозможные переходы (запрещены редьюсером)
- Из `idle` запрещены: `planApproved`, `revisionRequested`, `questionnaireProcessed`, `optionsGenerated`, `itineraryGenerated`, `budgetCalculated`, `executionCompleted`, `validationPassed`, `validationFailed`, `finalizeRequested`.
- Из `destinationRequest` запрещены все события, кроме `userMessage` и глобального `errorOccurred`.
- Из `validatingDestination` запрещены все события, кроме `questionnaireProcessed` и глобального `errorOccurred`.
- Из `awaitingPlanApproval` запрещены все события, кроме `planApproved`, `revisionRequested` и глобального `errorOccurred`.
- Из `generateResult` запрещены все события, кроме `optionsGenerated`, `itineraryGenerated`, `budgetCalculated` и глобального `errorOccurred`.
- Из `failed(reason)` запрещены все события, кроме `started`, `userMessage` и глобального `errorOccurred`.

### Важно про неподдержанные события
- События `executionCompleted`, `validationPassed`, `validationFailed`, `finalizeRequested` объявлены в модели, но в текущей версии FSM не имеют разрешённых переходов и всегда блокируются.

## Возможности
- чат с LLM;
- настройка модели, `temperature`, `windowSize`, API-ключа и `plannerInvariants`;
- краткосрочная, рабочая и долговременная память для контекста;
- сохранение истории сообщений в активной ветке;
- экран метрик сессии (токены, запросы, задержка);
- Vacation Planner на базе конечного автомата (FSM) с сохранением snapshot и финального плана;
- интеграция с MCP: при старте планировщика выполняется подключение к `open-weather` серверу и выводится системное сообщение со списком доступных `tools`.

## MCP интеграция (open-weather)
- Пакет: `https://github.com/msventurini/swift-mcp-sdk.git` (SPM продукт `MCP`).
- Endpoint: `stdio://open-weather` (по умолчанию клиент запускает локальный `OpenWeatherMCPServer` как subprocess через stdio).
- Для явного пути к исполняемому серверу используйте env: `OPENWEATHER_MCP_SERVER_PATH=/abs/path/to/OpenWeatherMCPServer`.
- Точка запуска: при команде `/vacation start` перед запуском FSM.
- Что видит пользователь: системное сообщение вида:
  - `MCP open-weather подключен.`
  - `Доступные tools:`
  - `- <tool_name>: <description>` (или `- <tool_name>`, если описание отсутствует)
- При ошибке подключения или `tools/list` выводится системное сообщение:
  - `MCP open-weather: не удалось получить tools (<error>).`

## Архитектура
- `Presentation`: AppKit контроллеры и `ViewModel`.
- `Domain`: сущности, протоколы и use case'ы (бизнес-логика и FSM).
- `Data`: реализации репозиториев, Keychain, file storage и LLM-клиенты.

Зависимости направлены внутрь: outer layers зависят от доменных абстракций, а не наоборот.

## Быстрый старт

### Запуск из Xcode
1. Откройте проект: `LightNeiroClient/LightNeiroClient.xcodeproj`.
2. Выберите схему `LightNeiroClient`.
3. Запустите приложение (`Run`).

### Сборка из терминала
```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -configuration Debug build
```

### Тесты
```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -destination 'platform=macOS' test
```

## Vacation Planner: актуальная FSM

### Состояния
- `idle`: ожидание.
- `destinationRequest`: запрос/уточнение destination.
- `validatingDestination`: обработка и валидация ответа пользователя.
- `awaitingPlanApproval`: ожидание команды `approve` или `revise: ...`.
- `generateResult`: генерация опций, маршрута и бюджета.
- `failed(reason)`: состояние ошибки.

### Ключевые переходы
1. `started` (или первое сообщение из `idle`) -> `destinationRequest`.
2. Сообщение пользователя в `destinationRequest` -> `validatingDestination` + `processUserAnswer`.
3. `questionnaireProcessed`:
- destination невалиден -> `destinationRequest` + повторный вопрос;
- destination валиден -> `awaitingPlanApproval`.
4. `planApproved` -> `generateResult`.
5. В `generateResult` оркестратор последовательно вызывает:
- `generateDestinationOptions`;
- `generateItinerary`;
- `calculateBudget`.
6. После `budgetCalculated` формируется `finalPlan`, план блокируется (`isFinalPlanLocked = true`), FSM возвращается в `idle`.
7. `revisionRequested(comment)` из `awaitingPlanApproval` сбрасывает утверждение/результаты, очищает `destination` и возвращает в `destinationRequest`.

### Команды пользователя
- `/vacation start` или `/vacation`: запускает сценарий планировщика. Перед стартом FSM выполняется попытка подключения к MCP `open-weather` и публикация списка `tools`.
- `/vacation stop`: останавливает режим планировщика и возвращает обычный чат.
- `approve`: подтвердить собранные данные и запустить генерацию финального результата.
- `revise: <комментарий>`: откатиться к повторному выбору направления с учетом комментария.
- любое другое сообщение: обработать как пользовательский ввод анкеты (`userMessage`).

## Валидация и инварианты
- `ProcessUserAnswerUseCase` извлекает структурированные поля из свободного ввода (LLM-first), применяет валидаторы и confidence threshold.
- При неуспешном извлечении/валидации пользователь получает уточняющий вопрос, FSM не падает.
- `VacationPlanningInvariantValidator` проверяет доменные инварианты (даты, бюджет, количество путешественников, корректность переходов).
- Для обратной совместимости старые сохраненные состояния автоматически маппятся в новую FSM при декодировании snapshot.

## Структура проекта
- `LightNeiroClient/LightNeiroClient/App`: сборка зависимостей и окружения.
- `LightNeiroClient/LightNeiroClient/Presentation`: экраны чата, настроек, метрик.
- `LightNeiroClient/LightNeiroClient/Domain`: модели, протоколы, use case'ы.
- `LightNeiroClient/LightNeiroClient/Data`: network/storage/security/mocks.
- `LightNeiroClient/LightNeiroClientTests`: unit-тесты, включая жизненный цикл Vacation Planner.

## Ограничения текущей версии
- одна активная ветка диалога без UI для полноценного branch management;
- генерация вопросов/извлечение полей зависят от доступности LLM и валидного API-ключа;
- анкета и чат используют единый pipeline (отдельной формы сценария планировщика нет).
