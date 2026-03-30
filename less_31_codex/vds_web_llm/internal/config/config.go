package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr         string
	OllamaURL          string
	OllamaModel        string
	APIKey             string
	RateLimitPerMinute int
	MaxContextTokens   int
	MaxBodyBytes       int64
	RequestTimeout     time.Duration
}

func LoadFromEnv() (Config, error) {
	cfg := Config{
		ListenAddr:         envOr("LISTEN_ADDR", ":8080"),
		OllamaURL:          envOr("OLLAMA_URL", "http://ollama:11434"),
		OllamaModel:        envOr("OLLAMA_MODEL", "llama3.2"),
		APIKey:             os.Getenv("API_KEY"),
		RateLimitPerMinute: envIntOr("RATE_LIMIT_PER_MINUTE", 60),
		MaxContextTokens:   envIntOr("MAX_CONTEXT_TOKENS", 4096),
		MaxBodyBytes:       int64(envIntOr("MAX_BODY_BYTES", 1<<20)),
		RequestTimeout:     time.Duration(envIntOr("REQUEST_TIMEOUT_SECONDS", 60)) * time.Second,
	}

	if cfg.APIKey == "" {
		return Config{}, errors.New("API_KEY must be set")
	}
	if cfg.RateLimitPerMinute <= 0 {
		return Config{}, fmt.Errorf("RATE_LIMIT_PER_MINUTE must be positive")
	}
	if cfg.MaxContextTokens <= 0 {
		return Config{}, fmt.Errorf("MAX_CONTEXT_TOKENS must be positive")
	}
	if cfg.RequestTimeout <= 0 {
		return Config{}, fmt.Errorf("REQUEST_TIMEOUT_SECONDS must be positive")
	}

	return cfg, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	if value := os.Getenv(key); value != "" {
		parsed, err := strconv.Atoi(value)
		if err == nil {
			return parsed
		}
	}
	return fallback
}
