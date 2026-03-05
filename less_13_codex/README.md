## Маршрут Запроса И Механизм Состояний Агента (Подробно)

Ниже описан реальный runtime-маршрут в приложении, начиная с ввода пользователя, а также конечный автомат состояний задачи (task-flow), который управляет поведением агента.

### 1) Полный маршрут запроса: от ввода пользователя до ответа

1. Пользователь вводит текст в поле чата и нажимает `Send`.
- `ChatSidebarViewController.sendTapped()` читает текст, очищает поле, вызывает `ChatViewModel.send(text:)`.

2. `ChatViewModel` переводит UI в состояние отправки.
- Проверяет блокировки (`isSending`, пустой ввод).
- Фиксирует `targetBranchID`, чтобы ответ гарантированно вернулся в ту ветку, из которой началась отправка.
- Добавляет в локальный UI:
  - сообщение пользователя (`.user`, `sent`);
  - временный плейсхолдер ответа ассистента (`.assistant`, `streaming`).

3. `ChatViewModel` вызывает оркестратор задачи.
- Вызов: `TaskFlowOrchestratorUseCase.execute(sessionID, branchID, userInput, userAction)`.
- Здесь начинается доменная часть task-flow.

4. Оркестратор читает текущее состояние и вычисляет переход.
- Загружает `LLMSettings` (включая `agentFlowSettings`).
- Читает текущее `TaskProgressState` для ветки (или берёт `initial()`).
- Преобразует пользовательский ввод/кнопочное действие в доменное событие (`TaskFlowEvent`).
- Через `AdvanceTaskStageUseCase` вычисляет следующее состояние `next`.

5. Оркестратор формирует инструкцию для ассистента и делегирует генерацию.
- Строит `assistantInstruction`, где фиксирует:
  - текущий stage/step;
  - ожидаемое следующее действие;
  - формат ответа (строго 3 секции markdown);
  - краткую сводку прошлых артефактов.
- Вызывает `SendMessageUseCase.execute(...)`.

6. `SendMessageUseCase` выполняет полный цикл user-turn/assistant-turn.
- Добавляет профильный префикс к user text (если включён).
- Сохраняет user message в репозиторий сообщений.
- Загружает настройки сессии.
- Обновляет память:
  - `short-term` (строго);
  - `working` (best-effort);
  - `long-term` (best-effort).
- Строит `MemoryContext`.
- Формирует `LLMRequest` и отправляет его через `LLMClient` (`RouterAILLMClient`).
- Получает ответ, сохраняет assistant message.
- Повторно обновляет часть памяти после assistant-turn.
- Пишет метрику (`latency`, `inputTokens`, `outputTokens`).

7. Оркестратор завершает шаг task-flow.
- Создаёт `StageArtifact` из ответа ассистента.
- Сохраняет:
  - `TaskProgressState` в `TaskProgressRepository`;
  - `StageArtifact` в `StageArtifactRepository`.
- Возвращает `TaskFlowOutput` в `ChatViewModel`.

8. `ChatViewModel` синхронизирует UI.
- Обновляет `taskProgressState` и `availableTaskActions`.
- Заменяет временный `streaming`-ответ финальным текстом.
- Перечитывает диалог ветки из репозитория (`loadDialog(for:)`), чтобы UI опирался на источник истины.
- Сбрасывает `isSending`, уведомляет подписчиков (включая метрики справа).

9. Ошибки в цепочке.
- Если любой критичный шаг падает, `ChatViewModel`:
  - переводит assistant-item в `failed`;
  - добавляет системное сообщение `Error: ...`;
  - снимает `isSending`.

### 2) Механизм состояний задачи (state machine агента)

Task-flow реализован как детерминированный конечный автомат.

#### Сущности автомата

- `AgentStage`:
  - `planning`
  - `execution`
  - `validation`
  - `done`

- `AgentExpectedAction`:
  - `await_input`
  - `await_continue`
  - `await_confirmation`
  - `none`
  - (также есть `await_clarification` в модели, но в текущих переходах не выставляется)

