# LightNeiroClient

macOS клиент на `AppKit` (MVVM, без SwiftUI) с чатом и встроенным отпускным планировщиком.

## Что делает приложение
- отправляет сообщения в LLM;
- хранит историю сообщений одной активной ветки;
- собирает краткосрочную/рабочую/долговременную память для запроса;
- позволяет настроить модель, temperature, window size и API-ключ;
- показывает базовые метрики сессии (токены, количество запросов, latency);
- поддерживает Vacation Planner (state-machine + сохранение снапшотов/финального плана);
- собирает данные для планировщика в свободной форме через LLM-first extraction;
- учитывает инварианты планировщика из окна настроек (`plannerInvariants`) при извлечении и формулировке вопросов;
- при нарушении инвариантов (например, некорректные даты/бюджет) сообщает об ошибке и повторно запрашивает корректные данные.

## Архитектура
- `Presentation`: контроллеры и view-model экрана чата, настроек и метрик.
- `Domain`: сущности, протоколы и use cases бизнес-логики, включая vacation state-machine и questionnaire pipeline.
- `Data`: репозитории (in-memory/file/Keychain/network) и LLM adapters для extraction/question generation.

## Машина состояний Vacation Planner

### Базовые состояния
- `idle`: планировщик не активен.
- `collectingRequirements`: первичный сбор обязательных данных.
- `clarifyingMissingData`: уточнение отсутствующих или невалидных полей.
- `generatingOptions`: генерация вариантов поездки.
- `buildingItinerary`: построение маршрута.
- `budgetReview`: расчет и проверка бюджета.
- `awaitingApproval`: ожидание подтверждения (`approve`) или правок (`revise: ...`).
- `completed`: финальный план сформирован и сохранен.
- `failed(reason)`: критическая ошибка перехода/инварианта.

### Как идет обработка шага
1. `VacationPlanningOrchestrator` загружает текущий `snapshot`.
2. Входное событие (`started`, `userMessage`, `approved`, `revisionRequested`) передается в `VacationPlannerReducer`.
3. Reducer возвращает `VacationPlanningTransitionResult`:
- `nextState`
- `nextContext`
- список `effects`
4. Orchestrator выполняет `effects` по очереди (`askQuestion`, `processUserAnswer`, `generateDestinationOptions`, `generateItinerary`, `calculateBudget`, `persistSnapshot`, `emitFinalPlan`).
5. Эффекты могут порождать новые события; они добавляются в очередь и обрабатываются в том же цикле.
6. Итоговый `snapshot` сохраняется в репозитории состояния.

### Команды пользователя в режиме планировщика
- `approve` -> событие подтверждения, переход к `completed`.
- `revise: ...` -> запрос правки, возврат к перерасчету или повторному сбору требований.
- любое другое сообщение -> `userMessage`, запускается извлечение данных и уточнение.

## Валидация ответов пользователя

### Канал ввода
- Чат и форма идут в один и тот же pipeline.
- Для чата `source = .chat`.
- Для формы `source = .form`, значения считаются высокодоверенными (`confidence = 1.0`).

### Extraction и нормализация
- `ProcessUserAnswerUseCase` вызывает `AnswerExtractionServiceProtocol`.
- Текущая стратегия: `LLM-first` extraction в структурированный JSON по полям:
- `destination`, `dates`, `budget`, `travel_style`, `interests`, `constraints`.
- При невалидном JSON/типах/ошибке LLM:
- система не падает;
- возвращаются `warnings`;
- пользователю задается уточняющий вопрос.

### Проверка confidence и ambiguous-ответов
- У `ProcessUserAnswerUseCase` есть `confidenceThreshold` (сейчас `0.7`).
- Если извлеченное поле имеет confidence ниже порога или помечено `ambiguous`, поле не записывается в `answers`.
- Пользователь получает сообщение с причиной и уточняющий вопрос по проблемному полю.

### Полевая валидация
- Перед записью значения проходят доменные валидаторы (`QuestionnaireValidationRule`):
- `nonEmptyText`
- `validDateRange`
- `positiveMoneyAmount`
- `positiveInteger`
- `nonEmptyList`
- Невалидные значения не применяются к `QuestionnaireState` и `VacationSlots`.

### Логика продолжения после валидации
- Если есть незаполненные `hard`-поля -> состояние `clarifyingMissingData`, задается следующий вопрос.
- Если `hard` заполнены, но есть `soft`-поля -> можно продолжать, но с предупреждением.
- Если все поля валидны -> переход к генерации вариантов.

## Проверка инвариантов

### 1) Доменные инварианты state-machine (pre/post перехода)
- На каждом редьюсе вызывается `VacationPlanningInvariantValidator.validate(...)`:
- до расчета перехода (`pre`)
- после расчета перехода (`post`)
- Эти проверки защищают целостность модели состояний (например, порядок дат, положительный бюджет, корректность обязательных артефактов для завершения и т.д.).

### 2) Инварианты пользовательского ввода во время сбора данных
- После применения результата extraction в `questionnaireProcessedTransition` выполняется дополнительная проверка пользовательских инвариантов для `slots`.
- Если нарушение найдено (например, `startDate > endDate` или `budget <= 0`):
- состояние не переводится в `failed`;
- пользователю отправляется понятное сообщение об ошибке;
- задается повторный вопрос по проблемному полю;
- flow остается в `clarifyingMissingData` до корректного ответа.

### 3) Инварианты из окна настроек (`plannerInvariants`)
- Пользовательские инварианты из Settings подгружаются из `SettingsRepository`.
- Они передаются в LLM extraction и question generation как часть `systemPrompt`.
- Это влияет на формулировку вопросов и интерпретацию свободного ввода LLM.
- Критичные доменные ограничения при этом дополнительно контролируются локальными проверками в reducer/use case (без зависимости от LLM).

## Ограничения текущей версии
- нет переключения веток и создания веток;
- нет profile-системы для пользовательских префиксов;
- extraction и question generation зависят от доступности LLM/API-ключа;
- нет отдельного визуального экрана анкеты (форма отправляет данные в тот же pipeline, что и чат).
