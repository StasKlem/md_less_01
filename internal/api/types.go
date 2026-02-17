// Package api содержит типы, интерфейсы и реализацию для работы с API чата
package api

// Request представляет структуру запроса к API chat completions
type Request struct {
	Model          string          `json:"model"`
	Messages       []Message       `json:"messages"`
	MaxTokens      int             `json:"max_tokens,omitempty"`
	Stop           []string        `json:"stop,omitempty"`
	ResponseFormat *ResponseFormat `json:"response_format,omitempty"`
}

// ResponseFormat представляет формат ответа (text или json_object)
type ResponseFormat struct {
	Type       string      `json:"type"`
	JSONSchema *JSONSchema `json:"json_schema,omitempty"`
}

// JSONSchema представляет JSON схему для структурированного вывода
// Используется когда Type = "json_schema"
type JSONSchema struct {
	Name   string                 `json:"name"`
	Strict bool                   `json:"strict"`
	Schema map[string]interface{} `json:"schema"`
}

// Message представляет одно сообщение в чате
type Message struct {
	Role    string `json:"role"`    // Роль отправителя: "system", "user", "assistant"
	Content string `json:"content"` // Текст сообщения
}

// Response представляет структуру ответа от API
type Response struct {
	Choices []Choice `json:"choices"`
}

// Choice представляет один вариант ответа от API
type Choice struct {
	Message Message `json:"message"`
}

// ChatResult содержит результат выполнения запроса
type ChatResult struct {
	Response *Response
	Duration int64 // в миллисекундах
}