- `TaskProgressState`:
  - `stage`
  - `step`
  - `expectedAction`
  - `updatedAt`

- `TaskFlowEvent`:
  - `userContinue`
  - `userConfirm`
  - `userClarification`

- `TaskFlowUserAction` (вход из UI-кнопок):
  - `.continueAction`
  - `.confirm`

#### Начальное состояние

`TaskProgressState.initial()`:
- `stage = planning`
- `step = 1`
- `expectedAction = await_input`

Это означает: агент ждёт первый осмысленный ввод пользователя для старта цикла.

### 3) Как вход пользователя превращается в событие автомата

В `TaskFlowOrchestratorUseCase.resolveEvent(...)` действует приоритет:

1. Если нажата кнопка `Continue` (`userAction == .continueAction`) -> событие `userContinue`.
2. Если нажата кнопка `Confirm` (`userAction == .confirm`) -> событие `userConfirm`.
3. Иначе анализируется текст:
- `"продолжить"` или `"continue"` -> `userContinue`;
- текст равен `normalizedConfirmCommand` из настроек -> `userConfirm`;
- всё остальное -> `userClarification`.

`normalizedConfirmCommand` берётся из `AgentFlowSettings.confirmCommand`:
- trim + lowercase;
- если пусто, fallback на дефолтную команду `"ок"`.

### 4) Правила переходов между состояниями (точная логика)

Переходы задаются в `AdvanceTaskStageUseCase.execute(...)`.

1. `planning + userContinue`
- Новое состояние: `execution`.
- `step = step + 1`.
- `expectedAction = await_continue`.

2. `execution + userContinue`
- Новое состояние: `validation`.
- `step = step + 1`.
- `expectedAction` зависит от `doneTransitionMode`:
  - `manualCommand` -> `await_confirmation`;
  - `auto` -> `await_continue`.

3. `validation + userContinue`
- Если `doneTransitionMode == auto`:
  - переход в `done`;
  - `step = step + 1`;
  - `expectedAction = none`.
- Если `doneTransitionMode == manualCommand`:
  - остаёмся в `validation`;
  - `step` не увеличивается;
  - `expectedAction = await_confirmation`.

4. `validation + userConfirm`
- Всегда переход в `done`.
- `step = step + 1`.
- `expectedAction = none`.

5. `done + любое событие`
- Остаёмся в `done`.
- `step` не меняется.
- `expectedAction = none`.

6. `любая стадия + userClarification`
- Стадия не меняется.
- `step` не меняется.
- `expectedAction` пересчитывается от текущей стадии:
  - `planning` -> `await_continue`;
  - `execution` -> `await_continue`;
  - `validation` -> `await_confirmation` при `manualCommand`, иначе `await_continue`;
  - `done` -> `none`.

### 5) Как настройки влияют на переходы

Ключевое поле: `AgentFlowSettings.doneTransitionMode`.

- `auto`:
  - в `validation` команда continue может сразу завершить задачу (`done`).
- `manualCommand`:
  - из `validation` в `done` переход только после confirm-команды (кнопка confirm или текст confirm-команды).

Ключевое поле: `AgentFlowSettings.confirmCommand`.

- Определяет текстовую команду подтверждения.
- Участвует в `resolveEvent()` и напрямую влияет, будет ли событие `userConfirm`.

### 6) Доступные пользователю действия по стадиям

`availableActions(for state)` возвращает:

- `planning` -> `[continue]`
- `execution` -> `[continue]`
- `validation`:
  - если `expectedAction == await_confirmation` -> `[confirm]`
  - иначе -> `[continue, confirm]`
- `done` -> `[]`

Именно этот список управляет активностью кнопок `Продолжить/Подтвердить` в UI.

### 7) Роль артефактов стадий

