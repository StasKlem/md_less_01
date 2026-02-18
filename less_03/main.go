package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

const (
	// AppName - имя приложения
	AppName = "LLM Chat Client"
	// Version - версия приложения
	Version = "1.0.0"
)

func main() {
	// Парсим аргументы командной строки
	cli := ParseCLIConfig()

	// Обработка специальных флагов до инициализации логгера
	if cli.ShowConfig {
		PrintDefaultConfig()
		os.Exit(0)
	}

	if cli.InitConfig {
		path := cli.ConfigFile
		if path == "" {
			path = "config.json"
		}
		if err := CreateDefaultConfigFile(path); err != nil {
			fmt.Fprintf(os.Stderr, "Ошибка создания конфигурации: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("Config file created: %s\n", path)
		os.Exit(0)
	}

	// Инициализируем логгер по умолчанию (в никуда)
	defaultLogConfig := &AppConfig{
		Log: LogConfig{
			Enabled:  false,
			FilePath: "",
		},
	}
	if err := InitLogger(defaultLogConfig); err != nil {
		fmt.Fprintf(os.Stderr, "Ошибка инициализации логгера: %v\n", err)
	}

	// Загружаем полную конфигурацию
	appConfig, err := LoadAppConfig(cli)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Ошибка загрузки конфигурации: %v\n", err)
		os.Exit(1)
	}

	// Пересоздаём логгер с правильной конфигурацией
	if err := InitLogger(appConfig); err != nil {
		fmt.Fprintf(os.Stderr, "Ошибка инициализации логгера: %v\n", err)
	}

	LogInfo("Application starting")
	LogInfo("Config: address=%s, model=%s",
		appConfig.Server.Address, appConfig.Model.Name)

	// Проверяем валидность конфигурации
	if err := appConfig.Validate(); err != nil {
		LogError("Config validation failed", err)
		fmt.Fprintf(os.Stderr, "Ошибка конфигурации: %v\n", err)
		fmt.Fprintf(os.Stderr, "Используйте --help для просмотра доступных опций\n")
		os.Exit(1)
	}

	LogInfo("Config validated: %s", appConfig.Model.Name)

	// Создаём модель приложения
	model := NewModel(appConfig)

	// Создаём и запускаем TUI приложение
	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),
		tea.WithInputTTY(),
	)

	LogInfo("Starting TUI program")

	// Запускаем приложение и обрабатываем ошибки
	if _, err := p.Run(); err != nil {
		LogError("TUI program run failed", err)
		fmt.Fprintf(os.Stderr, "Ошибка при запуске приложения: %v\n", err)
		os.Exit(1)
	}

	LogInfo("Application exited normally")
}
