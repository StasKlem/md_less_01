// Package config предоставляет конфигурацию приложения с поддержкой ENV переменных.
package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// AccessMode определяет режим контроля доступа.
type AccessMode string

const (
	// AccessModeWhitelist разрешает доступ только пользователям из списка ALLOWED_USER_IDS.
	AccessModeWhitelist AccessMode = "whitelist"
	// AccessModePublic разрешает доступ всем пользователям.
	AccessModePublic AccessMode = "public"
)

// Config содержит всю конфигурацию приложения.
type Config struct {
	// Telegram настройки
	Telegram TelegramConfig `mapstructure:"telegram"`

	// LLM настройки
	LLM LLMConfig `mapstructure:"llm"`

	// Database настройки
	Database DatabaseConfig `mapstructure:"database"`

	// AccessControl настройки
	AccessControl AccessControlConfig `mapstructure:"access_control"`

	// Report настройки
	Report ReportConfig `mapstructure:"report"`

	// Log настройки
	Log LogConfig `mapstructure:"log"`
}

// TelegramConfig содержит настройки Telegram бота.
type TelegramConfig struct {
	// BotToken токен для доступа к Telegram Bot API.
	BotToken string `mapstructure:"bot_token"`
	// Timeout таймаут запросов к Telegram API в секундах.
	Timeout time.Duration `mapstructure:"timeout"`
}

// LLMConfig содержит настройки LLM провайдера.
type LLMConfig struct {
	// Provider тип провайдера (openai, anthropic, etc.).
	Provider string `mapstructure:"provider"`
	// APIKey ключ для доступа к LLM API.
	APIKey string `mapstructure:"api_key"`
	// Model название модели для запросов.
	Model string `mapstructure:"model"`
	// BaseURL базовый URL API (для кастомных endpoint).
	BaseURL string `mapstructure:"base_url"`
	// Timeout таймаут запросов к LLM API в секундах.
	Timeout time.Duration `mapstructure:"timeout"`
}

// DatabaseConfig содержит настройки базы данных.
type DatabaseConfig struct {
	// Path путь к файлу SQLite базы данных.
	Path string `mapstructure:"path"`
	// MaxOpenConns максимальное количество открытых соединений.
	MaxOpenConns int `mapstructure:"max_open_conns"`
	// MaxIdleConns максимальное количество простых соединений.
	MaxIdleConns int `mapstructure:"max_idle_conns"`
	// ConnMaxLifetime время жизни соединения.
	ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
}

// AccessControlConfig содержит настройки контроля доступа.
type AccessControlConfig struct {
	// Mode режим контроля доступа (whitelist или public).
	Mode AccessMode `mapstructure:"mode"`
	// AllowedUserIDs список ID пользователей, которым разрешен доступ (для whitelist режима).
	AllowedUserIDs []int64 `mapstructure:"allowed_user_ids"`
}

// ReportConfig содержит настройки отчетов.
type ReportConfig struct {
	// SendTime время отправки ежедневного отчета в формате HH:MM.
	SendTime string `mapstructure:"send_time"`
	// Timezone часовой пояс для отправки отчетов.
	Timezone string `mapstructure:"timezone"`
}

// LogConfig содержит настройки логирования.
type LogConfig struct {
	// Level уровень логирования (debug, info, warn, error).
	Level string `mapstructure:"level"`
	// Format формат логов (json, text).
	Format string `mapstructure:"format"`
}

// Load загружает конфигурацию из ENV переменных.
func Load() (*Config, error) {
	v := viper.New()

	// Настройка ENV переменных
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// Явное связывание переменных окружения
	bindEnv(v)

	// Установка значений по умолчанию
	setDefaults(v)

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}

	// Валидация конфигурации
	if err := validate(&cfg); err != nil {
		return nil, fmt.Errorf("validate config: %w", err)
	}

	return &cfg, nil
}