После каждого успешного шага создаётся `StageArtifact`:
- фиксирует `stage`, `step`, `content`, `sourceMessageIDs`, `createdAt`;
- используется как история прогресса;
- передаётся в `assistantInstruction` (краткая сводка последних артефактов), чтобы следующий ответ был согласован с предыдущими шагами.

### 8) Инварианты и гарантии текущего механизма

- Автомат детерминирован: одинаковое `(state, event, flowSettings)` даёт одинаковый `next state`.
- Состояние сохраняется на уровне ветки (`branchID`), не на уровне всей сессии.
- После успешного ответа состояние и артефакт записываются атомарно в рамках одного orchestration-шага (последовательно, в одной async-цепочке).
- Ветка, в которую пишется ответ, фиксируется в начале отправки (`targetBranchID`) и не «прыгает» при UI-переключениях.

# LightNeiroClient

`LightNeiroClient` — macOS-клиент чата с LLM на `AppKit`, реализованный по `Clean Architecture` и `MVVM`.

## Ключевые возможности

- чат с ассистентом;
- ветвление диалога (branch tree);
- task-flow режим (`planning -> execution -> validation -> done`);
- настройки модели/температуры/окна контекста;
- профили пользовательского префикса;
- метрики запросов (tokens/latency);
- хранение API-ключа в Keychain.

## Архитектура

1. `Domain`
- сущности (`ChatMessage`, `ChatBranch`, `TaskProgressState`, `LLMSettings`);
- протоколы репозиториев/сервисов;
- use case-логика (`SendMessageUseCase`, `TaskFlowOrchestratorUseCase`, memory use cases).

2. `Data`
- сетевой адаптер: `RouterAILLMClient`;
- хранилища: `UserDefaultsSettingsRepository`, `FileLongTermMemoryRepository`, `FileTaskProgressRepository`, `FileStageArtifactRepository`;
- in-memory репозитории для сообщений/веток/метрик.

3. `Presentation`
- `NSViewController` + `ViewModel`;
- экраны: Chat, Settings, SessionInfo;
- координация через `MainViewModel`.

4. `App`
- `AppEnvironment.bootstrap()` собирает зависимости и стартовые данные.

## Память и стратегии контекста

Используются 3 слоя памяти:

1. `short-term`
- окно последних сообщений ветки (без `system`);
- управляется `windowSize` и стратегией контекста.

2. `working`
- оперативные ключи задачи (`task.goal`, `task.constraints`, `task.current_step` и др.);
- извлекается эвристиками из текста пользователя/ассистента.

3. `long-term`
- устойчивые сведения (`profile/decisions/knowledge`);
- хранится в файловом репозитории (`Application Support/LightNeiroClient/long_term_memory`).

Стратегии (`ContextStrategy`):
- `normal`: полный доступный non-system диалог;
- `slidingWindow`: последние `N` сообщений;
- `stickyFacts`: оконный диалог + long-term слой.

## Хранение данных

- `ChatSession/Branch/Message/ShortTerm/Working/Metrics`: in-memory (`Mock*Repository`, actor `InMemoryChatStore`);
- `LLMSettings`: `UserDefaults`;
- `LongTermMemory`: JSON в `Application Support`;
- `TaskProgress` и `StageArtifacts`: JSON в `Application Support`;
- `API key`: Keychain (`KeychainAPIKeyStore`).

## Запуск

1. Откройте `LightNeiroClient/LightNeiroClient.xcodeproj`.
2. Выберите схему `LightNeiroClient`.
3. Запустите `Run`.

CLI:

```bash
xcodebuild -project LightNeiroClient/LightNeiroClient.xcodeproj -scheme LightNeiroClient -configuration Debug build
```

## Текущий статус тестов

На данный момент отдельный `XCTest` target отсутствует.
Рекомендуется добавить unit-тесты для:
- `TaskFlowOrchestratorUseCase`;
- `SendMessageUseCase`;
- memory use cases (`BuildMemoryContext`, `UpdateShortTerm`, `UpdateWorking`, `UpdateLongTerm`);
- error-сценариев сетевого клиента.
