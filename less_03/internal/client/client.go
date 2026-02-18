// Package client предоставляет HTTP-клиент для взаимодействия с LLM API.
// Поддерживает как обычный режим, так и потоковый (streaming) режим получения ответов.
package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"llm-client/internal/chat"
	apperrors "llm-client/internal/errors"
	"llm-client/internal/logger"
)

// ChatRequest представляет запрос к LLM API (OpenAI-compatible формат)
type ChatRequest struct {
	Model       string         `json:"model"`
	Messages    []chat.Message `json:"messages"`
	Stream      bool           `json:"stream"`
	Temperature float64        `json:"temperature"`
	TopP        float64        `json:"top_p"`
	MaxTokens   int            `json:"max_tokens,omitempty"`
}

// ChatResponse представляет ответ от LLM API
type ChatResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index        int          `json:"index"`
		Delta        chat.Message `json:"delta"`
		Message      chat.Message `json:"message"`
		FinishReason string       `json:"finish_reason"`
	} `json:"choices"`
}

// StreamChunk представляет один чанк данных при стриминге
type StreamChunk struct {
	Content string
	Done    bool
	Error   error
}

// ClientOption - функция опция для настройки клиента
type ClientOption func(*Client)

// WithHTTPClient устанавливает кастомный HTTP клиент
func WithHTTPClient(httpClient *http.Client) ClientOption {
	return func(c *Client) {
		c.httpClient = httpClient
	}
}

// WithTimeout устанавливает таймаут для запросов
func WithTimeout(timeout time.Duration) ClientOption {
	return func(c *Client) {
		c.timeout = timeout
	}
}

// WithLogger устанавливает логгер для клиента
func WithLogger(log *logger.Logger) ClientOption {
	return func(c *Client) {
		c.logger = log
	}
}

// WithAPIKey устанавливает API ключ
func WithAPIKey(apiKey string) ClientOption {
	return func(c *Client) {
		c.apiKey = apiKey
	}
}

// Client - HTTP клиент для взаимодействия с LLM
type Client struct {
	baseURL     string
	apiEndpoint string
	httpClient  *http.Client
	timeout     time.Duration
	apiKey      string
	logger      *logger.Logger
}

// NewClient создаёт новый клиент для подключения к LLM
func NewClient(baseURL, apiEndpoint string, opts ...ClientOption) *Client {
	// Убираем trailing slash если есть
	baseURL = strings.TrimSuffix(baseURL, "/")
	// Убираем leading slash у эндпоинта для консистентности
	apiEndpoint = strings.TrimPrefix(apiEndpoint, "/")

	client := &Client{
		baseURL:     baseURL,
		apiEndpoint: apiEndpoint,
		httpClient: &http.Client{
			Timeout: 0, // По умолчанию без таймаута для стриминга
		},
		logger: logger.DefaultLogger,
	}

	// Применяем опции
	for _, opt := range opts {
		opt(client)
	}

	// Если API ключ не установлен через опцию, пробуем получить из окружения
	if client.apiKey == "" {
		client.apiKey = getAPIKey()
	}

	// Если таймаут установлен, применяем его к HTTP клиенту
	if client.timeout > 0 {
		client.httpClient.Timeout = client.timeout
	}

	return client
}

// getAPIKey получает API ключ из переменной окружения
func getAPIKey() string {
	return os.Getenv("ROUTERAI_API_KEY")
}

// getEndpoint возвращает полный URL эндпоинта
func (c *Client) getEndpoint() string {
	return c.baseURL + "/" + c.apiEndpoint
}

// Chat отправляет запрос к LLM и возвращает полный ответ (без стриминга)
func (c *Client) Chat(ctx context.Context, req *ChatRequest) (string, error) {
	req.Stream = false

	jsonData, err := json.Marshal(req)
	if err != nil {
		c.logger.Error("Failed to marshal chat request", "error", err)
		return "", apperrors.NewInternalError("MARSHAL_ERROR", "failed to marshal request", err)
	}

	c.logRequest(req, jsonData)

	resp, body, err := c.doRequest(ctx, jsonData)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	c.logResponse(resp, body)

	if resp.StatusCode != http.StatusOK {
		return "", c.handleErrorResponse(resp, body)
	}

	var chatResp ChatResponse
	if err := json.Unmarshal(body, &chatResp); err != nil {
		c.logger.Error("Failed to decode API response", "error", err)
		return "", apperrors.NewInternalError("UNMARSHAL_ERROR", "failed to decode response", err)
	}

	if len(chatResp.Choices) == 0 {
		c.logger.Error("API returned empty choices")
		return "", apperrors.NewAPIError("EMPTY_CHOICES", "empty response from API", nil, resp.StatusCode)
	}

	// Получаем контент из ответа
	content := chatResp.Choices[0].Delta.Content
	if content == "" {
		content = chatResp.Choices[0].Message.Content
	}

	c.logger.Debug("Received response", "content_length", len(content))
	return content, nil
}

