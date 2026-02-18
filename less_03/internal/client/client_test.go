package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"llm-client/internal/chat"
	"llm-client/internal/logger"
)

func TestNewClient(t *testing.T) {
	t.Run("default client", func(t *testing.T) {
		c := NewClient("http://localhost:11434", "/v1/chat/completions")

		if c.baseURL != "http://localhost:11434" {
			t.Errorf("baseURL = %q, want %q", c.baseURL, "http://localhost:11434")
		}
		if c.apiEndpoint != "v1/chat/completions" {
			t.Errorf("apiEndpoint = %q, want %q", c.apiEndpoint, "v1/chat/completions")
		}
		if c.httpClient == nil {
			t.Errorf("httpClient should not be nil")
		}
	})

	t.Run("with trailing slash", func(t *testing.T) {
		c := NewClient("http://localhost:11434/", "/v1/chat/completions")
		if c.baseURL != "http://localhost:11434" {
			t.Errorf("baseURL should have trailing slash removed")
		}
	})

	t.Run("with leading slash in endpoint", func(t *testing.T) {
		c := NewClient("http://localhost:11434", "/v1/chat/completions")
		if c.apiEndpoint != "v1/chat/completions" {
			t.Errorf("apiEndpoint should have leading slash removed")
		}
	})
}

func TestNewClient_Options(t *testing.T) {
	t.Run("with HTTP client", func(t *testing.T) {
		httpClient := &http.Client{Timeout: 30 * time.Second}
		c := NewClient("http://localhost:11434", "/v1/chat", WithHTTPClient(httpClient))

		if c.httpClient != httpClient {
			t.Errorf("httpClient was not set")
		}
	})

	t.Run("with timeout", func(t *testing.T) {
		timeout := 60 * time.Second
		c := NewClient("http://localhost:11434", "/v1/chat", WithTimeout(timeout))

		if c.timeout != timeout {
			t.Errorf("timeout = %v, want %v", c.timeout, timeout)
		}
		if c.httpClient.Timeout != timeout {
			t.Errorf("httpClient.Timeout = %v, want %v", c.httpClient.Timeout, timeout)
		}
	})

	t.Run("with logger", func(t *testing.T) {
		log := logger.NewLogger(logger.Config{Enabled: false})
		c := NewClient("http://localhost:11434", "/v1/chat", WithLogger(log))

		if c.logger != log {
			t.Errorf("logger was not set")
		}
	})

	t.Run("with API key", func(t *testing.T) {
		c := NewClient("http://localhost:11434", "/v1/chat", WithAPIKey("test-key"))

		if c.apiKey != "test-key" {
			t.Errorf("apiKey = %q, want %q", c.apiKey, "test-key")
		}
	})
}

