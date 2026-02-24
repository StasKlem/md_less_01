package logger

import (
	"context"
	"log/slog"
	"os"
)

type ctxKey string

const (
	TraceIDKey ctxKey = "trace_id"
	UserIDKey  ctxKey = "user_id"
)

func New(level string) *slog.Logger {
	var lvl slog.Level
	switch level {
	case "debug":
		lvl = slog.LevelDebug
	case "info":
		lvl = slog.LevelInfo
	case "warn":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level: lvl,
	}

	handler := slog.NewJSONHandler(os.Stdout, opts)
	logger := slog.New(handler)

	return logger
}

func WithTraceID(ctx context.Context, traceID string) context.Context {
	return context.WithValue(ctx, TraceIDKey, traceID)
}

func WithUserID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, UserIDKey, userID)
}

func GetTraceID(ctx context.Context) string {
	if v, ok := ctx.Value(TraceIDKey).(string); ok {
		return v
	}
	return ""
}

func GetUserID(ctx context.Context) int64 {
	if v, ok := ctx.Value(UserIDKey).(int64); ok {
		return v
	}
	return 0
}

func LogCtx(ctx context.Context, logger *slog.Logger) *slog.Logger {
	l := logger
	if traceID := GetTraceID(ctx); traceID != "" {
		l = l.With("trace_id", traceID)
	}
	if userID := GetUserID(ctx); userID != 0 {
		l = l.With("user_id", userID)
	}
	return l
}