// ChatStream отправляет запрос к LLM и возвращает канал для потокового получения токенов
func (c *Client) ChatStream(ctx context.Context, req *ChatRequest) <-chan StreamChunk {
	ch := make(chan StreamChunk, 64)

	jsonData, err := json.Marshal(req)
	if err != nil {
		c.logger.Error("Failed to marshal stream request", "error", err)
		ch <- StreamChunk{Error: apperrors.NewInternalError("MARSHAL_ERROR", "failed to marshal request", err)}
		close(ch)
		return ch
	}

	c.logRequest(req, jsonData)

	// Создаем HTTP запрос с контекстом
	httpReq, err := http.NewRequestWithContext(ctx, "POST", c.getEndpoint(), bytes.NewReader(jsonData))
	if err != nil {
		c.logger.Error("Failed to create HTTP request", "error", err)
		ch <- StreamChunk{Error: apperrors.NewInternalError("REQUEST_ERROR", "failed to create request", err)}
		close(ch)
		return ch
	}

	c.setHeaders(httpReq)

	// Выполняем запрос
	startTime := time.Now()
	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		c.logger.Error("HTTP stream request failed", "error", err, "duration", time.Since(startTime))
		ch <- StreamChunk{Error: apperrors.NewNetworkError("REQUEST_FAILED", "request failed", err)}
		close(ch)
		return ch
	}

	// Запускаем горутину для чтения стрима
	go func() {
		defer resp.Body.Close()
		defer close(ch)

		c.logResponse(resp, nil)

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			c.logger.Error("Stream API returned error status", "status", resp.StatusCode, "body", string(body))
			ch <- StreamChunk{Error: c.handleErrorResponse(resp, body)}
			return
		}

		c.logger.Debug("Stream connection established")

		// Читаем поток данных
		c.readStream(ctx, resp.Body, ch)
	}()

	return ch
}

// readStream читает поток данных из ответа
func (c *Client) readStream(ctx context.Context, reader io.Reader, ch chan<- StreamChunk) {
	buf := make([]byte, 4096)
	bytesRead := 0
	chunksReceived := 0
	var fullResponse strings.Builder

	for {
		select {
		case <-ctx.Done():
			c.logger.Info("Stream cancelled by context", "bytes_read", bytesRead, "chunks", chunksReceived)
			ch <- StreamChunk{Done: true}
			return
		default:
		}

		n, err := reader.Read(buf)
		if n > 0 {
			bytesRead += n
			chunks := c.parseStreamData(buf[:n])
			for _, chunk := range chunks {
				chunksReceived++

				if chunk.Done {
					c.logger.Info("Stream completed", "bytes", bytesRead, "chunks", chunksReceived, "response_length", fullResponse.Len())
					if fullResponse.Len() > 0 {
						c.logFullResponse(fullResponse.String())
					}
					ch <- chunk
					return
				}
				if chunk.Error != nil {
					c.logger.Error("Stream chunk error", "error", chunk.Error)
					ch <- chunk
					return
				}
				if chunk.Content != "" {
					fullResponse.WriteString(chunk.Content)
					ch <- chunk
				}
			}
		}

		if err != nil {
			if err != io.EOF {
				c.logger.Error("Stream read error", "error", err)
				ch <- StreamChunk{Error: apperrors.NewStreamError("READ_ERROR", "read error", err)}
			} else {
				c.logger.Debug("Stream ended (EOF)", "bytes", bytesRead, "chunks", chunksReceived)
				if fullResponse.Len() > 0 {
					c.logFullResponse(fullResponse.String())
				}
			}
			return
		}
	}
}

// setHeaders устанавливает необходимые HTTP заголовки
func (c *Client) setHeaders(req *http.Request) {
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
		c.logger.Debug("Authorization header set")
	} else {
		c.logger.Debug("No API key provided")
	}
}

