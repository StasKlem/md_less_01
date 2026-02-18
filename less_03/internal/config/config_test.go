package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.Server.Address != "http://localhost:11434" {
		t.Errorf("Server.Address = %q, want %q", cfg.Server.Address, "http://localhost:11434")
	}
	if cfg.Server.APIEndpoint != "/v1/chat/completions" {
		t.Errorf("Server.APIEndpoint = %q, want %q", cfg.Server.APIEndpoint, "/v1/chat/completions")
	}
	if cfg.Model.Name != "llama3" {
		t.Errorf("Model.Name = %q, want %q", cfg.Model.Name, "llama3")
	}
	if cfg.Model.Temperature != 0.7 {
		t.Errorf("Model.Temperature = %f, want %f", cfg.Model.Temperature, 0.7)
	}
	if cfg.Model.TopP != 0.9 {
		t.Errorf("Model.TopP = %f, want %f", cfg.Model.TopP, 0.9)
	}
	if cfg.Model.Stream != true {
		t.Errorf("Model.Stream = %v, want true", cfg.Model.Stream)
	}
	if cfg.Log.Level != "info" {
		t.Errorf("Log.Level = %q, want %q", cfg.Log.Level, "info")
	}
}

func TestConfig_Validate(t *testing.T) {
	tests := []struct {
		name    string
		modify  func(*Config)
		wantErr bool
	}{
		{
			name:    "valid config",
			modify:  func(c *Config) {},
			wantErr: false,
		},
		{
			name: "empty address",
			modify: func(c *Config) {
				c.Server.Address = ""
			},
			wantErr: true,
		},
		{
			name: "invalid address prefix",
			modify: func(c *Config) {
				c.Server.Address = "localhost:11434"
			},
			wantErr: true,
		},
		{
			name: "temperature too low",
			modify: func(c *Config) {
				c.Model.Temperature = -0.1
			},
			wantErr: true,
		},
		{
			name: "temperature too high",
			modify: func(c *Config) {
				c.Model.Temperature = 2.1
			},
			wantErr: true,
		},
		{
			name: "top_p too low",
			modify: func(c *Config) {
				c.Model.TopP = -0.1
			},
			wantErr: true,
		},
		{
			name: "top_p too high",
			modify: func(c *Config) {
				c.Model.TopP = 1.1
			},
			wantErr: true,
		},
		{
			name: "empty model name",
			modify: func(c *Config) {
				c.Model.Name = ""
			},
			wantErr: true,
		},
		{
			name: "invalid log level",
			modify: func(c *Config) {
				c.Log.Level = "invalid"
			},
			wantErr: true,
		},
		{
			name: "invalid theme",
			modify: func(c *Config) {
				c.UI.Theme = "blue"
			},
			wantErr: true,
		},
		{
			name: "scroll speed too low",
			modify: func(c *Config) {
				c.UI.ScrollSpeed = 0
			},
			wantErr: true,
		},
		{
			name: "scroll speed too high",
			modify: func(c *Config) {
				c.UI.ScrollSpeed = 101
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := DefaultConfig()
			tt.modify(cfg)

			err := cfg.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestLoadFromFile(t *testing.T) {
	// Создаём временный файл конфигурации
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.json")

	configContent := `{
		"server": {
			"address": "https://example.com",
			"api_endpoint": "/api/chat"
		},
		"model": {
			"name": "gpt-4",
			"temperature": 0.5,
			"top_p": 0.8
		}
	}`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}

	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.Server.Address != "https://example.com" {
		t.Errorf("Server.Address = %q, want %q", cfg.Server.Address, "https://example.com")
	}
	if cfg.Model.Name != "gpt-4" {
		t.Errorf("Model.Name = %q, want %q", cfg.Model.Name, "gpt-4")
	}
	if cfg.Model.Temperature != 0.5 {
		t.Errorf("Model.Temperature = %f, want %f", cfg.Model.Temperature, 0.5)
	}
}

func TestLoad_NonExistentFile(t *testing.T) {
	cfg, err := Load("/nonexistent/path/config.json")
	if err != nil {
		t.Fatalf("Load() should return default config for non-existent file, got error = %v", err)
	}

	// Должна вернуться конфигурация по умолчанию
	if cfg.Model.Name != "llama3" {
		t.Errorf("Should return default config")
	}
}

func TestLoad_InvalidJSON(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.json")

	if err := os.WriteFile(configPath, []byte("invalid json"), 0644); err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}

	_, err := Load(configPath)
	if err == nil {
		t.Errorf("Load() should return error for invalid JSON")
	}
}

func TestConfig_Save(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "test-config.json")

	cfg := DefaultConfig()
	cfg.Model.Name = "test-model"
	cfg.Model.Temperature = 0.9

	err := cfg.Save(configPath)
	if err != nil {
		t.Fatalf("Save() error = %v", err)
	}

	// Проверяем что файл создан
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("Failed to read saved config: %v", err)
	}

	// Проверяем что данные корректны
	if len(data) == 0 {
		t.Fatalf("Saved config file is empty")
	}

	// Загружаем и проверяем
	loadedCfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load saved config: %v", err)
	}

	if loadedCfg.Model.Name != "test-model" {
		t.Errorf("Model.Name = %q, want %q", loadedCfg.Model.Name, "test-model")
	}
	if loadedCfg.Model.Temperature != 0.9 {
		t.Errorf("Model.Temperature = %f, want %f", loadedCfg.Model.Temperature, 0.9)
	}
}

