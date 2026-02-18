// Package config предоставляет конфигурацию приложения с поддержкой JSON файлов,
// переменных окружения и валидацией параметров.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	apperrors "llm-client/internal/errors"
)

// ServerConfig содержит настройки подключения к серверу
type ServerConfig struct {
	// Address - адрес LLM сервера
	Address string `mapstructure:"address" json:"address"`
	// APIEndpoint - эндпоинт для запросов
	APIEndpoint string `mapstructure:"api_endpoint" json:"api_endpoint"`
}

// ModelConfig содержит настройки модели
type ModelConfig struct {
	// Name - имя модели
	Name string `mapstructure:"name" json:"name"`
	// SystemPrompt - системный промпт
	SystemPrompt string `mapstructure:"system_prompt" json:"system_prompt"`
	// Temperature - температура генерации (0.0-2.0)
	Temperature float64 `mapstructure:"temperature" json:"temperature"`
	// TopP - параметр top_p (0.0-1.0)
	TopP float64 `mapstructure:"top_p" json:"top_p"`
	// MaxTokens - максимальное количество токенов в ответе
	MaxTokens int `mapstructure:"max_tokens" json:"max_tokens"`
	// Stream - использовать ли потоковый режим
	Stream bool `mapstructure:"stream" json:"stream"`
}

// UIConfig содержит настройки пользовательского интерфейса
type UIConfig struct {
	// ShowTimestamps - показывать время в логах
	ShowTimestamps bool `mapstructure:"show_timestamps" json:"show_timestamps"`
	// Theme - тема оформления (light/dark)
	Theme string `mapstructure:"theme" json:"theme"`
	// ScrollSpeed - скорость скролла
	ScrollSpeed int `mapstructure:"scroll_speed" json:"scroll_speed"`
}

// LogConfig содержит настройки логирования
type LogConfig struct {
	// Enabled - включено ли логирование
	Enabled bool `mapstructure:"enabled" json:"enabled"`
	// FilePath - путь к файлу логов
	FilePath string `mapstructure:"file_path" json:"file_path"`
	// Level - уровень логирования (debug, info, warn, error)
	Level string `mapstructure:"level" json:"level"`
	// LogRequests - логировать HTTP запросы
	LogRequests bool `mapstructure:"log_requests" json:"log_requests"`
	// LogResponses - логировать HTTP ответы
	LogResponses bool `mapstructure:"log_responses" json:"log_responses"`
	// LogStreamChunks - логировать чанки стрима
	LogStreamChunks bool `mapstructure:"log_stream_chunks" json:"log_stream_chunks"`
}

// Config содержит полную конфигурацию приложения
type Config struct {
	// Server - настройки сервера
	Server ServerConfig `mapstructure:"server" json:"server"`
	// Model - настройки модели
	Model ModelConfig `mapstructure:"model" json:"model"`
	// UI - настройки интерфейса
	UI UIConfig `mapstructure:"ui" json:"ui"`
	// Log - настройки логирования
	Log LogConfig `mapstructure:"log" json:"log"`
}

// EnvConfigPrefix префикс для переменных окружения
const EnvConfigPrefix = "LLM_CLIENT"

// DefaultConfig возвращает конфигурацию со значениями по умолчанию
func DefaultConfig() *Config {
	return &Config{
		Server: ServerConfig{
			Address:     "http://localhost:11434",
			APIEndpoint: "/v1/chat/completions",
		},
		Model: ModelConfig{
			Name:         "llama3",
			SystemPrompt: "You are a helpful assistant.",
			Temperature:  0.7,
			TopP:         0.9,
			MaxTokens:    0,
			Stream:       true,
		},
		UI: UIConfig{
			ShowTimestamps: false,
			Theme:          "dark",
			ScrollSpeed:    10,
		},
		Log: LogConfig{
			Enabled:         false,
			FilePath:        "",
			Level:           "info",
			LogRequests:     true,
			LogResponses:    true,
			LogStreamChunks: false,
		},
	}
}

// Load загружает конфигурацию из файла и переменных окружения
func Load(path string) (*Config, error) {
	cfg := DefaultConfig()

	// Если путь не указан, ищем в стандартных местах
	if path == "" {
		path = findConfigFile()
	}

	// Если файл найден, загружаем его
	if path != "" {
		if err := loadFromFile(path, cfg); err != nil {
			return nil, err
		}
	}

	// Переопределяем из переменных окружения
	if err := loadFromEnv(cfg); err != nil {
		return nil, err
	}

	// Валидируем конфигурацию
	if err := cfg.Validate(); err != nil {
		return nil, apperrors.NewValidationError("INVALID_CONFIG", "configuration validation failed", err)
	}

	return cfg, nil
}

