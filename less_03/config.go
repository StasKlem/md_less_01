package main

import (
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// CLIConfig хранит настройки из командной строки
type CLIConfig struct {
	ConfigFile  string
	Address     string
	Model       string
	SystemPrompt string
	Temperature float64
	TopP        float64
	ShowConfig  bool
	InitConfig  bool
}

// ParseCLIConfig парсит аргументы командной строки
func ParseCLIConfig() *CLIConfig {
	cli := &CLIConfig{}

	flag.StringVar(&cli.ConfigFile, "config", "", "Path to config file (or use LLM_CLIENT_CONFIG env)")
	flag.StringVar(&cli.Address, "address", "", "LLM server address")
	flag.StringVar(&cli.Address, "a", "", "Shorthand for -address")
	flag.StringVar(&cli.Model, "model", "", "Model name to use")
	flag.StringVar(&cli.Model, "m", "", "Shorthand for -model")
	flag.StringVar(&cli.SystemPrompt, "system", "", "System prompt")
	flag.StringVar(&cli.SystemPrompt, "s", "", "Shorthand for -system")
	flag.Float64Var(&cli.Temperature, "temperature", 0, "Temperature (0.0-2.0)")
	flag.Float64Var(&cli.Temperature, "t", 0, "Shorthand for -temperature")
	flag.Float64Var(&cli.TopP, "top-p", 0, "Top P (0.0-1.0)")
	flag.Float64Var(&cli.TopP, "p", 0, "Shorthand for -top-p")
	flag.BoolVar(&cli.ShowConfig, "show-config", false, "Show default config and exit")
	flag.BoolVar(&cli.InitConfig, "init-config", false, "Create default config file")

	flag.Parse()

	return cli
}

// LoadAppConfig загружает полную конфигурацию из файла и CLI флагов
func LoadAppConfig(cli *CLIConfig) (*AppConfig, error) {
	// Загружаем конфигурацию из файла
	var config *AppConfig
	var err error

	configPath := cli.ConfigFile
	if configPath == "" {
		configPath = GetConfigPath()
	}

	if configPath != "" {
		config, err = LoadConfig(configPath)
		if err != nil {
			return nil, fmt.Errorf("failed to load config: %w", err)
		}
		LogInfo("Config loaded from: %s", configPath)
	} else {
		config = DefaultConfig()
		LogInfo("Using default config")
	}

	// Переопределяем из CLI флагов
	if cli.Address != "" {
		config.Server.Address = cli.Address
	}
	if cli.Model != "" {
		config.Model.Name = cli.Model
	}
	if cli.SystemPrompt != "" {
		config.Model.SystemPrompt = cli.SystemPrompt
	}
	if cli.Temperature != 0 {
		config.Model.Temperature = cli.Temperature
	}
	if cli.TopP != 0 {
		config.Model.TopP = cli.TopP
	}

	// Проверяем переменную окружения для логирования
	if logPath := os.Getenv("LLM_CLIENT_LOG"); logPath != "" {
		config.Log.Enabled = true
		config.Log.FilePath = logPath
	}

	// Включаем логирование запросов/ответей если включено логирование
	if config.Log.Enabled {
		config.Log.LogRequests = true
		config.Log.LogResponses = true
	}

	return config, nil
}

// RuntimeConfig хранит изменяемые во время работы параметры
type RuntimeConfig struct {
	Model       string
	SystemPrompt string
	Temperature float64
	TopP        float64
	Stream      bool
}

// NewRuntimeConfig создаёт RuntimeConfig из AppConfig
func NewRuntimeConfig(app *AppConfig) *RuntimeConfig {
	return &RuntimeConfig{
		Model:        app.Model.Name,
		SystemPrompt: app.Model.SystemPrompt,
		Temperature:  app.Model.Temperature,
		TopP:         app.Model.TopP,
		Stream:       app.Model.Stream,
	}
}

// SetParam устанавливает параметр во время работы
func (c *RuntimeConfig) SetParam(name, value string) error {
	LogDebug("Setting runtime parameter: %s=%s", name, value)

	switch name {
	case "temperature", "temp":
		v, err := strconv.ParseFloat(value, 64)
		if err != nil {
			LogError("Failed to parse temperature", err)
			return fmt.Errorf("invalid temperature value: %s", value)
		}
		if v < 0 || v > 2 {
			LogError("Temperature out of range", fmt.Errorf("value %f not in [0, 2]", v))
			return fmt.Errorf("temperature must be between 0.0 and 2.0")
		}
		c.Temperature = v
		LogInfo("Temperature set to %.2f", v)

	case "top_p", "topp", "top-p":
		v, err := strconv.ParseFloat(value, 64)
		if err != nil {
			LogError("Failed to parse top_p", err)
			return fmt.Errorf("invalid top_p value: %s", value)
		}
		if v < 0 || v > 1 {
			LogError("Top P out of range", fmt.Errorf("value %f not in [0, 1]", v))
			return fmt.Errorf("top_p must be between 0.0 and 1.0")
		}
		c.TopP = v
		LogInfo("Top P set to %.2f", v)

	case "model":
		if value == "" {
			LogError("Model name cannot be empty", nil)
			return fmt.Errorf("model name cannot be empty")
		}
		c.Model = value
		LogInfo("Model set to %s", value)

	case "system", "system_prompt", "system-prompt":
		c.SystemPrompt = value
		LogInfo("System prompt updated")

	case "stream":
		v := strings.ToLower(value)
		if v == "true" || v == "1" || v == "on" || v == "yes" {
			c.Stream = true
			LogInfo("Stream mode enabled")
		} else if v == "false" || v == "0" || v == "off" || v == "no" {
			c.Stream = false
			LogInfo("Stream mode disabled")
		} else {
			return fmt.Errorf("invalid stream value: %s (use true/false, 1/0, on/off, yes/no)", value)
		}

	default:
		LogError("Unknown parameter", fmt.Errorf("unknown param: %s", name))
		return fmt.Errorf("unknown parameter: %s", name)
	}

	return nil
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

// ToChatRequest конвертирует в ChatRequest
// Если stream=false, используется значение из конфига
func (c *RuntimeConfig) ToChatRequest(messages []Message, stream bool) *ChatRequest {
	useStream := stream
	if !stream {
		useStream = c.Stream
	}
	return &ChatRequest{
		Model:       c.Model,
		Messages:    messages,
		Stream:      useStream,
		Temperature: c.Temperature,
		TopP:        c.TopP,
	}
}
