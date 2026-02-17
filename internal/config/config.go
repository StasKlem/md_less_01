// Package config содержит конфигурацию приложения
package config

import (
	"fmt"
	"os"
	"time"
)

// Config содержит все настройки приложения
type Config struct {
	APIKey    string        // API ключ для авторизации
	APIURL    string        // URL endpoint API
	Model     string        // Название модели
	MaxTokens int           // Максимальное количество токенов для запроса без ограничений
	Timeout   time.Duration // Глобальный таймаут для HTTP запросов
}

const (
	defaultModel     = "deepseek/deepseek-v3.2"
	defaultAPIURL    = "https://routerai.ru/api/v1/chat/completions"
	defaultMaxTokens = 4096
	defaultTimeout   = 120 * time.Second
)

// Load загружает конфигурацию из переменных окружения
// Возвращает: заполненную Config или ошибку если ROUTERAI_API_KEY не задан
func Load() (*Config, error) {
	apiKey := os.Getenv("ROUTERAI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("переменная окружения ROUTERAI_API_KEY не установлена")
	}

	return &Config{
		APIKey:    apiKey,
		APIURL:    defaultAPIURL,
		Model:     defaultModel,
		MaxTokens: defaultMaxTokens,
		Timeout:   defaultTimeout,
	}, nil
}