func TestClient_Chat_Success(t *testing.T) {
	expectedResponse := "Hello! How can I help you?"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("Expected POST, got %s", r.Method)
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Expected Content-Type: application/json")
		}

		resp := ChatResponse{
			ID:      "test-id",
			Object:  "chat.completion",
			Created: time.Now().Unix(),
			Model:   "test-model",
			Choices: []struct {
				Index        int          `json:"index"`
				Delta        chat.Message `json:"delta"`
				Message      chat.Message `json:"message"`
				FinishReason string       `json:"finish_reason"`
			}{
				{
					Index: 0,
					Delta: chat.Message{
						Role:    chat.RoleAssistant,
						Content: expectedResponse,
					},
					FinishReason: "stop",
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions")

	ctx := context.Background()
	req := &ChatRequest{
		Model: "test-model",
		Messages: []chat.Message{
			{Role: chat.RoleUser, Content: "Hello"},
		},
		Temperature: 0.7,
	}

	response, err := c.Chat(ctx, req)
	if err != nil {
		t.Fatalf("Chat() error = %v", err)
	}

	if response != expectedResponse {
		t.Errorf("response = %q, want %q", response, expectedResponse)
	}
}

func TestClient_Chat_EmptyChoices(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := ChatResponse{
			ID:      "test-id",
			Object:  "chat.completion",
			Created: time.Now().Unix(),
			Model:   "test-model",
			Choices: []struct {
				Index        int          `json:"index"`
				Delta        chat.Message `json:"delta"`
				Message      chat.Message `json:"message"`
				FinishReason string       `json:"finish_reason"`
			}{},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions")

	ctx := context.Background()
	req := &ChatRequest{
		Model:    "test-model",
		Messages: []chat.Message{{Role: chat.RoleUser, Content: "Hello"}},
	}

	_, err := c.Chat(ctx, req)
	if err == nil {
		t.Errorf("Chat() should return error for empty choices")
	}
}

func TestClient_Chat_ErrorStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error": "Invalid API key"}`))
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions")

	ctx := context.Background()
	req := &ChatRequest{
		Model:    "test-model",
		Messages: []chat.Message{{Role: chat.RoleUser, Content: "Hello"}},
	}

	_, err := c.Chat(ctx, req)
	if err == nil {
		t.Errorf("Chat() should return error for non-200 status")
	}
}

func TestClient_Chat_ContextCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Имитируем долгий запрос
		<-r.Context().Done()
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions", WithTimeout(100*time.Millisecond))

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Отменяем сразу

	req := &ChatRequest{
		Model:    "test-model",
		Messages: []chat.Message{{Role: chat.RoleUser, Content: "Hello"}},
	}

	_, err := c.Chat(ctx, req)
	if err == nil {
		t.Errorf("Chat() should return error when context is cancelled")
	}
}

func TestClient_ChatStream_Success(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Connection", "keep-alive")

		// Отправляем несколько чанков
		chunks := []string{"Hello", " ", "world", "!"}
		for _, chunk := range chunks {
			resp := ChatResponse{
				Choices: []struct {
					Index        int          `json:"index"`
					Delta        chat.Message `json:"delta"`
					Message      chat.Message `json:"message"`
					FinishReason string       `json:"finish_reason"`
				}{
					{
						Delta: chat.Message{
							Role:    chat.RoleAssistant,
							Content: chunk,
						},
					},
				},
			}
			data, _ := json.Marshal(resp)
			w.Write([]byte("data: " + string(data) + "\n\n"))
			w.(http.Flusher).Flush()
		}

		// Сигнал конца
		w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions")

	ctx := context.Background()
	req := &ChatRequest{
		Model:    "test-model",
		Messages: []chat.Message{{Role: chat.RoleUser, Content: "Hello"}},
		Stream:   true,
	}

	ch := c.ChatStream(ctx, req)

	var result strings.Builder
	done := false

	for chunk := range ch {
		if chunk.Done {
			done = true
			continue
		}
		if chunk.Error != nil {
			t.Fatalf("Stream chunk error: %v", chunk.Error)
		}
		result.WriteString(chunk.Content)
	}

	if !done {
		t.Errorf("Stream should end with Done signal")
	}

	expected := "Hello world!"
	if result.String() != expected {
		t.Errorf("result = %q, want %q", result.String(), expected)
	}
}

func TestClient_ChatStream_ContextCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Отправляем один чанк и ждём
		resp := ChatResponse{
			Choices: []struct {
				Index        int          `json:"index"`
				Delta        chat.Message `json:"delta"`
				Message      chat.Message `json:"message"`
				FinishReason string       `json:"finish_reason"`
			}{
				{
					Delta: chat.Message{Content: "test"},
				},
			},
		}
		data, _ := json.Marshal(resp)
		w.Write([]byte("data: " + string(data) + "\n\n"))
		w.(http.Flusher).Flush()

		// Ждём отмены контекста
		<-r.Context().Done()
	}))
	defer server.Close()

	c := NewClient(server.URL, "/v1/chat/completions")

	ctx, cancel := context.WithCancel(context.Background())
	req := &ChatRequest{
		Model:    "test-model",
		Messages: []chat.Message{{Role: chat.RoleUser, Content: "Hello"}},
		Stream:   true,
	}

	ch := c.ChatStream(ctx, req)

	// Получаем первый чанк
	<-ch

	// Отменяем контекст
	cancel()

	// Проверяем что стрим завершился
	select {
	case <-ch:
		// OK
	case <-time.After(time.Second):
		t.Errorf("Stream should close after context cancellation")
	}
}

