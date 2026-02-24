package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

type AccessMode string

const (
	AccessModeWhitelist AccessMode = "whitelist"
	AccessModePublic    AccessMode = "public"
)

type Config struct {
	Telegram   TelegramConfig
	LLM        LLMConfig
	Database   DatabaseConfig
	Scheduler  SchedulerConfig
	Access     AccessConfig
	LogLevel   string
	ServerPort int
}

type TelegramConfig struct {
	Token string
}

type LLMConfig struct {
	Provider  string
	APIKey    string
	BaseURL   string
	Model     string
	Timeout   time.Duration
	MaxTokens int
}

type DatabaseConfig struct {
	Path         string
	MaxOpenConns int
	MaxIdleConns int
	WALMode      bool
}

type SchedulerConfig struct {
	ReportTime string
	Timezone   string
}

type AccessConfig struct {
	Mode           AccessMode
	AllowedUserIDs []int64
}

func Load() (*Config, error) {
	v := viper.New()

	v.SetEnvPrefix("")
	v.AutomaticEnv()
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	setDefaults(v)

	if err := v.BindEnv("telegram.token", "TELEGRAM_TOKEN"); err != nil {
		return nil, fmt.Errorf("bind telegram token: %w", err)
	}
	if err := v.BindEnv("llm.api_key", "LLM_API_KEY"); err != nil {
		return nil, fmt.Errorf("bind llm api key: %w", err)
	}
	if err := v.BindEnv("llm.base_url", "LLM_BASE_URL"); err != nil {
		return nil, fmt.Errorf("bind llm base url: %w", err)
	}
	if err := v.BindEnv("llm.model", "LLM_MODEL"); err != nil {
		return nil, fmt.Errorf("bind llm model: %w", err)
	}
	if err := v.BindEnv("database.path", "DATABASE_PATH"); err != nil {
		return nil, fmt.Errorf("bind database path: %w", err)
	}
	if err := v.BindEnv("access.mode", "ACCESS_MODE"); err != nil {
		return nil, fmt.Errorf("bind access mode: %w", err)
	}
	if err := v.BindEnv("access.allowed_user_ids", "ALLOWED_USER_IDS"); err != nil {
		return nil, fmt.Errorf("bind allowed user ids: %w", err)
	}

	cfg := &Config{
		Telegram: TelegramConfig{
			Token: v.GetString("telegram.token"),
		},
		LLM: LLMConfig{
			Provider:  v.GetString("llm.provider"),
			APIKey:    v.GetString("llm.api_key"),
			BaseURL:   v.GetString("llm.base_url"),
			Model:     v.GetString("llm.model"),
			Timeout:   v.GetDuration("llm.timeout"),
			MaxTokens: v.GetInt("llm.max_tokens"),
		},
		Database: DatabaseConfig{
			Path:         v.GetString("database.path"),
			MaxOpenConns: v.GetInt("database.max_open_conns"),
			MaxIdleConns: v.GetInt("database.max_idle_conns"),
			WALMode:      v.GetBool("database.wal_mode"),
		},
		Scheduler: SchedulerConfig{
			ReportTime: v.GetString("scheduler.report_time"),
			Timezone:   v.GetString("scheduler.timezone"),
		},
		Access: AccessConfig{
			Mode:           AccessMode(v.GetString("access.mode")),
			AllowedUserIDs: parseUserIDs(v.GetString("access.allowed_user_ids")),
		},
		LogLevel:   v.GetString("log_level"),
		ServerPort: v.GetInt("server_port"),
	}

	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("validate config: %w", err)
	}

	return cfg, nil
}

func setDefaults(v *viper.Viper) {
	v.SetDefault("llm.provider", "openai")
	v.SetDefault("llm.timeout", 30*time.Second)
	v.SetDefault("llm.max_tokens", 1000)

	v.SetDefault("database.path", "./data/kbju.db")
	v.SetDefault("database.max_open_conns", 10)
	v.SetDefault("database.max_idle_conns", 5)
	v.SetDefault("database.wal_mode", true)

	v.SetDefault("scheduler.report_time", "21:00")
	v.SetDefault("scheduler.timezone", "UTC")

	v.SetDefault("access.mode", string(AccessModeWhitelist))

	v.SetDefault("log_level", "info")
	v.SetDefault("server_port", 8080)
}

func parseUserIDs(s string) []int64 {
	if s == "" {
		return nil
	}
	var ids []int64
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		var id int64
		if _, err := fmt.Sscanf(part, "%d", &id); err == nil && id > 0 {
			ids = append(ids, id)
		}
	}
	return ids
}

func (c *Config) Validate() error {
	if c.Telegram.Token == "" {
		return fmt.Errorf("telegram token is required")
	}
	if c.LLM.APIKey == "" {
		return fmt.Errorf("llm api key is required")
	}
	if c.Access.Mode != AccessModeWhitelist && c.Access.Mode != AccessModePublic {
		return fmt.Errorf("invalid access mode: %s, must be 'whitelist' or 'public'", c.Access.Mode)
	}
	if c.Access.Mode == AccessModeWhitelist && len(c.Access.AllowedUserIDs) == 0 {
		return fmt.Errorf("whitelist mode requires at least one allowed user id")
	}
	return nil
}

func (c *Config) IsUserAllowed(userID int64) bool {
	if c.Access.Mode == AccessModePublic {
		return true
	}
	for _, id := range c.Access.AllowedUserIDs {
		if id == userID {
			return true
		}
	}
	return false
}
