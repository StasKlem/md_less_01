// Package logger предоставляет структурированный логгер на основе slog.
package logger

import (
	"context"
	"io"
	"log/slog"
	"os"
	"strings"
)

// Logger структурированный логгер приложения.
type Logger struct {
	*slog.Logger
}

// New создает новый логгер с указанными настройками.
// level - уровень логирования (debug, info, warn, error)
// format - формат вывода (json, text)
// output - выходной поток (по умолчанию os.Stdout)
func New(level string, format string, output io.Writer) *Logger {
	if output == nil {
		output = os.Stdout
	}

	// Парсинг уровня логирования
	var logLevel slog.Level
	switch strings.ToLower(level) {
	case "debug":
		logLevel = slog.LevelDebug
	case "info":
		logLevel = slog.LevelInfo
	case "warn":
		logLevel = slog.LevelWarn
	case "error":
		logLevel = slog.LevelError
	default:
		logLevel = slog.LevelInfo
	}

	// Создание обработчика в зависимости от формата
	var handler slog.Handler
	opts := &slog.HandlerOptions{
		Level: logLevel,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			// Убираем время из логов для тестов
			if a.Key == slog.TimeKey {
				return slog.Attr{}
			}
			return a
		},
	}

	switch strings.ToLower(format) {
	case "json":
		handler = slog.NewJSONHandler(output, opts)
	default:
		handler = slog.NewTextHandler(output, opts)
	}

	return &Logger{
		Logger: slog.New(handler),
	}
}

// NewDefault создает логгер с настройками по умолчанию (text format, info level).
func NewDefault() *Logger {
	return New("info", "text", os.Stdout)
}

// WithContext добавляет контекст к логгеру.
// Примечание: slog.Logger не поддерживает контекст напрямую,
// метод оставлен для совместимости интерфейсов.
func (l *Logger) WithContext(ctx context.Context) *Logger {
	// В slog контекст используется только при логировании
	// Для совместимости возвращаем тот же логгер
	return l
}

// With добавляет атрибуты к логгеру.
func (l *Logger) With(attrs ...any) *Logger {
	return &Logger{
		Logger: l.Logger.With(attrs...),
	}
}

// Debug логирует сообщение на уровне DEBUG.
func (l *Logger) Debug(msg string, args ...any) {
	l.Logger.Debug(msg, args...)
}

// Info логирует сообщение на уровне INFO.
func (l *Logger) Info(msg string, args ...any) {
	l.Logger.Info(msg, args...)
}

// Warn логирует сообщение на уровне WARN.
func (l *Logger) Warn(msg string, args ...any) {
	l.Logger.Warn(msg, args...)
}

// Error логирует сообщение на уровне ERROR.
func (l *Logger) Error(msg string, args ...any) {
	l.Logger.Error(msg, args...)
}

// LogAttrs логирует сообщение с атрибутами.
func (l *Logger) LogAttrs(level slog.Level, msg string, attrs ...slog.Attr) {
	l.Logger.LogAttrs(context.Background(), level, msg, attrs...)
}