func TestClient_ParseStreamData(t *testing.T) {
	c := NewClient("http://localhost:11434", "/v1/chat")

	t.Run("parse single chunk", func(t *testing.T) {
		data := []byte("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n")
		chunks := c.parseStreamData(data)

		if len(chunks) != 1 {
			t.Fatalf("Expected 1 chunk, got %d", len(chunks))
		}
		if chunks[0].Content != "Hello" {
			t.Errorf("Content = %q, want %q", chunks[0].Content, "Hello")
		}
	})

	t.Run("parse done signal", func(t *testing.T) {
		data := []byte("data: [DONE]\n")
		chunks := c.parseStreamData(data)

		if len(chunks) != 1 {
			t.Fatalf("Expected 1 chunk, got %d", len(chunks))
		}
		if !chunks[0].Done {
			t.Errorf("Chunk should be Done")
		}
	})

	t.Run("parse finish reason", func(t *testing.T) {
		data := []byte("data: {\"choices\":[{\"delta\":{\"content\":\"!\"},\"finish_reason\":\"stop\"}]}\n")
		chunks := c.parseStreamData(data)

		if len(chunks) != 2 {
			t.Fatalf("Expected 2 chunks (content + done), got %d", len(chunks))
		}
		if !chunks[1].Done {
			t.Errorf("Second chunk should be Done")
		}
	})

	t.Run("ignore comments", func(t *testing.T) {
		data := []byte(": comment\ndata: {\"choices\":[{\"delta\":{\"content\":\"test\"}}]}\n")
		chunks := c.parseStreamData(data)

		if len(chunks) != 1 {
			t.Fatalf("Expected 1 chunk, got %d", len(chunks))
		}
	})

	t.Run("ignore empty lines", func(t *testing.T) {
		data := []byte("\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"test\"}}]}\n\n")
		chunks := c.parseStreamData(data)

		if len(chunks) != 1 {
			t.Fatalf("Expected 1 chunk, got %d", len(chunks))
		}
	})
}

func TestClient_SetHeaders(t *testing.T) {
	t.Run("with API key", func(t *testing.T) {
		c := NewClient("http://localhost:11434", "/v1/chat", WithAPIKey("test-key"))

		req, _ := http.NewRequest("POST", c.getEndpoint(), nil)
		c.setHeaders(req)

		if req.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Content-Type = %q, want %q", req.Header.Get("Content-Type"), "application/json")
		}
		if req.Header.Get("Authorization") != "Bearer test-key" {
			t.Errorf("Authorization = %q, want %q", req.Header.Get("Authorization"), "Bearer test-key")
		}
	})

	t.Run("without API key", func(t *testing.T) {
		c := NewClient("http://localhost:11434", "/v1/chat")

		req, _ := http.NewRequest("POST", c.getEndpoint(), nil)
		c.setHeaders(req)

		if req.Header.Get("Authorization") != "" {
			t.Errorf("Authorization should be empty")
		}
	})
}

func TestClient_Getters(t *testing.T) {
	c := NewClient("http://localhost:11434", "/v1/chat/completions")

	if c.GetBaseURL() != "http://localhost:11434" {
		t.Errorf("GetBaseURL() = %q, want %q", c.GetBaseURL(), "http://localhost:11434")
	}
	if c.GetAPIEndpoint() != "v1/chat/completions" {
		t.Errorf("GetAPIEndpoint() = %q, want %q", c.GetAPIEndpoint(), "v1/chat/completions")
	}
}

func TestChatRequest_Marshal(t *testing.T) {
	req := &ChatRequest{
		Model: "test-model",
		Messages: []chat.Message{
			{Role: chat.RoleSystem, Content: "You are helpful"},
			{Role: chat.RoleUser, Content: "Hello"},
		},
		Stream:      true,
		Temperature: 0.7,
		TopP:        0.9,
		MaxTokens:   100,
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}

	var unmarshaled ChatRequest
	if err := json.Unmarshal(data, &unmarshaled); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}

	if unmarshaled.Model != req.Model {
		t.Errorf("Model = %q, want %q", unmarshaled.Model, req.Model)
	}
	if len(unmarshaled.Messages) != len(req.Messages) {
		t.Errorf("Messages count = %d, want %d", len(unmarshaled.Messages), len(req.Messages))
	}
	if unmarshaled.Stream != req.Stream {
		t.Errorf("Stream = %v, want %v", unmarshaled.Stream, req.Stream)
	}
}
