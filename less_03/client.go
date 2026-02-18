package main

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
)

// ChatRequest представляет запрос к LLM API (OpenAI-compatible формат)
type ChatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Stream      bool      `json:"stream"`
	Temperature float64   `json:"temperature"`
	TopP        float64   `json:"top_p"`
}

// ChatResponse представляет ответ от LLM API
type ChatResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index        int     `json:"index"`
		Delta        Message `json:"delta"`
		FinishReason string  `json:"finish_reason"`
	} `json:"choices"`
}

// StreamChunk представляет один чанк данных при стриминге
type StreamChunk struct {
	Content string
	Done    bool
	Error   error
}

// Client - HTTP клиент для взаимодействия с LLM
type Client struct {
	baseURL     string
	apiEndpoint string
	httpClient  *http.Client
}

// NewClient создаёт новый клиент для подключения к LLM
func NewClient(baseURL, apiEndpoint string) *Client {
	// Убираем trailing slash если есть
	baseURL = strings.TrimSuffix(baseURL, "/")
	// Убираем leading slash у эндпоинта для консистентности
	apiEndpoint = strings.TrimPrefix(apiEndpoint, "/")

	return &Client{
		baseURL:     baseURL,
		apiEndpoint: apiEndpoint,
		httpClient: &http.Client{
			// Не используем таймаут по умолчанию для стриминга
			// Таймауты могут прервать долгую генерацию
		},
	}
}

// getAPIKey получает API ключ из переменной окружения
func getAPIKey() string {
	return os.Getenv("ROUTERAI_API_KEY")
}

// Chat отправляет запрос к LLM и возвращает полный ответ (без стриминга)
func (c *Client) Chat(ctx context.Context, req *ChatRequest) (string, error) {
	req.Stream = false

	jsonData, err := json.Marshal(req)
	if err != nil {
		LogError("Failed to marshal chat request", err)
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	endpoint := c.baseURL + "/" + c.apiEndpoint
	LogDebug("Sending chat request to %s", endpoint)
	logRequest(req)

	httpReq, err := http.NewRequestWithContext(ctx, "POST", endpoint,
		bytes.NewReader(jsonData))
	if err != nil {
		LogError("Failed to create HTTP request", err)
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	c.setHeaders(httpReq)

	// Логируем полный запрос с заголовками
	logFullRequest(httpReq.Method, httpReq.URL.String(), httpReq.Header, jsonData)

	startTime := time.Now()
	resp, err := c.httpClient.Do(httpReq)
	duration := time.Since(startTime)
	
	if err != nil {
		LogError("HTTP request failed", err)
		logResponseError(err, duration)
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	logResponse(resp, duration)

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		LogError("API returned error status", fmt.Errorf("status %d: %s", resp.StatusCode, string(body)))
		logResponseBody(body)
		return "", fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))
	}

	var chatResp ChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		LogError("Failed to decode API response", err)
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		LogError("API returned empty choices", nil)
		return "", fmt.Errorf("empty response from API")
	}

	LogDebug("Received response with %d choices", len(chatResp.Choices))
	return chatResp.Choices[0].Delta.Content, nil
}

// ChatStream отправляет запрос к LLM и возвращает канал для потокового получения токенов
// Канал закрывается когда генерация завершена или произошла ошибка
func (c *Client) ChatStream(ctx context.Context, req *ChatRequest) <-chan StreamChunk {
	ch := make(chan StreamChunk, 64)

	jsonData, err := json.Marshal(req)
	if err != nil {
		LogError("Failed to marshal stream request", err)
		ch <- StreamChunk{Error: fmt.Errorf("failed to marshal request: %w", err)}
		close(ch)
		return ch
	}

	LogDebug("Sending stream request to %s, stream=%v", c.baseURL+"/"+c.apiEndpoint, req.Stream)
	logRequest(req)

	endpoint := c.baseURL + "/" + c.apiEndpoint
	httpReq, err := http.NewRequestWithContext(ctx, "POST", endpoint,
		bytes.NewReader(jsonData))
	if err != nil {
		LogError("Failed to create HTTP stream request", err)
		ch <- StreamChunk{Error: fmt.Errorf("failed to create request: %w", err)}
		close(ch)
		return ch
	}

	c.setHeaders(httpReq)

	// Логируем полный запрос с заголовками
	logFullRequest(httpReq.Method, httpReq.URL.String(), httpReq.Header, jsonData)

	startTime := time.Now()
	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		LogError("HTTP stream request failed", err)
		logResponseError(err, time.Since(startTime))
		ch <- StreamChunk{Error: fmt.Errorf("request failed: %w", err)}
		close(ch)
		return ch
	}

	// Запускаем горутину для чтения стрима
	go func() {
		defer resp.Body.Close()
		defer close(ch)

		duration := time.Since(startTime)
		logResponse(resp, duration)

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			LogError("Stream API returned error status", fmt.Errorf("status %d: %s", resp.StatusCode, string(body)))
			logResponseBody(body)
			ch <- StreamChunk{Error: fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(body))}
			return
		}

		LogDebug("Stream connection established, reading chunks...")

		// Читаем поток данных (Server-Sent Events формат)
		// Каждая строка начинается с "data: " и содержит JSON
		reader := resp.Body
		buf := make([]byte, 4096)
		bytesRead := 0
		chunksReceived := 0
		var fullResponse strings.Builder

		for {
			select {
			case <-ctx.Done():
				LogInfo("Stream cancelled by context, bytes read: %d, chunks: %d", bytesRead, chunksReceived)
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
					// Логируем чанк
					logStreamChunk(chunk)
					
					// Проверяем сигнал завершения
					if chunk.Done {
						LogInfo("Stream completed, total bytes: %d, chunks: %d, response length: %d",
							bytesRead, chunksReceived, fullResponse.Len())
						// Логируем полный ответ
						if fullResponse.Len() > 0 {
							logFullResponse(fullResponse.String())
						}
						ch <- chunk
						return
					}
					if chunk.Error != nil {
						LogError("Stream chunk error", chunk.Error)
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
					LogError("Stream read error", err)
					ch <- StreamChunk{Error: fmt.Errorf("read error: %w", err)}
				} else {
					LogDebug("Stream ended (EOF), bytes: %d, chunks: %d", bytesRead, chunksReceived)
					// Логируем полный ответ при EOF
					if fullResponse.Len() > 0 {
						logFullResponse(fullResponse.String())
					}
				}
				return
			}
		}
	}()

	return ch
}

