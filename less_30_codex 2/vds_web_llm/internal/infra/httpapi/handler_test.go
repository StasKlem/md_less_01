package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"vds_web_llm/internal/app"
	"vds_web_llm/internal/domain"
	"vds_web_llm/internal/infra/ratelimit"
)

type mockUpstream struct {
	healthErr error
	reply     domain.Message
	calls     int
}

func (m *mockUpstream) Health(ctx context.Context) error {
	return m.healthErr
}

func (m *mockUpstream) Chat(ctx context.Context, model string, messages []domain.Message, temperature float64) (domain.Message, error) {
	m.calls++
	return m.reply, nil
}

func newTestHandler(limit int, maxTokens int, upstream *mockUpstream) http.Handler {
	svc := app.NewService(app.Dependencies{
		Upstream:        upstream,
		Limiter:         ratelimit.NewFixedWindowLimiter(limit, time.Minute),
		APIKey:          "secret",
		MaxContextToken: maxTokens,
		DefaultModel:    "llama3.2",
		RequestTimeout:  5 * time.Second,
	})
	return NewHandler(svc, Options{
		APIKey:     "secret",
		MaxBody:    1 << 20,
		RequestNow: func() time.Time { return time.Unix(123, 0) },
	})
}

func TestChatUnauthorized(t *testing.T) {
	upstream := &mockUpstream{reply: domain.Message{Role: "assistant", Content: "ok"}}
	h := newTestHandler(10, 100, upstream)

	req := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewBufferString(`{"message":"hello"}`))
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestChatRateLimit(t *testing.T) {
	upstream := &mockUpstream{reply: domain.Message{Role: "assistant", Content: "ok"}}
	h := newTestHandler(1, 100, upstream)

	body := `{"message":"hello"}`
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewBufferString(body))
		req.Header.Set("Authorization", "Bearer secret")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if i == 0 && rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		if i == 1 && rec.Code != http.StatusTooManyRequests {
			t.Fatalf("expected 429, got %d", rec.Code)
		}
	}
}

func TestChatContextLimit(t *testing.T) {
	upstream := &mockUpstream{reply: domain.Message{Role: "assistant", Content: "ok"}}
	h := newTestHandler(10, 1, upstream)

	req := httptest.NewRequest(http.MethodPost, "/chat", bytes.NewBufferString(`{"message":"this is too long"}`))
	req.Header.Set("Authorization", "Bearer secret")
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	if upstream.calls != 0 {
		t.Fatalf("expected no upstream calls, got %d", upstream.calls)
	}
}

func TestOpenAIChatResponse(t *testing.T) {
	upstream := &mockUpstream{reply: domain.Message{Role: "assistant", Content: "hello"}}
	h := newTestHandler(10, 100, upstream)

	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", bytes.NewBufferString(`{
		"model":"llama3.2",
		"messages":[{"role":"user","content":"say hi"}]
	}`))
	req.Header.Set("Authorization", "Bearer secret")
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["object"] != "chat.completion" {
		t.Fatalf("unexpected object: %v", resp["object"])
	}
}
