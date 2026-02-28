# Алгоритм метрик

## Обзор

LLM Client отслеживает метрики запросов, включая токены в секунду, продолжительность запроса и количество токенов.

## Компоненты

### MetricsViewModel

Расположение: `MacTerminalOpencode/ViewModels/MetricsViewModel.swift`

### Структура RequestMetrics

```swift
struct RequestMetrics {
    var modelName: String           // Название модели
    var totalTokens: Int            // Общее количество токенов
    var promptTokens: Int           // Токены промпта
    var completionTokens: Int       // Токены ответа
    var tokensPerSecond: Double     // Скорость (токенов/сек)
    var requestDuration: TimeInterval // Продолжительность запроса
    var startTime: Date             // Время начала
}
```

## Алгоритм

### 1. Продолжительность запроса (Duration)

```
Duration = CurrentTime - StartTime
```

- **StartTime**: Устанавливается при вызове `startRequest()` (когда пользователь отправляет сообщение)
- **CurrentTime**: Фиксируется при завершении или во время стриминга
- **Единица измерения**: Секунды (TimeInterval = Double)

```swift
requestDuration = Date().timeIntervalSince(startTime)
```

### 2. Количество токенов

Токены **оцениваются** с помощью подсчёта слов:

```
Количество токенов = Количество слов в ответе
```

```swift
let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
                         .filter { !$0.isEmpty }
                         .count
```

**Примечание**: Это приближённая оценка. Настоящий токенизатор (например, tiktoken) был бы точнее, но для простоты мы используем количество слов как прокси.

**Поток данных:**
1. Каждый стриминг-чанк вызывает `recordTokens(wordCount)`
2. Токены накапливаются: `tokenCount += count`
3. При завершении: `completionTokens = tokenCount`

### 3. Токенов в секунду (Скорость)

```
Speed = completionTokens / requestDuration
```

```swift
tokensPerSecond = Double(completionTokens) / requestDuration
```

**Условия:**
- Вычисляется только когда `requestDuration > 0`
- Обновляется во время стриминга и при завершении

## Диаграмма потока

```
Пользователь отправляет сообщение
        │
        ▼
┌─────────────────────┐
│ startRequest()      │
│ - tokenCount = 0    │
│ - startTime = now   │
│ - эмиссия метрик    │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│ Стриминг чанков     │
│ (для каждого чанка) │
│ ─────────────────── │
│ recordTokens(count) │
│ - tokenCount += N   │
│ - duration = now -  │
│   startTime         │
│ - speed = tokens /  │
│   duration          │
│ - эмиссия метрик    │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│ completeRequest()   │
│ - финальная duration│
│ - финальный токены  │
│ - финальная скорость│
│ - эмиссия метрик    │
└─────────────────────┘
```

## Точки интеграции

### ChatViewModel

Вызывает методы MetricsViewModel:

| Событие | Действие |
|---------|----------|
| `sendMessage()` | `metricsViewModel.startRequest()` |
| `.chunkReceived` | `metricsViewModel.recordTokens(wordCount)` |
| `.completed` | `metricsViewModel.completeRequest()` |

### MetricsPanelViewController

Слушает `MetricsViewModelEvent` и обновляет UI:

```swift
case .metricsUpdated(let metrics):
    modelNameLabel = "Model: \(metrics.modelName)"
    tokensLabel = "Tokens: \(metrics.completionTokens)"
    speedLabel = "Speed: \(metrics.tokensPerSecond) tok/s"
    durationLabel = "Duration: \(metrics.requestDuration)s"
```

## Пример расчёта

```
Время начала: 10:00:00.000

Чанк 1 в 10:00:00.500 (15 слов)
  - duration = 0.5s
  - tokens = 15
  - speed = 15 / 0.5 = 30 tok/s

Чанк 2 в 10:00:01.000 (20 слов)
  - duration = 1.0s
  - tokens = 35
  - speed = 35 / 1.0 = 35 tok/s

Завершение в 10:00:01.200
  - duration = 1.2s
  - tokens = 50
  - speed = 50 / 1.2 = 41.67 tok/s
```

## Ограничения

1. **Оценка токенов**: Используется подсчёт слов вместо реального токенизатора
2. **Токены промпта**: Не отслеживаются (требуют данных из ответа API)
3. **Задержка первого токена**: Не отслеживается отдельно

## Возможные улучшения

- Интегрировать tiktoken для точного подсчёта токенов
- Отслеживать time-to-first-token (TTFT)
- Парсить ответ API для получения точного количества токенов
- Добавить оценку стоимости токенов
