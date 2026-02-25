# Задание #7

Агент теперь может сохранять контекст и подхватывать его после перезапуска приложения.

---

## Подсчёт токенов

Приложение поддерживает подсчёт токенов на трёх уровнях:

### 1. Токены текущего запроса

Для каждого запроса к модели отображаются:
- **Prompt Tokens** — количество токенов во входном сообщении (ваш запрос + история диалога + системный промпт)
- **Completion Tokens** — количество токенов в ответе модели
- **Total Tokens** — сумма prompt + completion

**Откуда берутся данные:**
- API LLM (Ollama, OpenAI, LM Studio) возвращает объект `usage` в ответе
- Для streaming-режима данные приходят в последнем чанке
- Для non-streaming режима данные приходят сразу в ответе

### 2. Токены ответа модели

Токены ответа (completion tokens) сохраняются:
- В каждом сообщении (`Message.completionTokens`)
- В истории диалога (накапливаются при сохранении контекста)
- В метриках текущего запроса (отображаются в реальном времени)

### 3. Токены всей истории диалога

Накапливаются в течение сессии:
- **Conversation Prompt Tokens** — сумма всех prompt tokens за все запросы
- **Conversation Completion Tokens** — сумма всех completion tokens за все ответы
- **Conversation Total Tokens** — общая сумма токенов диалога

**Важно:**
- Счётчики диалога сбрасываются при нажатии "Clear Chat"
- При сохранении контекста токены сохраняются вместе с сообщениями
- При перезапуске приложения токены подхватываются из сохранённых сообщений

---

## Архитектура подсчёта токенов

```
┌─────────────────────────────────────────────────────────────┐
│                     API Response (usage)                    │
│  { prompt_tokens: 50, completion_tokens: 100, total: 150 }  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    LLMAPIClient.swift                       │
│  Извлекает usage из ответа API                              │
│  Возвращает (promptTokens, completionTokens, totalTokens)   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                 SendMessageUseCase.swift                    │
│  Получает токены от API клиента                             │
│  Передаёт в событии .completed(...)                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   ChatViewModel.swift                       │
│  Обрабатывает .completed событие                            │
│  Вызывает metricsViewModel.completeRequest(...)             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  MetricsViewModel.swift                     │
│  currentMetrics — метрики текущего запроса                  │
│  conversationPromptTokens — накапливает prompt токены       │
│  conversationCompletionTokens — накапливает completion      │
│  Отправляет событие .metricsUpdated                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              MetricsPanelViewController.swift               │
│  Отображает все метрики в UI                                │
│  - Current Request (prompt, completion, total, speed)       │
│  - Conversation Total (prompt, completion, total)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Структуры данных

### Message
```swift
struct Message {
    var promptTokens: Int?      // токены запроса
    var completionTokens: Int?  // токены ответа
    var totalTokens: Int?       // общие токены
}
```

### RequestMetrics
```swift
struct RequestMetrics {
    // Текущий запрос
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    var tokensPerSecond: Double
    var requestDuration: TimeInterval
    
    // История диалога
    var conversationPromptTokens: Int
    var conversationCompletionTokens: Int
    var conversationTotalTokens: Int
}
```

---

## Пример ответа API

```json
{
  "id": "chatcmpl-123",
  "choices": [...],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 100,
    "total_tokens": 150
  }
}
```

---

## Отображение в UI

MetricsPanel показывает:

```
Model: llama3.2

Current Request:
• Prompt: 50 tok
• Completion: 100 tok
• Total: 150 tok
• Speed: 45.2 tok/s
• Duration: 2.2s

Conversation Total:
• Prompt: 250 tok
• Completion: 480 tok
• Total: 730 tok
```