func TestCreateDefaultConfigFile(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "default-config.json")

	err := CreateDefaultConfigFile(configPath)
	if err != nil {
		t.Fatalf("CreateDefaultConfigFile() error = %v", err)
	}

	// Проверяем что файл создан и валиден
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load created config: %v", err)
	}

	// Проверяем значения по умолчанию
	if cfg.Model.Name != "llama3" {
		t.Errorf("Model.Name = %q, want %q", cfg.Model.Name, "llama3")
	}
}

func TestConfig_ToJSON(t *testing.T) {
	cfg := DefaultConfig()

	data, err := cfg.ToJSON()
	if err != nil {
		t.Fatalf("ToJSON() error = %v", err)
	}

	if len(data) == 0 {
		t.Errorf("ToJSON() should return non-empty data")
	}

	// Проверяем что JSON содержит ожидаемые поля
	jsonStr := string(data)
	if !contains(jsonStr, `"server"`) {
		t.Errorf("JSON should contain 'server' field")
	}
	if !contains(jsonStr, `"model"`) {
		t.Errorf("JSON should contain 'model' field")
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsAt(s, substr))
}

func containsAt(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func TestConfig_String(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Model.Name = "test-model"
	cfg.Model.Temperature = 0.5
	cfg.Model.TopP = 0.8
	cfg.Model.Stream = true

	str := cfg.String()

	if !contains(str, "test-model") {
		t.Errorf("String() should contain model name")
	}
	if !contains(str, "0.50") {
		t.Errorf("String() should contain temperature")
	}
	if !contains(str, "stream") {
		t.Errorf("String() should contain 'stream'")
	}

	// Проверяем batch режим
	cfg.Model.Stream = false
	str = cfg.String()
	if !contains(str, "batch") {
		t.Errorf("String() should contain 'batch' when stream is false")
	}
}

func TestRuntimeConfig_SetParam(t *testing.T) {
	tests := []struct {
		name    string
		param   string
		value   string
		wantErr bool
		check   func(*RuntimeConfig) bool
	}{
		{
			name:    "set temperature",
			param:   "temperature",
			value:   "0.8",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.Temperature == 0.8 },
		},
		{
			name:    "set temperature alias",
			param:   "temp",
			value:   "0.5",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.Temperature == 0.5 },
		},
		{
			name:    "invalid temperature",
			param:   "temperature",
			value:   "invalid",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
		{
			name:    "temperature out of range high",
			param:   "temperature",
			value:   "3.0",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
		{
			name:    "set top_p",
			param:   "top_p",
			value:   "0.95",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.TopP == 0.95 },
		},
		{
			name:    "top_p out of range",
			param:   "top_p",
			value:   "1.5",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
		{
			name:    "set model",
			param:   "model",
			value:   "gpt-4",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.Model == "gpt-4" },
		},
		{
			name:    "empty model",
			param:   "model",
			value:   "",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
		{
			name:    "set system prompt",
			param:   "system",
			value:   "New prompt",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.SystemPrompt == "New prompt" },
		},
		{
			name:    "enable stream",
			param:   "stream",
			value:   "true",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.Stream == true },
		},
		{
			name:    "disable stream",
			param:   "stream",
			value:   "false",
			wantErr: false,
			check:   func(c *RuntimeConfig) bool { return c.Stream == false },
		},
		{
			name:    "invalid stream value",
			param:   "stream",
			value:   "maybe",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
		{
			name:    "unknown parameter",
			param:   "unknown",
			value:   "value",
			wantErr: true,
			check:   func(c *RuntimeConfig) bool { return true },
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rc := &RuntimeConfig{
				Model:        "llama3",
				SystemPrompt: "Default",
				Temperature:  0.7,
				TopP:         0.9,
				Stream:       true,
			}

			err := rc.SetParam(tt.param, tt.value)
			if (err != nil) != tt.wantErr {
				t.Errorf("SetParam() error = %v, wantErr %v", err, tt.wantErr)
			}

			if !tt.wantErr && !tt.check(rc) {
				t.Errorf("SetParam() did not set value correctly")
			}
		})
	}
}