// bindEnv связывает переменные окружения с полями конфига.
func bindEnv(v *viper.Viper) {
	// Telegram
	v.BindEnv("telegram.bot_token", "TELEGRAM_BOT_TOKEN")
	v.BindEnv("telegram.timeout", "TELEGRAM_TIMEOUT")

	// LLM
	v.BindEnv("llm.provider", "LLM_PROVIDER")
	v.BindEnv("llm.api_key", "LLM_API_KEY")
	v.BindEnv("llm.model", "LLM_MODEL")
	v.BindEnv("llm.base_url", "LLM_BASE_URL")
	v.BindEnv("llm.timeout", "LLM_TIMEOUT")

	// Database
	v.BindEnv("database.path", "DATABASE_PATH")
	v.BindEnv("database.max_open_conns", "DATABASE_MAX_OPEN_CONNS")
	v.BindEnv("database.max_idle_conns", "DATABASE_MAX_IDLE_CONNS")
	v.BindEnv("database.conn_max_lifetime", "DATABASE_CONN_MAX_LIFETIME")

	// Access Control
	v.BindEnv("access_control.mode", "ACCESS_CONTROL_MODE")
	v.BindEnv("access_control.allowed_user_ids", "ACCESS_CONTROL_ALLOWED_USER_IDS")

	// Report
	v.BindEnv("report.send_time", "REPORT_SEND_TIME")
	v.BindEnv("report.timezone", "REPORT_TIMEZONE")

	// Log
	v.BindEnv("log.level", "LOG_LEVEL")
	v.BindEnv("log.format", "LOG_FORMAT")
}

// setDefaults устанавливает значения по умолчанию.
func setDefaults(v *viper.Viper) {
	// Telegram
	v.SetDefault("telegram.timeout", 30*time.Second)

	// LLM
	v.SetDefault("llm.provider", "openai")
	v.SetDefault("llm.model", "gpt-4o-mini")
	v.SetDefault("llm.timeout", 60*time.Second)

	// Database
	v.SetDefault("database.path", "./data/kbju.db")
	v.SetDefault("database.max_open_conns", 1) // SQLite лучше работает с одним соединением
	v.SetDefault("database.max_idle_conns", 1)
	v.SetDefault("database.conn_max_lifetime", 5 * time.Minute)

	// Access Control
	v.SetDefault("access_control.mode", string(AccessModePublic))
	v.SetDefault("access_control.allowed_user_ids", []int64{})

	// Report
	v.SetDefault("report.send_time", "21:00")
	v.SetDefault("report.timezone", "Europe/Moscow")

	// Log
	v.SetDefault("log.level", "info")
	v.SetDefault("log.format", "text")
}

// validate проверяет корректность конфигурации.
func validate(cfg *Config) error {
	if cfg.Telegram.BotToken == "" {
		return fmt.Errorf("telegram.bot_token is required")
	}

	if cfg.LLM.APIKey == "" {
		return fmt.Errorf("llm.api_key is required")
	}

	// Валидация режима доступа
	switch cfg.AccessControl.Mode {
	case AccessModeWhitelist, AccessModePublic:
		// OK
	default:
		return fmt.Errorf("invalid access_control.mode: %s (allowed: whitelist, public)", cfg.AccessControl.Mode)
	}

	// В режиме whitelist должен быть хотя бы один пользователь
	if cfg.AccessControl.Mode == AccessModeWhitelist && len(cfg.AccessControl.AllowedUserIDs) == 0 {
		return fmt.Errorf("access_control.allowed_user_ids must not be empty in whitelist mode")
	}

	// Валидация времени отчета
	if cfg.Report.SendTime == "" {
		return fmt.Errorf("report.send_time is required")
	}

	// Валидация уровня логов
	switch strings.ToLower(cfg.Log.Level) {
	case "debug", "info", "warn", "error":
		// OK
	default:
		return fmt.Errorf("invalid log.level: %s (allowed: debug, info, warn, error)", cfg.Log.Level)
	}

	return nil
}

// IsWhitelistMode возвращает true, если включен режим whitelist.
func (c *AccessControlConfig) IsWhitelistMode() bool {
	return c.Mode == AccessModeWhitelist
}

// IsUserAllowed проверяет, разрешен ли доступ пользователю с данным ID.
func (c *AccessControlConfig) IsUserAllowed(userID int64) bool {
	if !c.IsWhitelistMode() {
		return true
	}

	for _, id := range c.AllowedUserIDs {
		if id == userID {
			return true
		}
	}
	return false
}
