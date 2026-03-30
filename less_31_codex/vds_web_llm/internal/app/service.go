package app

import (
	"context"
	"fmt"
	"strings"
	"time"

	"vds_web_llm/internal/domain"
)

type Upstream interface {
	Health(ctx context.Context) error
	Chat(ctx context.Context, model string, messages []domain.Message, temperature float64) (domain.Message, error)
}

type Limiter interface {
	Allow(key string, now time.Time) bool
}

type Dependencies struct {
	Upstream        Upstream
	Limiter         Limiter
	APIKey          string
	MaxContextToken int
	DefaultModel    string
	RequestTimeout  time.Duration
}

type Service struct {
	upstream       Upstream
	limiter        Limiter
	apiKey         string
	maxContext     int
	defaultModel   string
	requestTimeout time.Duration
}

func NewService(deps Dependencies) *Service {
	return &Service{
		upstream:       deps.Upstream,
		limiter:        deps.Limiter,
		apiKey:         deps.APIKey,
		maxContext:     deps.MaxContextToken,
		defaultModel:   deps.DefaultModel,
		requestTimeout: deps.RequestTimeout,
	}
}

func (s *Service) Authenticate(key string) error {
	if key == "" || key != s.apiKey {
		return domain.ErrUnauthorized
	}
	return nil
}

func (s *Service) Health(ctx context.Context) error {
	ctx, cancel := s.withTimeout(ctx)
	defer cancel()

	if err := s.upstream.Health(ctx); err != nil {
		return fmt.Errorf("%w: %v", domain.ErrUpstreamFailure, err)
	}
	return nil
}

func (s *Service) Chat(ctx context.Context, apiKey string, limiterKey string, input domain.ChatInput) (domain.ChatResult, error) {
	if err := s.authenticateAndLimit(apiKey, limiterKey); err != nil {
		return domain.ChatResult{}, err
	}

	messages := sanitizeMessages(input.Messages)
	if len(messages) == 0 {
		return domain.ChatResult{}, domain.ErrInvalidRequest
	}

	estimated := domain.EstimateTokens(messages)
	if estimated > s.maxContext {
		return domain.ChatResult{}, domain.ErrContextExceeded
	}

	ctx, cancel := s.withTimeout(ctx)
	defer cancel()

	model := input.Model
	if model == "" {
		model = s.defaultModel
	}

	reply, err := s.upstream.Chat(ctx, model, messages, input.Temperature)
	if err != nil {
		return domain.ChatResult{}, fmt.Errorf("%w: %v", domain.ErrUpstreamFailure, err)
	}

	return domain.ChatResult{
		Model:           model,
		Message:         reply,
		InputTokens:     estimated,
		OutputTokens:    domain.EstimateTokens([]domain.Message{reply}),
		EstimatedTokens: estimated,
	}, nil
}

func (s *Service) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if s.requestTimeout <= 0 {
		return context.WithCancel(ctx)
	}
	return context.WithTimeout(ctx, s.requestTimeout)
}

func (s *Service) authenticateAndLimit(apiKey string, limiterKey string) error {
	if err := s.Authenticate(apiKey); err != nil {
		return err
	}
	if limiterKey == "" {
		limiterKey = apiKey
	}
	if s.limiter != nil && !s.limiter.Allow(limiterKey, time.Now()) {
		return domain.ErrRateLimited
	}
	return nil
}

func sanitizeMessages(messages []domain.Message) []domain.Message {
	cleaned := make([]domain.Message, 0, len(messages))
	for _, msg := range messages {
		role := strings.TrimSpace(msg.Role)
		content := strings.TrimSpace(msg.Content)
		if role == "" || content == "" {
			continue
		}
		cleaned = append(cleaned, domain.Message{Role: role, Content: content})
	}
	return cleaned
}
