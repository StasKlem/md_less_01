package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
	"github.com/spf13/viper"
)

type AccessMode string

const (
	AccessModeWhitelist AccessMode = "whitelist"
	AccessModePublic    AccessMode = "public"
)

type Config struct {
	Bot       BotConfig
	Database  DatabaseConfig
	LLM       LLMConfig
	Scheduler SchedulerConfig
	Access    AccessConfig
	Logging   LoggingConfig
}

type BotConfig struct {
	Token string
}

type DatabaseConfig struct {
	Path    string
	WALMode bool
}

type LLMConfig struct {
	APIKey  string
	BaseURL string
	Model   string
	TimeOut time.Duration
}

type SchedulerConfig struct {
	ReportTime   string
	ReportTicker time.Duration
}

type AccessConfig struct {
	Mode           AccessMode
	AllowedUserIDs []int64
}

type LoggingConfig struct {
	Level  string
	Format string
}

func Load() (*Config, error) {
	viper.SetConfigName(".env")
	viper.SetConfigType("env")
	viper.AddConfigPath(".")
	viper.AddConfigPath("/etc/kbju-bot/")
	viper.AutomaticEnv()

	viper.SetDefault("BOT_TOKEN", "")
	viper.SetDefault("DB_PATH", "./data/kbju.db")
	viper.SetDefault("DB_WAL_MODE", true)
	viper.SetDefault("LLM_API_KEY", "")
	viper.SetDefault("LLM_BASE_URL", "https://routerai.ru/api/v1")
	viper.SetDefault("LLM_MODEL", "deepseek/deepseek-v3.2")
	viper.SetDefault("LLM_TIMEOUT_SECONDS", 60)
	viper.SetDefault("SCHEDULER_REPORT_TIME", "21:00")
	viper.SetDefault("SCHEDULER_REPORT_TICKER_MINUTES", 60)
	viper.SetDefault("ACCESS_MODE", "public")
	viper.SetDefault("ALLOWED_USER_IDS", "")
	viper.SetDefault("LOG_LEVEL", "info")
	viper.SetDefault("LOG_FORMAT", "json")

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
	}

	cfg := &Config{
		Bot: BotConfig{
			Token: viper.GetString("BOT_TOKEN"),
		},
		Database: DatabaseConfig{
			Path:    viper.GetString("DB_PATH"),
			WALMode: viper.GetBool("DB_WAL_MODE"),
		},
		LLM: LLMConfig{
			APIKey:  viper.GetString("LLM_API_KEY"),
			BaseURL: viper.GetString("LLM_BASE_URL"),
			Model:   viper.GetString("LLM_MODEL"),
			TimeOut: time.Duration(viper.GetInt("LLM_TIMEOUT_SECONDS")) * time.Second,
		},
		Scheduler: SchedulerConfig{
			ReportTime:   viper.GetString("SCHEDULER_REPORT_TIME"),
			ReportTicker: time.Duration(viper.GetInt("SCHEDULER_REPORT_TICKER_MINUTES")) * time.Minute,
		},
		Access: AccessConfig{
			Mode: AccessMode(viper.GetString("ACCESS_MODE")),
		},
		Logging: LoggingConfig{
			Level:  viper.GetString("LOG_LEVEL"),
			Format: viper.GetString("LOG_FORMAT"),
		},
	}

	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}

	if err := cfg.parseAllowedUserIDs(); err != nil {
		return nil, fmt.Errorf("failed to parse allowed user IDs: %w", err)
	}

	return cfg, nil
}

func (c *Config) validate() error {
	if c.Bot.Token == "" {
		return fmt.Errorf("BOT_TOKEN is required")
	}
	if c.LLM.APIKey == "" {
		return fmt.Errorf("LLM_API_KEY is required")
	}
	if c.Access.Mode != AccessModeWhitelist && c.Access.Mode != AccessModePublic {
		return fmt.Errorf("ACCESS_MODE must be 'whitelist' or 'public', got: %s", c.Access.Mode)
	}
	return nil
}

func (c *Config) parseAllowedUserIDs() error {
	if c.Access.Mode != AccessModeWhitelist {
		return nil
	}

	idsStr := viper.GetString("ALLOWED_USER_IDS")
	if idsStr == "" {
		return fmt.Errorf("ALLOWED_USER_IDS is required when ACCESS_MODE is 'whitelist'")
	}

	ids := strings.Split(idsStr, ",")
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		parsedID, err := strconv.ParseInt(id, 10, 64)
		if err != nil {
			return fmt.Errorf("invalid user ID '%s': %w", id, err)
		}
		c.Access.AllowedUserIDs = append(c.Access.AllowedUserIDs, parsedID)
	}

	if len(c.Access.AllowedUserIDs) == 0 {
		return fmt.Errorf("ALLOWED_USER_IDS is empty when ACCESS_MODE is 'whitelist'")
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

func init() {
	if err := godotenv.Load(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: .env file not found: %v\n", err)
	}
}