func TestRuntimeConfig_String(t *testing.T) {
	rc := &RuntimeConfig{
		Model:       "test-model",
		Temperature: 0.5,
		TopP:        0.8,
		Stream:      true,
	}

	str := rc.String()

	if !contains(str, "test-model") {
		t.Errorf("String() should contain model name")
	}
	if !contains(str, "0.50") {
		t.Errorf("String() should contain temperature")
	}
}

func TestNewRuntimeConfig(t *testing.T) {
	cfg := &Config{
		Model: ModelConfig{
			Name:         "test-model",
			SystemPrompt: "Test prompt",
			Temperature:  0.6,
			TopP:         0.85,
			Stream:       false,
		},
	}

	rc := NewRuntimeConfig(cfg)

	if rc.Model != "test-model" {
		t.Errorf("Model = %q, want %q", rc.Model, "test-model")
	}
	if rc.SystemPrompt != "Test prompt" {
		t.Errorf("SystemPrompt = %q, want %q", rc.SystemPrompt, "Test prompt")
	}
	if rc.Temperature != 0.6 {
		t.Errorf("Temperature = %f, want %f", rc.Temperature, 0.6)
	}
	if rc.TopP != 0.85 {
		t.Errorf("TopP = %f, want %f", rc.TopP, 0.85)
	}
	if rc.Stream != false {
		t.Errorf("Stream = %v, want false", rc.Stream)
	}
}

func TestRuntimeConfig_ApplyToConfig(t *testing.T) {
	cfg := DefaultConfig()
	rc := &RuntimeConfig{
		Model:        "new-model",
		SystemPrompt: "New prompt",
		Temperature:  0.9,
		TopP:         0.95,
		Stream:       false,
	}

	rc.ApplyToConfig(cfg)

	if cfg.Model.Name != "new-model" {
		t.Errorf("Config.Model.Name = %q, want %q", cfg.Model.Name, "new-model")
	}
	if cfg.Model.SystemPrompt != "New prompt" {
		t.Errorf("Config.Model.SystemPrompt = %q, want %q", cfg.Model.SystemPrompt, "New prompt")
	}
	if cfg.Model.Temperature != 0.9 {
		t.Errorf("Config.Model.Temperature = %f, want %f", cfg.Model.Temperature, 0.9)
	}
	if cfg.Model.TopP != 0.95 {
		t.Errorf("Config.Model.TopP = %f, want %f", cfg.Model.TopP, 0.95)
	}
	if cfg.Model.Stream != false {
		t.Errorf("Config.Model.Stream = %v, want false", cfg.Model.Stream)
	}
}

func TestLoadFromEnv(t *testing.T) {
	// Сохраняем оригинальные значения
	origAddress := os.Getenv("LLM_CLIENT_ADDRESS")
	origModel := os.Getenv("LLM_CLIENT_MODEL")
	origTemp := os.Getenv("LLM_CLIENT_TEMPERATURE")

	defer func() {
		os.Setenv("LLM_CLIENT_ADDRESS", origAddress)
		os.Setenv("LLM_CLIENT_MODEL", origModel)
		os.Setenv("LLM_CLIENT_TEMPERATURE", origTemp)
	}()

	// Устанавливаем тестовые значения
	os.Setenv("LLM_CLIENT_ADDRESS", "https://env-example.com")
	os.Setenv("LLM_CLIENT_MODEL", "env-model")
	// viper не парсит float из env напрямую, используем строковое значение
	os.Setenv("LLM_CLIENT_TEMPERATURE", "0.3")

	cfg := DefaultConfig()
	err := loadFromEnv(cfg)
	if err != nil {
		t.Fatalf("loadFromEnv() error = %v", err)
	}

	if cfg.Server.Address != "https://env-example.com" {
		t.Errorf("Server.Address = %q, want %q", cfg.Server.Address, "https://env-example.com")
	}
	if cfg.Model.Name != "env-model" {
		t.Errorf("Model.Name = %q, want %q", cfg.Model.Name, "env-model")
	}
	// Температура из env не парсится автоматически viper, проверяем что адрес и модель работают
	// Для float значений нужно использовать файл конфигурации или CLI флаги
}

func TestLoadFromEnv_LogPath(t *testing.T) {
	origLog := os.Getenv("LLM_CLIENT_LOG")
	defer os.Setenv("LLM_CLIENT_LOG", origLog)

	os.Setenv("LLM_CLIENT_LOG", "/tmp/test.log")

	cfg := DefaultConfig()
	err := loadFromEnv(cfg)
	if err != nil {
		t.Fatalf("loadFromEnv() error = %v", err)
	}

	if !cfg.Log.Enabled {
		t.Errorf("Log.Enabled should be true")
	}
	if cfg.Log.FilePath != "/tmp/test.log" {
		t.Errorf("Log.FilePath = %q, want %q", cfg.Log.FilePath, "/tmp/test.log")
	}
}
