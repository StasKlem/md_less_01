// Package llm предоставляет интерфейс и реализацию клиента для LLM провайдеров.
package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/stasklem/kbju-bot/internal/domain"
)

// LLMProvider определяет интерфейс для взаимодействия с LLM.
type LLMProvider interface {
	// SendText отправляет текстовое сообщение в LLM и получает ответ с КБЖУ.
	SendText(ctx context.Context, text string) (*domain.KBJUResult, error)
	// SendAudio отправляет аудиофайл в LLM для распознавания и получения КБЖУ.
	SendAudio(ctx context.Context, audioData []byte, mimeType string) (*domain.KBJUResult, error)
}

// ClientConfig содержит настройки LLM клиента.
type ClientConfig struct {
	Provider string
	APIKey   string
	Model    string
	BaseURL  string
	Timeout  time.Duration
}

// client реализует LLMProvider для OpenAI-совместимых API.
type client struct {
	apiKey    string
	model     string
	baseURL   string
	httpClient *http.Client
}

// NewClient создает новый LLM клиент.
func NewClient(cfg ClientConfig) LLMProvider {
	baseURL := cfg.BaseURL
	if baseURL == "" {
		// По умолчанию используем routerai.ru
		baseURL = "https://routerai.ru/api/v1"
	}

	return &client{
		apiKey:  cfg.APIKey,
		model:   cfg.Model,
		baseURL: strings.TrimSuffix(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: cfg.Timeout,
		},
	}
}

// SendText отправляет текстовое сообщение в LLM.
func (c *client) SendText(ctx context.Context, text string) (*domain.KBJUResult, error) {
	// Формируем промпт для извлечения КБЖУ
	prompt := fmt.Sprintf(`Проанализируй описание еды и извлеки данные о КБЖУ (калории, белки, жиры, углеводы).
Верни ТОЛЬКО JSON в следующем формате без какого-либо дополнительного текста:
{"calories": int, "proteins": float, "fats": float, "carbs": float, "food_name": string}

Описание еды: %s

Если данные не могут быть определены точно, используй приблизительные значения для типичной порции.
food_name должен быть кратким названием блюда на русском языке.`, text)

	return c.sendChatRequest(ctx, prompt)
}

// SendAudio отправляет аудиофайл в LLM для распознавания.
func (c *client) SendAudio(ctx context.Context, audioData []byte, mimeType string) (*domain.KBJUResult, error) {
	// Для аудио используем Whisper API для транскрипции, затем отправляем текст
	transcribedText, err := c.transcribeAudio(ctx, audioData, mimeType)
	if err != nil {
		return nil, fmt.Errorf("transcribe audio: %w", err)
	}

	// Отправляем распознанный текст на анализ КБЖУ
	return c.SendText(ctx, transcribedText)
}

// transcribeAudio транскрибирует аудио с помощью Whisper API.
func (c *client) transcribeAudio(ctx context.Context, audioData []byte, mimeType string) (string, error) {
	// Создаем multipart запрос для Whisper API
	body := &strings.Builder{}
	boundary := "----WebKitFormBoundary7MA4YWxkTrZu0gW"

	body.WriteString("--" + boundary + "\r\n")
	body.WriteString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.ogg\"\r\n")
	body.WriteString("Content-Type: " + mimeType + "\r\n\r\n")
	body.Write(audioData)
	body.WriteString("\r\n")
	body.WriteString("--" + boundary + "\r\n")
	body.WriteString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
	body.WriteString("whisper-1\r\n")
	body.WriteString("\r\n")
	body.WriteString("--" + boundary + "\r\n")
	body.WriteString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
	body.WriteString("json\r\n")
	body.WriteString("\r\n")
	body.WriteString("--" + boundary + "--\r\n")

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/audio/transcriptions", strings.NewReader(body.String()))
	if err != nil {
		return "", fmt.Errorf("create transcription request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("execute transcription request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("transcription API error: %s (status: %d)", string(respBody), resp.StatusCode)
	}

	var transcriptionResp struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&transcriptionResp); err != nil {
		return "", fmt.Errorf("decode transcription response: %w", err)
	}

	return transcriptionResp.Text, nil
}

// sendChatRequest отправляет запрос к чат-модели.
func (c *client) sendChatRequest(ctx context.Context, prompt string) (*domain.KBJUResult, error) {
	requestBody := map[string]interface{}{
		"model": c.model,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
		"temperature": 0.1,
		"response_format": map[string]string{"type": "json_object"},
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/chat/completions", strings.NewReader(string(jsonBody)))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("LLM API error: %s (status: %d)", string(respBody), resp.StatusCode)
	}

	var apiResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("empty response from LLM")
	}

	content := apiResp.Choices[0].Message.Content
	return parseKBJUResponse(content)
}

// parseKBJUResponse парсит JSON ответ от LLM.
func parseKBJUResponse(content string) (*domain.KBJUResult, error) {
	// Очищаем ответ от возможных markdown обёрток
	content = strings.TrimSpace(content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var result domain.KBJUResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		return nil, fmt.Errorf("parse KBJU JSON: %w", err)
	}

	// Валидация данных
	if !result.Validate() {
		// Применяем fallback на дефолтные значения
		if result.Calories < 0 {
			result.Calories = 0
		}
		if result.Proteins < 0 {
			result.Proteins = 0
		}
		if result.Fats < 0 {
			result.Fats = 0
		}
		if result.Carbs < 0 {
			result.Carbs = 0
		}
		if result.FoodName == "" {
			result.FoodName = "Неизвестное блюдо"
		}
	}

	return &result, nil
}
