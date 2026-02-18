// Package main - точка входа приложения LLM Chat Client.
// Реализует dependency injection для всех компонентов.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"

	"llm-client/internal/config"
	"llm-client/internal/logger"
	"llm-client/internal/ui"
)

const (
	// appName - имя приложения
	appName = "LLM Chat Client"
	// version - версия приложения
	version = "2.0.0"
)

// CLIConfig хранит настройки из командной строки
type CLIConfig struct {
	ConfigFile   string
	Address      string
	Model        string
	SystemPrompt string
	Temperature  float64
	TopP         float64
	ShowConfig   bool
	InitConfig   bool
	ShowVersion  bool
}

func main() {
	os.Exit(run(os.Args[1:]))
}

// run выполняет основную логику приложения и возвращает код выхода
func run(args []string) int {
	// Парсим аргументы командной строки
	cli := parseCLIConfig(args)

	// Обработка специальных флагов
	if cli.ShowVersion {
		fmt.Printf("%s version %s\n", appName, version)
		return 0
	}

	if cli.ShowConfig {
		printDefaultConfig()
		return 0
	}

	if cli.InitConfig {
		path := cli.ConfigFile
		if path == "" {
			path = "config.json"
		}
		if err := config.CreateDefaultConfigFile(path); err != nil {
			fmt.Fprintf(os.Stderr, "Ошибка создания конфигурации: %v\n", err)
			return 1
		}
		fmt.Printf("Config file created: %s\n", path)
		return 0
	}

	// Загружаем конфигурацию
	appConfig, err := loadConfig(cli)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Ошибка загрузки конфигурации: %v\n", err)
		fmt.Fprintf(os.Stderr, "Используйте --help для просмотра доступных опций\n")
		return 1
	}

	// Инициализируем логгер
	log := initLogger(appConfig)
	defer log.Close()

	log.Info("Application starting",
		"version", version,
		"address", appConfig.Server.Address,
		"model", appConfig.Model.Name,
	)

	// Создаём модель приложения с dependency injection
	model := ui.NewModel(appConfig, ui.WithLogger(log))

	// Создаём и запускаем TUI приложение
	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),
		tea.WithInputTTY(),
		tea.WithMouseCellMotion(),
	)

	log.Info("Starting TUI program")

	// Запускаем обработку сигналов
	cancelCtx, cancel := context.WithCancel(context.Background())
	defer cancel()

	setupSignalHandler(cancelCtx, log)

	// Запускаем приложение и обрабатываем ошибки
	if _, err := p.Run(); err != nil {
		log.Error("TUI program run failed", "error", err)
		fmt.Fprintf(os.Stderr, "Ошибка при запуске приложения: %v\n", err)
		return 1
	}

	log.Info("Application exited normally")
	return 0
}

// parseCLIConfig парсит аргументы командной строки
func parseCLIConfig(args []string) *CLIConfig {
	cli := &CLIConfig{}

	fs := flag.NewFlagSet(appName, flag.ContinueOnError)
	fs.StringVar(&cli.ConfigFile, "config", "", "Path to config file (or use LLM_CLIENT_CONFIG env)")
	fs.StringVar(&cli.Address, "address", "", "LLM server address")
	fs.StringVar(&cli.Address, "a", "", "Shorthand for -address")
	fs.StringVar(&cli.Model, "model", "", "Model name to use")
	fs.StringVar(&cli.Model, "m", "", "Shorthand for -model")
	fs.StringVar(&cli.SystemPrompt, "system", "", "System prompt")
	fs.StringVar(&cli.SystemPrompt, "s", "", "Shorthand for -system")
	fs.Float64Var(&cli.Temperature, "temperature", 0, "Temperature (0.0-2.0)")
	fs.Float64Var(&cli.Temperature, "t", 0, "Shorthand for -temperature")
	fs.Float64Var(&cli.TopP, "top-p", 0, "Top P (0.0-1.0)")
	fs.Float64Var(&cli.TopP, "p", 0, "Shorthand for -top-p")
	fs.BoolVar(&cli.ShowConfig, "show-config", false, "Show default config and exit")
	fs.BoolVar(&cli.InitConfig, "init-config", false, "Create default config file")
	fs.BoolVar(&cli.ShowVersion, "version", false, "Show version and exit")
	fs.BoolVar(&cli.ShowVersion, "v", false, "Shorthand for -version")

	if err := fs.Parse(args); err != nil {
		return cli
	}

	return cli
}

// loadConfig загружает и валидирует конфигурацию
func loadConfig(cli *CLIConfig) (*config.Config, error) {
	// Загружаем конфигурацию из файла
	cfg, err := config.Load(cli.ConfigFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	// Переопределяем из CLI флагов
	if cli.Address != "" {
		cfg.Server.Address = cli.Address
	}
	if cli.Model != "" {
		cfg.Model.Name = cli.Model
	}
	if cli.SystemPrompt != "" {
		cfg.Model.SystemPrompt = cli.SystemPrompt
	}
	if cli.Temperature != 0 {
		cfg.Model.Temperature = cli.Temperature
	}
	if cli.TopP != 0 {
		cfg.Model.TopP = cli.TopP
	}

	// Повторно валидируем после применения CLI флагов
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return cfg, nil
}

// initLogger инициализирует логгер с заданной конфигурацией
func initLogger(cfg *config.Config) *logger.Logger {
	logCfg := logger.Config{
		Enabled:   cfg.Log.Enabled,
		FilePath:  cfg.Log.FilePath,
		Level:     logger.ParseLevel(cfg.Log.Level),
		AddSource: cfg.Log.Level == "debug",
	}

	log := logger.NewLogger(logCfg)
	logger.SetDefault(log)

	return log
}

// setupSignalHandler настраивает обработку сигналов ОС
func setupSignalHandler(ctx context.Context, log *logger.Logger) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		log.Info("Received signal, shutting down", "signal", sig)
		// Контекст будет отменён через cancel в main
		_ = ctx
	}()
}

// printDefaultConfig выводит конфигурацию по умолчанию в stdout
func printDefaultConfig() {
	cfg := config.DefaultConfig()
	data, err := cfg.ToJSON()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling config: %v\n", err)
		return
	}
	fmt.Println(string(data))
}
