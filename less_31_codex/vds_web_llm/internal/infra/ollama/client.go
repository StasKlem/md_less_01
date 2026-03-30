package ollama

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"vds_web_llm/internal/domain"
)

type Config struct {
	BaseURL string
	Model   string
	Timeout time.Duration
}

type Client struct {
	baseURL string
	model   string
	http    *http.Client
}

func NewClient(cfg Config) *Client {
	timeout := cfg.Timeout
	if timeout <= 0 {
		timeout = 60 * time.Second
	}
	return &Client{
		baseURL: strings.TrimRight(cfg.BaseURL, "/"),
		model:   cfg.Model,
		http: &http.Client{
			Timeout: timeout,
		},
	}
}

func (c *Client) Health(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/tags", nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
	return fmt.Errorf("ollama health failed: %s: %s", resp.Status, strings.TrimSpace(string(body)))
}

func (c *Client) Chat(ctx context.Context, model string, messages []domain.Message, temperature float64) (domain.Message, error) {
	if model == "" {
		model = c.model
	}

	payload := chatRequest{
		Model:       model,
		Messages:    messages,
		Stream:      false,
		Temperature: temperature,
	}
	buf, err := json.Marshal(payload)
	if err != nil {
		return domain.Message{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/api/chat", bytes.NewReader(buf))
	if err != nil {
		return domain.Message{}, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return domain.Message{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return domain.Message{}, fmt.Errorf("ollama chat failed: %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}

	var out chatResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return domain.Message{}, err
	}
	return domain.Message{
		Role:    "assistant",
		Content: out.Message.Content,
	}, nil
}

type chatRequest struct {
	Model       string           `json:"model"`
	Messages    []domain.Message `json:"messages"`
	Stream      bool             `json:"stream"`
	Temperature float64          `json:"temperature,omitempty"`
}

type chatResponse struct {
	Message domain.Message `json:"message"`
}
