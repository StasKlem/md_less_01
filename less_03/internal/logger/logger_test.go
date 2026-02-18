package logger

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseLevel(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected Level
	}{
		{"debug", "debug", LevelDebug},
		{"info", "info", LevelInfo},
		{"warn", "warn", LevelWarn},
		{"warning", "warning", LevelWarn},
		{"error", "error", LevelError},
		{"DEBUG uppercase", "DEBUG", LevelDebug},
		{"INFO uppercase", "INFO", LevelInfo},
		{"unknown defaults to info", "unknown", LevelInfo},
		{"empty defaults to info", "", LevelInfo},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ParseLevel(tt.input)
			if got != tt.expected {
				t.Errorf("ParseLevel(%q) = %v, want %v", tt.input, got, tt.expected)
			}
		})
	}
}

func TestLevel_ToSlogLevel(t *testing.T) {
	tests := []struct {
		name     string
		level    Level
		expected slog.Level
	}{
		{"debug", LevelDebug, slog.LevelDebug},
		{"info", LevelInfo, slog.LevelInfo},
		{"warn", LevelWarn, slog.LevelWarn},
		{"error", LevelError, slog.LevelError},
		{"unknown defaults to info", "", slog.LevelInfo},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.level.ToSlogLevel()
			if got != tt.expected {
				t.Errorf("Level.ToSlogLevel() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestNewLogger_Disabled(t *testing.T) {
	l := NewLogger(Config{
		Enabled: false,
		Level:   LevelInfo,
	})

	if l.Enabled() {
		t.Errorf("Logger should be disabled")
	}
}

func TestNewLogger_Enabled(t *testing.T) {
	// Создаём временный файл
	tmpDir := t.TempDir()
	logFile := filepath.Join(tmpDir, "test.log")

	l := NewLogger(Config{
		Enabled:  true,
		FilePath: logFile,
		Level:    LevelDebug,
	})

	if !l.Enabled() {
		t.Errorf("Logger should be enabled")
	}

	// Пишем сообщение
	l.Info("test message", "key", "value")
	l.Close()

	// Проверяем что файл создан и содержит данные
	content, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatalf("Failed to read log file: %v", err)
	}

	if len(content) == 0 {
		t.Errorf("Log file should not be empty")
	}
}

func TestNewLogger_DirectoryPath(t *testing.T) {
	tmpDir := t.TempDir()

	l := NewLogger(Config{
		Enabled:  true,
		FilePath: tmpDir, // Передаём директорию, не файл
		Level:    LevelInfo,
	})

	if !l.Enabled() {
		t.Errorf("Logger should be enabled")
	}

	l.Info("test message")
	l.Close()

	// Проверяем что файл создан в директории
	logFile := filepath.Join(tmpDir, "llm-client.log")
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		t.Errorf("Log file should be created in directory")
	}
}

func TestLogger_With(t *testing.T) {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	l := &Logger{
		logger: slog.New(handler),
		config: Config{Enabled: true, Level: LevelDebug},
	}

	// Создаём логгер с атрибутами
	l2 := l.With("user_id", "123", "session", "abc")
	l2.Info("test message")

	// Проверяем что атрибуты добавлены
	var entry map[string]any
	if err := json.Unmarshal(buf.Bytes(), &entry); err != nil {
		t.Fatalf("Failed to parse log entry: %v", err)
	}

	if entry["user_id"] != "123" {
		t.Errorf("user_id = %v, want 123", entry["user_id"])
	}
	if entry["session"] != "abc" {
		t.Errorf("session = %v, want abc", entry["session"])
	}
}

func TestLogger_WithGroup(t *testing.T) {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	l := &Logger{
		logger: slog.New(handler),
		config: Config{Enabled: true, Level: LevelDebug},
	}

	l2 := l.WithGroup("http")
	l2.Debug("request", "method", "GET")

	// Проверяем что группа добавлена
	content := buf.String()
	if !strings.Contains(content, "http") {
		t.Errorf("Log should contain group name 'http'")
	}
}

func TestLogger_ContextMethods(t *testing.T) {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	l := &Logger{
		logger: slog.New(handler),
		config: Config{Enabled: true, Level: LevelDebug},
	}

	ctx := context.Background()

	l.DebugContext(ctx, "debug message", "key", "value")
	l.InfoContext(ctx, "info message")
	l.WarnContext(ctx, "warn message")
	l.ErrorContext(ctx, "error message", "error", "test error")

	// Проверяем что все сообщения записаны
	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 4 {
		t.Errorf("Expected 4 log entries, got %d", len(lines))
	}
}

func TestLogger_JSONFormat(t *testing.T) {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	l := &Logger{
		logger: slog.New(handler),
		config: Config{Enabled: true, Level: LevelDebug},
	}

	l.Info("test message", "string_key", "value", "int_key", 42, "bool_key", true)

	// Проверяем что вывод валидный JSON
	var entry map[string]any
	if err := json.Unmarshal(buf.Bytes(), &entry); err != nil {
		t.Fatalf("Log output should be valid JSON: %v", err)
	}

	if entry["msg"] != "test message" {
		t.Errorf("msg = %v, want 'test message'", entry["msg"])
	}
	if entry["string_key"] != "value" {
		t.Errorf("string_key = %v, want 'value'", entry["string_key"])
	}
	if intVal, ok := entry["int_key"].(float64); !ok || intVal != 42 {
		t.Errorf("int_key = %v, want 42", entry["int_key"])
	}
	if entry["bool_key"] != true {
		t.Errorf("bool_key = %v, want true", entry["bool_key"])
	}
}

func TestDefaultLogger(t *testing.T) {
	// Проверяем что DefaultLogger существует
	if DefaultLogger == nil {
		t.Errorf("DefaultLogger should not be nil")
	}

	// По умолчанию логгер отключен
	if DefaultLogger.Enabled() {
		t.Errorf("DefaultLogger should be disabled by default")
	}
}

func TestSetDefault(t *testing.T) {
	newLogger := NewLogger(Config{Enabled: true, Level: LevelDebug})
	SetDefault(newLogger)

	if DefaultLogger != newLogger {
		t.Errorf("DefaultLogger should be updated")
	}

	// Возвращаем оригинальный логгер
	SetDefault(NewLogger(Config{Enabled: false}))
}

func TestGlobalFunctions(t *testing.T) {
	// Создаём тестовый логгер и устанавливаем как default
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	testLogger := &Logger{
		logger: slog.New(handler),
		config: Config{Enabled: true, Level: LevelDebug},
	}
	SetDefault(testLogger)

	// Тестируем глобальные функции
	Debug("debug msg")
	Info("info msg", "key", "val")
	Warn("warn msg")
	Error("error msg", "err", "test")

	// Проверяем что сообщения записаны
	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 4 {
		t.Errorf("Expected 4 log entries, got %d", len(lines))
	}

	// Возвращаем оригинальный логгер
	SetDefault(NewLogger(Config{Enabled: false}))
}

func TestLogger_Close(t *testing.T) {
	l := NewLogger(Config{Enabled: false})
	err := l.Close()
	if err != nil {
		t.Errorf("Close() should not return error: %v", err)
	}
}
