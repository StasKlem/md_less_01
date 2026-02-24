package logger

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"
)

type Level string

const (
	LevelDebug Level = "debug"
	LevelInfo  Level = "info"
	LevelWarn  Level = "warn"
	LevelError Level = "error"
)

type Logger struct {
	logger *slog.Logger
}

func New(level, format string) *Logger {
	var lvl slog.Level
	switch Level(level) {
	case LevelDebug:
		lvl = slog.LevelDebug
	case LevelInfo:
		lvl = slog.LevelInfo
	case LevelWarn:
		lvl = slog.LevelWarn
	case LevelError:
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}

	var handler slog.Handler
	if format == "json" {
		handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	} else {
		handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	}

	return &Logger{
		logger: slog.New(handler),
	}
}

func (l *Logger) Debug(msg string, args ...any) {
	l.logger.Debug(msg, args...)
}

func (l *Logger) Info(msg string, args ...any) {
	l.logger.Info(msg, args...)
}

func (l *Logger) Warn(msg string, args ...any) {
	l.logger.Warn(msg, args...)
}

func (l *Logger) Error(msg string, args ...any) {
	l.logger.Error(msg, args...)
}

func (l *Logger) With(args ...any) *Logger {
	return &Logger{
		logger: l.logger.With(args...),
	}
}

func (l *Logger) WithContext(ctx context.Context) *Logger {
	return &Logger{
		logger: l.logger.With("request_id", ctx.Value("request_id")),
	}
}

type Loggable interface {
	Log() []any
}

func (l *Logger) InfoContext(ctx context.Context, msg string, args ...any) {
	l.logger.Log(ctx, slog.LevelInfo, msg, args...)
}

func (l *Logger) ErrorContext(ctx context.Context, msg string, args ...any) {
	l.logger.Log(ctx, slog.LevelError, msg, args...)
}

func (l *Logger) WithTime() *Logger {
	return &Logger{
		logger: l.logger.With("time", time.Now().Format(time.RFC3339)),
	}
}

func (l *Logger) FormatError(err error) string {
	return fmt.Sprintf("%+v", err)
}
