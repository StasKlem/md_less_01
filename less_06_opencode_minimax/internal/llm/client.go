package llm

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type LLMProvider interface {
	SendText(ctx context.Context, text string) (string, error)
	SendAudio(ctx context.Context, fileData []byte, fileName string) (string, error)
}

type Client struct {
	apiKey  string
	baseURL string
	model   string
	timeout time.Duration
	client  *http.Client
}

type LLMConfig struct {
	APIKey  string
	BaseURL string
	Model   string
	Timeout time.Duration
}

func NewClient(cfg LLMConfig) *Client {
	return &Client{
		apiKey:  cfg.APIKey,
		baseURL: cfg.BaseURL,
		model:   cfg.Model,
		timeout: cfg.Timeout,
		client: &http.Client{
			Timeout: cfg.Timeout,
		},
	}
}

type ChatMessage struct {
	Role    string     `json:"role"`
	Content string     `json:"content,omitempty"`
	Type    string     `json:"type,omitempty"`
	Image   *ImageData `json:"image_url,omitempty"`
}

type ImageData struct {
	URL string `json:"url"`
}

type ChatRequest struct {
	Model    string        `json:"model"`
	Messages []ChatMessage `json:"messages"`
}

type ChatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func (c *Client) SendText(ctx context.Context, text string) (string, error) {
	prompt := fmt.Sprintf(`Ты ассистент подсчета КБЖУ. Пользователь сообщил о приеме пищи: "%s".
Верни JSON с данными о КБЖУ. Формат ответа:
{"calories": int, "proteins": float, "fats": float, "carbs": float, "food_name": string}

Верни ТОЛЬКО валидный JSON, без дополнительного текста.`, text)

	messages := []ChatMessage{
		{Role: "system", Content: "Ты - ассистент подсчета КБЖУ. Отвечай только валидным JSON."},
		{Role: "user", Content: prompt},
	}

	return c.sendChatRequest(ctx, messages)
}

func (c *Client) SendAudio(ctx context.Context, fileData []byte, fileName string) (string, error) {
	audioBase64 := base64.StdEncoding.EncodeToString(fileData)

	prompt := "Распознай речь из аудио и определи КБЖУ упомянутой еды. Верни JSON: {\"calories\": int, \"proteins\": float, \"fats\": float, \"carbs\": float, \"food_name\": string}. Верни ТОЛЬКО валидный JSON."

	messages := []ChatMessage{
		{Role: "system", Content: "Ты - ассистент подсчета КБЖУ. Распознавай речь и отвечай только валидным JSON."},
		{
			Role:    "user",
			Content: fmt.Sprintf("[Аудиофайл: %s]", fileName),
			Image: &ImageData{
				URL: fmt.Sprintf("data:audio;base64,%s", audioBase64),
			},
		},
		{Role: "user", Content: prompt},
	}

	return c.sendChatRequest(ctx, messages)
}

func (c *Client) sendChatRequest(ctx context.Context, messages []ChatMessage) (string, error) {
	reqBody := ChatRequest{
		Model:    c.model,
		Messages: messages,
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var chatResp ChatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no choices in response")
	}

	content := chatResp.Choices[0].Message.Content
	content = strings.TrimSpace(content)

	jsonStart := strings.Index(content, "{")
	jsonEnd := strings.LastIndex(content, "}")
	if jsonStart != -1 && jsonEnd != -1 {
		content = content[jsonStart : jsonEnd+1]
	}

	return content, nil
}
