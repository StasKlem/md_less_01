package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

// ChatRequestBuilder создает HTTP запросы к API чата
// Immutable: параметры устанавливаются только при создании
type ChatRequestBuilder struct {
	apiKey            string
	url               string
	model             string
	maxTokens         int
	stopSequences     []string
	formatDescription string
	responseFormat    *ResponseFormat
}

// NewRequestBuilder создает новый builder с базовыми параметрами
// apiKey - ключ API для авторизации
// url - endpoint API
// model - название модели (например, "deepseek/deepseek-v3.2")
// maxTokens - максимальное количество токенов в ответе
func NewRequestBuilder(apiKey, url, model string, maxTokens int) *ChatRequestBuilder {
	return &ChatRequestBuilder{
		apiKey:    apiKey,
		url:       url,
		model:     model,
		maxTokens: maxTokens,
	}
}

// NewRequestBuilderWithOptions создает builder со всеми параметрами
// stopSequences - последовательности для остановки генерации
// formatDescription - системное сообщение с инструкциями
func NewRequestBuilderWithOptions(
	apiKey string,
	url string,
	model string,
	maxTokens int,
	stopSequences []string,
	formatDescription string,
) *ChatRequestBuilder {
	return &ChatRequestBuilder{
		apiKey:            apiKey,
		url:               url,
		model:             model,
		maxTokens:         maxTokens,
		stopSequences:     stopSequences,
		formatDescription: formatDescription,
	}
}

// Build создает HTTP POST запрос к API
// userMessage - сообщение пользователя для отправки
// Возвращает: HTTP запрос с заголовками Authorization и Content-Type
func (b *ChatRequestBuilder) Build(userMessage string) (*http.Request, error) {
	messages := []Message{}

	// Добавляем системное сообщение с инструкциями, если задано
	if b.formatDescription != "" {
		messages = append(messages, Message{
			Role:    "system",
			Content: b.formatDescription,
		})
	}

	// Добавляем сообщение пользователя
	messages = append(messages, Message{
		Role:    "user",
		Content: userMessage,
	})

	reqBody := Request{
		Model:          b.model,
		Messages:       messages,
		MaxTokens:      b.maxTokens,
		ResponseFormat: b.responseFormat,
	}

	if len(b.stopSequences) > 0 {
		reqBody.Stop = b.stopSequences
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("ошибка маршалинга JSON: %w", err)
	}

	req, err := http.NewRequest("POST", b.url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("ошибка создания запроса: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+b.apiKey)

	return req, nil
}