// findConfigFile ищет файл конфигурации в стандартных местах
func findConfigFile() string {
	// Проверяем переменную окружения
	if path := os.Getenv(EnvConfigPrefix + "_CONFIG"); path != "" {
		return path
	}

	// Проверяем стандартные места
	homeDir, err := os.UserHomeDir()
	if err == nil {
		// ~/.llm-client/config.json
		configPath := filepath.Join(homeDir, ".llm-client", "config.json")
		if _, err := os.Stat(configPath); err == nil {
			return configPath
		}
	}

	// Проверяем текущую директорию
	if _, err := os.Stat("config.json"); err == nil {
		return "config.json"
	}

	return ""
}

// loadFromFile загружает конфигурацию из JSON файла
func loadFromFile(path string, cfg *Config) error {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // Файл не существует, используем дефолт
		}
		return apperrors.NewConfigError("FILE_READ_ERROR", "failed to read config file", err)
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return apperrors.NewConfigError("PARSE_ERROR", "failed to parse config file", err)
	}

	return nil
}

// loadFromEnv загружает конфигурацию из переменных окружения
func loadFromEnv(cfg *Config) error {
	// Читаем значения напрямую из переменных окружения
	if val := os.Getenv(EnvConfigPrefix + "_ADDRESS"); val != "" {
		cfg.Server.Address = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_API_ENDPOINT"); val != "" {
		cfg.Server.APIEndpoint = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_MODEL"); val != "" {
		cfg.Model.Name = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_SYSTEM_PROMPT"); val != "" {
		cfg.Model.SystemPrompt = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_TEMPERATURE"); val != "" {
		if v, err := parseFloat(val); err == nil {
			cfg.Model.Temperature = v
		}
	}
	if val := os.Getenv(EnvConfigPrefix + "_TOP_P"); val != "" {
		if v, err := parseFloat(val); err == nil {
			cfg.Model.TopP = v
		}
	}
	if val := os.Getenv(EnvConfigPrefix + "_MAX_TOKENS"); val != "" {
		if v, err := strconv.Atoi(val); err == nil {
			cfg.Model.MaxTokens = v
		}
	}
	if val := os.Getenv(EnvConfigPrefix + "_STREAM"); val != "" {
		cfg.Model.Stream = strings.ToLower(val) == "true" || val == "1"
	}
	if val := os.Getenv(EnvConfigPrefix + "_THEME"); val != "" {
		cfg.UI.Theme = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_SCROLL_SPEED"); val != "" {
		if v, err := strconv.Atoi(val); err == nil {
			cfg.UI.ScrollSpeed = v
		}
	}
	if val := os.Getenv(EnvConfigPrefix + "_LOG_ENABLED"); val != "" {
		cfg.Log.Enabled = strings.ToLower(val) == "true" || val == "1"
	}
	if val := os.Getenv(EnvConfigPrefix + "_LOG"); val != "" {
		cfg.Log.FilePath = val
	}
	if val := os.Getenv(EnvConfigPrefix + "_LOG_LEVEL"); val != "" {
		cfg.Log.Level = val
	}

	// Специальная обработка переменной LLM_CLIENT_LOG
	if logPath := os.Getenv("LLM_CLIENT_LOG"); logPath != "" {
		cfg.Log.Enabled = true
		cfg.Log.FilePath = logPath
	}

	return nil
}

// Validate проверяает валидность конфигурации
func (c *Config) Validate() error {
	if c.Server.Address == "" {
		return fmt.Errorf("server.address cannot be empty")
	}

	// Проверяем формат адреса (должен начинаться с http:// или https://)
	if !strings.HasPrefix(c.Server.Address, "http://") && !strings.HasPrefix(c.Server.Address, "https://") {
		return fmt.Errorf("server.address must start with http:// or https://")
	}

	if c.Model.Temperature < 0 || c.Model.Temperature > 2 {
		return fmt.Errorf("model.temperature must be between 0.0 and 2.0, got %f", c.Model.Temperature)
	}

	if c.Model.TopP < 0 || c.Model.TopP > 1 {
		return fmt.Errorf("model.top_p must be between 0.0 and 1.0, got %f", c.Model.TopP)
	}

	if c.Model.Name == "" {
		return fmt.Errorf("model.name cannot be empty")
	}

	validLevels := map[string]bool{"debug": true, "info": true, "warn": true, "error": true}
	if !validLevels[c.Log.Level] {
		return fmt.Errorf("log.level must be one of: debug, info, warn, error, got %q", c.Log.Level)
	}

	if c.UI.Theme != "" && c.UI.Theme != "light" && c.UI.Theme != "dark" {
		return fmt.Errorf("ui.theme must be 'light' or 'dark', got %q", c.UI.Theme)
	}

	if c.UI.ScrollSpeed < 1 || c.UI.ScrollSpeed > 100 {
		return fmt.Errorf("ui.scroll_speed must be between 1 and 100, got %d", c.UI.ScrollSpeed)
	}

	return nil
}