// setHeaders устанавливает необходимые HTTP заголовки
func (c *Client) setHeaders(req *http.Request) {
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	apiKey := getAPIKey()
	if apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
		LogDebug("Authorization header set: Bearer %s...", apiKey[:min(8, len(apiKey))])
	} else {
		LogDebug("No API key provided, Authorization header not set")
	}
}

// min возвращает минимальное из двух чисел
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// parseStreamData парсит данные Server-Sent Events формата
// Возвращает слайс чанков с контентом
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

// BuildChatRequest создаёт запрос к API из истории диалога и конфигурации
// Устарела, используйте RuntimeConfig.ToChatRequest
func BuildChatRequest(config interface{}, history *ChatHistory) *ChatRequest {
	return &ChatRequest{
		Model:       "llama3",
		Messages:    history.GetMessages(),
		Stream:      true,
		Temperature: 0.7,
		TopP:        0.9,
	}
}

// === Функции логирования HTTP запросов ===

// logRequest записывает детали запроса в лог в формате JSON
func logRequest(req *ChatRequest) {
	jsonData, err := json.MarshalIndent(req, "", "  ")
	if err != nil {
		Logger.Printf("HTTP REQUEST ERROR: failed to marshal: %v", err)
		return
	}
	Logger.Printf("HTTP REQUEST BODY:\n%s", string(jsonData))
}

// logFullRequest записывает полный HTTP запрос с заголовками
func logFullRequest(method, url string, headers map[string][]string, body []byte) {
	var sb strings.Builder
	sb.WriteString("=== HTTP REQUEST ===\n")
	sb.WriteString(fmt.Sprintf("Method: %s\n", method))
	sb.WriteString(fmt.Sprintf("URL: %s\n", url))
	sb.WriteString("Headers:\n")
	
	// Сортируем ключи для консистентности
	keys := make([]string, 0, len(headers))
	for k := range headers {
		keys = append(keys, k)
	}
	
	for _, key := range keys {
		values := headers[key]
		if key == "Authorization" && len(values) > 0 {
			// Скрываем большую часть токена
			token := values[0]
			if len(token) > 12 {
				token = token[:8] + "..." + token[len(token)-4:]
			}
			sb.WriteString(fmt.Sprintf("  %s: %s\n", key, token))
		} else {
			for _, v := range values {
				sb.WriteString(fmt.Sprintf("  %s: %s\n", key, v))
			}
		}
	}
	
	if len(body) > 0 {
		sb.WriteString("Body:\n")
		// Пробуем отформатировать JSON
		var jsonData interface{}
		if err := json.Unmarshal(body, &jsonData); err == nil {
			formatted, err := json.MarshalIndent(jsonData, "", "  ")
			if err == nil {
				sb.WriteString(string(formatted))
			} else {
				sb.WriteString(string(body))
			}
		} else {
			sb.WriteString(string(body))
		}
	}
	
	sb.WriteString("\n=== END HTTP REQUEST ===")
	Logger.Println(sb.String())
}

// logResponse записывает детали ответа в лог
func logResponse(resp *http.Response, duration time.Duration) {
	Logger.Printf("HTTP RESPONSE: status=%d | duration=%v | content-length=%d",
		resp.StatusCode, duration, resp.ContentLength)
}

// logResponseError записывает ошибку запроса в лог
func logResponseError(err error, duration time.Duration) {
	Logger.Printf("HTTP ERROR: duration=%v | error=%v", duration, err)
}

// logResponseBody записывает тело ответа в лог в формате JSON
func logResponseBody(body []byte) {
	if len(body) == 0 {
		return
	}

	// Пробуем отформатировать JSON красиво
	var jsonData interface{}
	if err := json.Unmarshal(body, &jsonData); err == nil {
		formatted, err := json.MarshalIndent(jsonData, "", "  ")
		if err == nil {
			Logger.Printf("HTTP RESPONSE BODY:\n%s", string(formatted))
			return
		}
	}

	// Если не JSON, логируем как есть
	Logger.Printf("HTTP RESPONSE BODY: %s", string(body))
}

// logStreamChunk записывает полученный чанк стрима в лог
func logStreamChunk(chunk StreamChunk) {
	if chunk.Error != nil {
		Logger.Printf("STREAM CHUNK ERROR: %v", chunk.Error)
		return
	}
	if chunk.Done {
		Logger.Printf("STREAM CHUNK: [DONE]")
		return
	}
	if chunk.Content != "" {
		// Для стрима логируем только первые 50 символов каждого чанка
		content := chunk.Content
		if len(content) > 50 {
			content = content[:50] + "..."
		}
		Logger.Printf("STREAM CHUNK: %q", content)
	}
}

// logFullResponse записывает полный ответ ассистента в лог
func logFullResponse(content string) {
	response := map[string]interface{}{
		"object":   "chat.completion",
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
		Logger.Printf("FULL RESPONSE ERROR: failed to marshal: %v", err)
		return
	}
	Logger.Printf("FULL RESPONSE:\n%s", string(jsonData))
}
