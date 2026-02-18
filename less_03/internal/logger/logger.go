// Package logger предоставляет структурированное логирование для приложения LLM Chat Client.
// Использует стандартный пакет log/slog для логирования с уровнями и контекстом.
package logger

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

// Level определяет уровень логирования
type Level string

const (
	// LevelDebug - отладочные сообщения
	LevelDebug Level = "debug"
	// LevelInfo - информационные сообщения
	LevelInfo Level = "info"
	// LevelWarn - предупреждения
	LevelWarn Level = "warn"
	// LevelError - ошибки
	LevelError Level = "error"
)

// ParseLevel парсит строку в уровень логирования
func ParseLevel(s string) Level {
	switch strings.ToLower(s) {
	case "debug":
		return LevelDebug
	case "info":
		return LevelInfo
	case "warn", "warning":
		return LevelWarn
	case "error":
		return LevelError
	default:
		return LevelInfo
	}
}

// ToSlogLevel конвертирует Level в slog.Level
func (l Level) ToSlogLevel() slog.Level {
	switch l {
	case LevelDebug:
		return slog.LevelDebug
	case LevelInfo:
		return slog.LevelInfo
	case LevelWarn:
		return slog.LevelWarn
	case LevelError:
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// Config содержит конфигурацию логгера
type Config struct {
	// Enabled указывает включено ли логирование
	Enabled bool
	// FilePath путь к файлу логов
	FilePath string
	// Level уровень логирования
	Level Level
	// AddSource добавлять ли информацию об исходном коде
	AddSource bool
}

// Logger обёртка над slog.Logger для удобства
type Logger struct {
	logger *slog.Logger
	config Config
}

// DefaultLogger логгер по умолчанию (отключён)
var DefaultLogger *Logger

func init() {
	DefaultLogger = NewLogger(Config{
		Enabled: false,
		Level:   LevelInfo,
	})
}

// NewLogger создаёт новый логгер с заданной конфигурацией
func NewLogger(cfg Config) *Logger {
	var handler slog.Handler
	var output io.Writer = io.Discard

	if cfg.Enabled && cfg.FilePath != "" {
		// Если указан каталог, создаём файл в нём
		if info, err := os.Stat(cfg.FilePath); err == nil && info.IsDir() {
			cfg.FilePath = filepath.Join(cfg.FilePath, "llm-client.log")
		}

		// Создаём директорию если не существует
		dir := filepath.Dir(cfg.FilePath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			// Если не удалось создать директорию, отключаем логирование
			cfg.Enabled = false
		} else {
			// Открываем файл для записи
			f, err := os.OpenFile(cfg.FilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				cfg.Enabled = false
			} else {
				output = f
			}
		}
	}

	opts := &slog.HandlerOptions{
		Level:     cfg.Level.ToSlogLevel(),
		AddSource: cfg.AddSource,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			// Убираем время из логов если не нужно
			if a.Key == slog.TimeKey {
				return a
			}
			return a
		},
	}

	handler = slog.NewJSONHandler(output, opts)

	return &Logger{
		logger: slog.New(handler),
		config: cfg,
	}
}

// SetDefault устанавливает логгер по умолчанию
func SetDefault(l *Logger) {
	DefaultLogger = l
}

// Logger возвращает базовый slog.Logger
func (l *Logger) Logger() *slog.Logger {
	return l.logger
}

// Enabled возвращает включён ли логгер
func (l *Logger) Enabled() bool {
	return l.config.Enabled
}

// Debug записывает отладочное сообщение
func (l *Logger) Debug(msg string, args ...any) {
	l.logger.Debug(msg, args...)
}

// DebugContext записывает отладочное сообщение с контекстом
func (l *Logger) DebugContext(ctx context.Context, msg string, args ...any) {
	l.logger.DebugContext(ctx, msg, args...)
}

// Info записывает информационное сообщение
func (l *Logger) Info(msg string, args ...any) {
	l.logger.Info(msg, args...)
}

// InfoContext записывает информационное сообщение с контекстом
func (l *Logger) InfoContext(ctx context.Context, msg string, args ...any) {
	l.logger.InfoContext(ctx, msg, args...)
}

// Warn записывает предупреждение
func (l *Logger) Warn(msg string, args ...any) {
	l.logger.Warn(msg, args...)
}

// WarnContext записывает предупреждение с контекстом
func (l *Logger) WarnContext(ctx context.Context, msg string, args ...any) {
	l.logger.WarnContext(ctx, msg, args...)
}

// Error записывает ошибку
func (l *Logger) Error(msg string, args ...any) {
	l.logger.Error(msg, args...)
}

// ErrorContext записывает ошибку с контекстом
func (l *Logger) ErrorContext(ctx context.Context, msg string, args ...any) {
	l.logger.ErrorContext(ctx, msg, args...)
}

// With создаёт новый логгер с добавленными атрибутами
func (l *Logger) With(args ...any) *Logger {
	return &Logger{
		logger: l.logger.With(args...),
		config: l.config,
	}
}

// WithGroup создаёт новый логгер с группой атрибутов
func (l *Logger) WithGroup(name string) *Logger {
	return &Logger{
		logger: l.logger.WithGroup(name),
		config: l.config,
	}
}

// Close закрывает логгер (освобождает ресурсы)
func (l *Logger) Close() error {
	// В текущей реализации ничего не делаем
	// Файлы закрываются автоматически при завершении программы
	return nil
}

// === Глобальные функции для удобства ===

// Debug записывает отладочное сообщение в логгер по умолчанию
func Debug(msg string, args ...any) {
	DefaultLogger.Debug(msg, args...)
}

// Info записывает информационное сообщение в логгер по умолчанию
func Info(msg string, args ...any) {
	DefaultLogger.Info(msg, args...)
}

// Warn записывает предупреждение в логгер по умолчанию
func Warn(msg string, args ...any) {
	DefaultLogger.Warn(msg, args...)
}

// Error записывает ошибку в логгер по умолчанию
func Error(msg string, args ...any) {
	DefaultLogger.Error(msg, args...)
}

// With создаёт новый логгер с атрибутами
func With(args ...any) *Logger {
	return DefaultLogger.With(args...)
}
