package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"vds_web_llm/internal/app"
	"vds_web_llm/internal/config"
	"vds_web_llm/internal/infra/httpapi"
	"vds_web_llm/internal/infra/ollama"
	"vds_web_llm/internal/infra/ratelimit"
)

func main() {
	cfg, err := config.LoadFromEnv()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	upstream := ollama.NewClient(ollama.Config{
		BaseURL: cfg.OllamaURL,
		Model:   cfg.OllamaModel,
		Timeout: cfg.RequestTimeout,
	})

	limiter := ratelimit.NewFixedWindowLimiter(cfg.RateLimitPerMinute, time.Minute)
	service := app.NewService(app.Dependencies{
		Upstream:        upstream,
		Limiter:         limiter,
		APIKey:          cfg.APIKey,
		MaxContextToken: cfg.MaxContextTokens,
		DefaultModel:    cfg.OllamaModel,
		RequestTimeout:  cfg.RequestTimeout,
	})

	handler := httpapi.NewHandler(service, httpapi.Options{
		APIKey:     cfg.APIKey,
		MaxBody:    cfg.MaxBodyBytes,
		RequestNow: time.Now,
		RemoteAddr: httpapi.RemoteAddressFromRequest,
	})

	server := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Printf("listening on %s", cfg.ListenAddr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("shutdown signal: %s", sig)
	case err := <-errCh:
		log.Fatalf("server error: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("shutdown: %v", err)
	}
}