// doRequest выполняет HTTP запрос и возвращает ответ
func (c *Client) doRequest(ctx context.Context, jsonData []byte) (*http.Response, []byte, error) {
	httpReq, err := http.NewRequestWithContext(ctx, "POST", c.getEndpoint(), bytes.NewReader(jsonData))
	if err != nil {
		c.logger.Error("Failed to create HTTP request", "error", err)
		return nil, nil, apperrors.NewInternalError("REQUEST_ERROR", "failed to create request", err)
	}

	c.setHeaders(httpReq)

	startTime := time.Now()
	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		c.logger.Error("HTTP request failed", "error", err, "duration", time.Since(startTime))
		return nil, nil, apperrors.NewNetworkError("REQUEST_FAILED", "request failed", err)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		c.logger.Error("Failed to read response body", "error", err)
		return resp, nil, apperrors.NewInternalError("READ_ERROR", "failed to read response", err)
	}

	return resp, body, nil
}

// handleErrorResponse обрабатывает ошибку от API
func (c *Client) handleErrorResponse(resp *http.Response, body []byte) error {
	c.logger.Error("API error", "status", resp.StatusCode, "body", string(body))
	return apperrors.NewAPIError(
		"API_ERROR",
		fmt.Sprintf("API error (status %d)", resp.StatusCode),
		nil,
		resp.StatusCode,
	).WithContext("body", string(body))
}

// parseStreamData парсит данные Server-Sent Events формата
func (c *Client) parseStreamData(data []byte) []StreamChunk {
	var chunks []StreamChunk

	lines := bytes.Split(data, []byte("\n"))
	for _, line := range lines {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}

		// Пропускаем комментарии
		if bytes.HasPrefix(line, []byte(":")) {
			continue
		}

		// Ожидаем формат "data: {...}"
		if !bytes.HasPrefix(line, []byte("data: ")) {
			continue
		}

		jsonData := bytes.TrimPrefix(line, []byte("data: "))

		// Проверяем сигнал конца потока
		if string(jsonData) == "[DONE]" {
			chunks = append(chunks, StreamChunk{Done: true})
			return chunks
		}

		// Парсим JSON ответа
		var resp ChatResponse
		if err := json.Unmarshal(jsonData, &resp); err != nil {
			// Игнорируем ошибки парсинга отдельных чанков
			continue
		}

		// Извлекаем контент из чанка
		if len(resp.Choices) > 0 {
			content := resp.Choices[0].Delta.Content
			if content == "" {
				content = resp.Choices[0].Message.Content
			}
			if content != "" {
				chunks = append(chunks, StreamChunk{Content: content})
			}
			// Проверяем завершение генерации
			if resp.Choices[0].FinishReason != "" && resp.Choices[0].FinishReason != "null" {
				chunks = append(chunks, StreamChunk{Done: true})
			}
		}
	}

	return chunks
}

// logRequest записывает детали запроса в лог
func (c *Client) logRequest(req *ChatRequest, jsonData []byte) {
	c.logger.Info("Sending request",
		"endpoint", c.getEndpoint(),
		"model", req.Model,
		"messages_count", len(req.Messages),
		"stream", req.Stream,
	)

	c.logger.Debug("Request body", "body", string(jsonData))
}

// logResponse записывает детали ответа в лог
func (c *Client) logResponse(resp *http.Response, body []byte) {
	c.logger.Info("Received response",
		"status", resp.StatusCode,
		"content_length", resp.ContentLength,
	)

	if body != nil {
		c.logger.Debug("Response body", "body", string(body))
	}
}

// logFullResponse записывает полный ответ ассистента в лог
func (c *Client) logFullResponse(content string) {
	response := map[string]interface{}{
		"object": "chat.completion",
		"choices": []map[string]interface{}{
			{
				"index": 0,
				"message": map[string]string{
					"role":    "assistant",
					"content": content,
				},
				"finish_reason": "stop",
			},
		},
	}

	jsonData, err := json.MarshalIndent(response, "", "  ")
	if err != nil {
		c.logger.Error("Failed to marshal full response", "error", err)
		return
	}
	c.logger.Info("Full response", "body", string(jsonData))
}

// GetBaseURL возвращает базовый URL клиента
func (c *Client) GetBaseURL() string {
	return c.baseURL
}

// GetAPIEndpoint возвращает эндпоинт API
func (c *Client) GetAPIEndpoint() string {
	return c.apiEndpoint
}
