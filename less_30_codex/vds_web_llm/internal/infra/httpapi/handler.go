package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"vds_web_llm/internal/app"
	"vds_web_llm/internal/domain"
)

type Options struct {
	APIKey     string
	MaxBody    int64
	RequestNow func() time.Time
	RemoteAddr func(*http.Request) string
}

type Handler struct {
	service *app.Service
	opts    Options
	mux     *http.ServeMux
}

func NewHandler(service *app.Service, opts Options) http.Handler {
	h := &Handler{
		service: service,
		opts:    opts,
		mux:     http.NewServeMux(),
	}
	if h.opts.RequestNow == nil {
		h.opts.RequestNow = time.Now
	}
	if h.opts.RemoteAddr == nil {
		h.opts.RemoteAddr = RemoteAddressFromRequest
	}
	h.routes()
	return h
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.opts.MaxBody > 0 && r.Body != nil {
		r.Body = http.MaxBytesReader(w, r.Body, h.opts.MaxBody)
	}
	h.mux.ServeHTTP(w, r)
}

func (h *Handler) routes() {
	h.mux.HandleFunc("/health", h.health)
	h.mux.HandleFunc("/chat", h.chat)
	h.mux.HandleFunc("/v1/chat/completions", h.openAIChat)
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	if err := h.service.Health(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
	})
}

func (h *Handler) chat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	apiKey, err := h.authorize(r)
	if err != nil {
		writeError(w, err)
		return
	}

	var req chatRequest
	if err := decodeJSON(r.Body, &req); err != nil {
		writeError(w, domain.ErrInvalidRequest)
		return
	}

	input := domain.ChatInput{
		Model:       req.Model,
		Messages:    toMessages(req.Messages),
		Temperature: req.Temperature,
	}
	if req.Message != "" {
		input.Messages = append(input.Messages, domain.Message{Role: "user", Content: req.Message})
	}

	result, err := h.service.Chat(r.Context(), apiKey, h.rateLimitKey(r, apiKey), input)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, domain.ChatResponse{
		Answer:           result.Message.Content,
		Model:            result.Model,
		PromptTokens:     result.InputTokens,
		CompletionTokens: result.OutputTokens,
		EstimatedTokens:  result.EstimatedTokens,
		Messages:         []domain.Message{result.Message},
	})
}

func (h *Handler) openAIChat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	apiKey, err := h.authorize(r)
	if err != nil {
		writeError(w, err)
		return
	}

	var req openAIChatRequest
	if err := decodeJSON(r.Body, &req); err != nil {
		writeError(w, domain.ErrInvalidRequest)
		return
	}

	input := domain.ChatInput{
		Model:       req.Model,
		Messages:    toMessages(req.Messages),
		Temperature: req.Temperature,
	}

	result, err := h.service.Chat(r.Context(), apiKey, h.rateLimitKey(r, apiKey), input)
	if err != nil {
		writeError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, openAIChatResponse{
		ID:      "chatcmpl-local",
		Object:  "chat.completion",
		Created: h.opts.RequestNow().Unix(),
		Model:   result.Model,
		Choices: []openAIChoice{{
			Index: 0,
			Message: domain.Message{
				Role:    "assistant",
				Content: result.Message.Content,
			},
			FinishReason: "stop",
		}},
		Usage: usage{
			PromptTokens:     result.InputTokens,
			CompletionTokens: result.OutputTokens,
			TotalTokens:      result.InputTokens + result.OutputTokens,
		},
	})
}

func (h *Handler) authorize(r *http.Request) (string, error) {
	key := apiKeyFromRequest(r)
	if key == "" || key != h.opts.APIKey {
		return "", domain.ErrUnauthorized
	}
	return key, nil
}

func (h *Handler) rateLimitKey(r *http.Request, apiKey string) string {
	remote := ""
	if h.opts.RemoteAddr != nil {
		remote = h.opts.RemoteAddr(r)
	}
	if remote == "" {
		return apiKey
	}
	return apiKey + "|" + remote
}

func apiKeyFromRequest(r *http.Request) string {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(auth), "bearer ") {
		return strings.TrimSpace(auth[7:])
	}
	if key := strings.TrimSpace(r.Header.Get("X-API-Key")); key != "" {
		return key
	}
	return ""
}

func decodeJSON(body io.Reader, v any) error {
	dec := json.NewDecoder(body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, domain.ErrUnauthorized):
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
	case errors.Is(err, domain.ErrRateLimited):
		writeJSON(w, http.StatusTooManyRequests, errorResponse{Error: "rate limit exceeded"})
	case errors.Is(err, domain.ErrContextExceeded):
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "context limit exceeded"})
	case errors.Is(err, domain.ErrInvalidRequest):
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request"})
	default:
		writeJSON(w, http.StatusBadGateway, errorResponse{Error: "upstream failure"})
	}
}

func methodNotAllowed(w http.ResponseWriter) {
	w.Header().Set("Allow", "GET, POST")
	writeJSON(w, http.StatusMethodNotAllowed, errorResponse{Error: "method not allowed"})
}

func toMessages(messages []messageRequest) []domain.Message {
	result := make([]domain.Message, 0, len(messages))
	for _, msg := range messages {
		result = append(result, domain.Message{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}
	return result
}

func RemoteAddressFromRequest(r *http.Request) string {
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		return strings.TrimSpace(parts[0])
	}
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err == nil {
		return host
	}
	return strings.TrimSpace(r.RemoteAddr)
}

type errorResponse struct {
	Error string `json:"error"`
}

type chatRequest struct {
	Model       string           `json:"model"`
	Message     string           `json:"message"`
	Messages    []messageRequest `json:"messages"`
	Temperature float64          `json:"temperature"`
}

type openAIChatRequest struct {
	Model       string           `json:"model"`
	Messages    []messageRequest `json:"messages"`
	Temperature float64          `json:"temperature"`
}

type messageRequest struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIChatResponse struct {
	ID      string         `json:"id"`
	Object  string         `json:"object"`
	Created int64          `json:"created"`
	Model   string         `json:"model"`
	Choices []openAIChoice `json:"choices"`
	Usage   usage          `json:"usage"`
}

type openAIChoice struct {
	Index        int            `json:"index"`
	Message      domain.Message `json:"message"`
	FinishReason string         `json:"finish_reason"`
}

type usage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}
