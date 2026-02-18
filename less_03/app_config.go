package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// ServerConfig содержит настройки подключения к серверу
type ServerConfig struct {
	// Address - адрес LLM сервера
	Address string `json:"address"`
	// APIEndpoint - эндпоинт для запросов (по умолчанию /v1/chat/completions)
	APIEndpoint string `json:"api_endpoint"`
}

// ModelConfig содержит настройки модели
type ModelConfig struct {
	// Name - имя модели
	Name string `json:"name"`
	// SystemPrompt - системный промпт
	SystemPrompt string `json:"system_prompt"`
	// Temperature - температура генерации (0.0-2.0)
	Temperature float64 `json:"temperature"`
	// TopP - параметр top_p (0.0-1.0)
	TopP float64 `json:"top_p"`
	// MaxTokens - максимальное количество токенов в ответе (0 = без ограничений)
	MaxTokens int `json:"max_tokens"`
	// Stream - использовать ли потоковый режим (по умолчанию true)
	Stream bool `json:"stream"`
}

// UIConfig содержит настройки пользовательского интерфейса
type UIConfig struct {
	// ShowTimestamps - показывать время в логах
	ShowTimestamps bool `json:"show_timestamps"`
	// Theme - тема оформления (light/dark)
	Theme string `json:"theme"`
	// ScrollSpeed - скорость скролла
	ScrollSpeed int `json:"scroll_speed"`
}

// LogConfig содержит настройки логирования
type LogConfig struct {
	// Enabled - включено ли логирование
	Enabled bool `json:"enabled"`
	// FilePath - путь к файлу логов
	FilePath string `json:"file_path"`
	// Level - уровень логирования (debug, info, warn, error)
	Level string `json:"level"`
	// LogRequests - логировать HTTP запросы
	LogRequests bool `json:"log_requests"`
	// LogResponses - логировать HTTP ответы
	LogResponses bool `json:"log_responses"`
	// LogStreamChunks - логировать чанки стрима
	LogStreamChunks bool `json:"log_stream_chunks"`
}

// AppConfig содержит полную конфигурацию приложения
type AppConfig struct {
	// Server - настройки сервера
	Server ServerConfig `json:"server"`
	// Model - настройки модели
	Model ModelConfig `json:"model"`
	// UI - настройки интерфейса
	UI UIConfig `json:"ui"`
	// Log - настройки логирования
	Log LogConfig `json:"log"`
}

// DefaultConfig возвращает конфигурацию со значениями по умолчанию
func DefaultConfig() *AppConfig {
	return &AppConfig{
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

// LoadConfig загружает конфигурацию из файла
func LoadConfig(path string) (*AppConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			// Файл не существует, возвращаем конфигурацию по умолчанию
			return DefaultConfig(), nil
		}
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	config := DefaultConfig()
	if err := json.Unmarshal(data, config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	return config, nil
}

// SaveConfig сохраняет конфигурацию в файл
func (c *AppConfig) SaveConfig(path string) error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// GetConfigPath возвращает путь к файлу конфигурации
func GetConfigPath() string {
	// Проверяем переменную окружения
	if path := os.Getenv("LLM_CLIENT_CONFIG"); path != "" {
		return path
	}

	// Проверяем стандартные места
	homeDir, err := os.UserHomeDir()
	if err == nil {
		// ~/.llm-client/config.json
		configDir := strings.Join([]string{homeDir, ".llm-client"}, string(os.PathSeparator))
		configPath := strings.Join([]string{configDir, "config.json"}, string(os.PathSeparator))
		
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

// Validate проверяает валидность конфигурации
func (c *AppConfig) Validate() error {
	if c.Server.Address == "" {
		return fmt.Errorf("server.address cannot be empty")
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

	if c.Log.Level != "debug" && c.Log.Level != "info" && c.Log.Level != "warn" && c.Log.Level != "error" {
		return fmt.Errorf("log.level must be one of: debug, info, warn, error")
	}

	return nil
}

// CreateDefaultConfigFile создаёт файл конфигурации по умолчанию
func CreateDefaultConfigFile(path string) error {
	config := DefaultConfig()
	return config.SaveConfig(path)
}

// PrintDefaultConfig выводит конфигурацию по умолчанию в stdout
func PrintDefaultConfig() {
	config := DefaultConfig()
	data, _ := json.MarshalIndent(config, "", "  ")
	fmt.Println(string(data))
}