// Save сохраняет конфигурацию в файл
func (c *Config) Save(path string) error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return apperrors.NewConfigError("MARSHAL_ERROR", "failed to marshal config", err)
	}

	// Создаём директорию если не существует
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return apperrors.NewConfigError("MKDIR_ERROR", "failed to create config directory", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return apperrors.NewConfigError("WRITE_ERROR", "failed to write config file", err)
	}

	return nil
}

// CreateDefaultConfigFile создаёт файл конфигурации по умолчанию
func CreateDefaultConfigFile(path string) error {
	cfg := DefaultConfig()
	return cfg.Save(path)
}

// ToJSON возвращает JSON представление конфигурации
func (c *Config) ToJSON() ([]byte, error) {
	return json.MarshalIndent(c, "", "  ")
}

// String возвращает строковое представление конфигурации для отображения
func (c *Config) String() string {
	streamStatus := "batch"
	if c.Model.Stream {
		streamStatus = "stream"
	}
	return fmt.Sprintf("Model: %s | Temp: %.2f | Top_P: %.2f | %s",
		c.Model.Name, c.Model.Temperature, c.Model.TopP, streamStatus)
}

// RuntimeConfig хранит изменяемые во время работы параметры
type RuntimeConfig struct {
	Model        string
	SystemPrompt string
	Temperature  float64
	TopP         float64
	Stream       bool
}

// NewRuntimeConfig создаёт RuntimeConfig из Config
func NewRuntimeConfig(cfg *Config) *RuntimeConfig {
	return &RuntimeConfig{
		Model:        cfg.Model.Name,
		SystemPrompt: cfg.Model.SystemPrompt,
		Temperature:  cfg.Model.Temperature,
		TopP:         cfg.Model.TopP,
		Stream:       cfg.Model.Stream,
	}
}

// SetParam устанавливает параметр во время работы
func (c *RuntimeConfig) SetParam(name, value string) error {
	switch name {
	case "temperature", "temp":
		v, err := parseFloat(value)
		if err != nil {
			return fmt.Errorf("invalid temperature value: %s", value)
		}
		if v < 0 || v > 2 {
			return fmt.Errorf("temperature must be between 0.0 and 2.0")
		}
		c.Temperature = v

	case "top_p", "topp", "top-p":
		v, err := parseFloat(value)
		if err != nil {
			return fmt.Errorf("invalid top_p value: %s", value)
		}
		if v < 0 || v > 1 {
			return fmt.Errorf("top_p must be between 0.0 and 1.0")
		}
		c.TopP = v

	case "model":
		if value == "" {
			return fmt.Errorf("model name cannot be empty")
		}
		c.Model = value

	case "system", "system_prompt", "system-prompt":
		c.SystemPrompt = value

	case "stream":
		v := strings.ToLower(value)
		if v == "true" || v == "1" || v == "on" || v == "yes" {
			c.Stream = true
		} else if v == "false" || v == "0" || v == "off" || v == "no" {
			c.Stream = false
		} else {
			return fmt.Errorf("invalid stream value: %s (use true/false)", value)
		}

	default:
		return fmt.Errorf("unknown parameter: %s", name)
	}

	return nil
}

// parseFloat парсит float64 из строки
func parseFloat(s string) (float64, error) {
	var result float64
	_, err := fmt.Sscanf(s, "%f", &result)
	return result, err
}

// String возвращает строковое представление для отображения
func (c *RuntimeConfig) String() string {
	streamStatus := "stream"
	if !c.Stream {
		streamStatus = "batch"
	}
	return fmt.Sprintf("Model: %s | Temp: %.2f | Top_P: %.2f | %s",
		c.Model, c.Temperature, c.TopP, streamStatus)
}

// ApplyToConfig применяет изменения RuntimeConfig к Config
func (c *RuntimeConfig) ApplyToConfig(cfg *Config) {
	cfg.Model.Name = c.Model
	cfg.Model.SystemPrompt = c.SystemPrompt
	cfg.Model.Temperature = c.Temperature
	cfg.Model.TopP = c.TopP
	cfg.Model.Stream = c.Stream
}
