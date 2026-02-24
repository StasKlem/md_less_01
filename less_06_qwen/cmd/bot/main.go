// Package main точка входа приложения Telegram бота для учета КБЖУ.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	tgbotapi "gopkg.in/telebot.v3"

	// Импортируем SQLite драйвер для регистрации
	_ "github.com/mattn/go-sqlite3"

	"github.com/stasklem/kbju-bot/internal/bot"
	"github.com/stasklem/kbju-bot/internal/config"
	"github.com/stasklem/kbju-bot/internal/llm"
	"github.com/stasklem/kbju-bot/internal/logger"
	"github.com/stasklem/kbju-bot/internal/repository/sqlite"
	"github.com/stasklem/kbju-bot/internal/services"
)

const (
	// appName название приложения для логов.
	appName = "kbju-bot"
	// shutdownTimeout таймаут graceful shutdown.
	shutdownTimeout = 30 * time.Second
)

func main() {
	// Загружаем конфигурацию
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Создаем логгер
	log := logger.New(cfg.Log.Level, cfg.Log.Format, os.Stdout)
	log.Info("starting application", "name", appName, "version", getVersion())

	// Инициализируем базу данных
	log.Info("initializing database", "path", cfg.Database.Path)
	db, err := sqlite.New(cfg.Database)
	if err != nil {
		log.Error("failed to initialize database", "error", err)
		os.Exit(1)
	}
	defer func() {
		if err := db.Close(); err != nil {
			log.Error("failed to close database", "error", err)
		}
	}()

	// Выполняем миграции
	if err := db.AutoMigrate(); err != nil {
		log.Error("failed to run migrations", "error", err)
		os.Exit(1)
	}
	log.Info("database migrations completed")

	// Создаем репозитории
	userRepo := sqlite.NewUserRepository(db.DB)
	recordRepo := sqlite.NewDailyRecordRepository(db.DB)
	messageLogRepo := sqlite.NewMessageLogRepository(db.DB)

	// Создаем LLM клиент
	llmClient := llm.NewClient(llm.ClientConfig{
		Provider: cfg.LLM.Provider,
		APIKey:   cfg.LLM.APIKey,
		Model:    cfg.LLM.Model,
		BaseURL:  cfg.LLM.BaseURL,
		Timeout:  cfg.LLM.Timeout,
	})
	log.Info("LLM client initialized", "provider", cfg.LLM.Provider, "model", cfg.LLM.Model)

	// Создаем сервис
	kbjuService := services.NewKBJUService(services.KBJUServiceConfig{
		UserRepo:       userRepo,
		RecordRepo:     recordRepo,
		MessageLogRepo: messageLogRepo,
		LLMProvider:    llmClient,
		TXManager:      db,
	})

	// Создаем Telegram бота
	tgBot, err := tgbotapi.NewBot(tgbotapi.Settings{
		Token: cfg.Telegram.BotToken,
	})
	if err != nil {
		log.Error("failed to create telegram bot", "error", err)
		os.Exit(1)
	}
	log.Info("telegram bot initialized")

	// Создаем обертку бота с обработчиками
	botInstance := bot.New(bot.Config{
		Bot:          tgBot,
		Service:      kbjuService,
		AccessConfig: &cfg.AccessControl,
		Logger:       log.With("component", "bot"),
	})

	// Создаем планировщик отчетов
	scheduler, err := bot.NewReportScheduler(bot.ReportSchedulerConfig{
		UserRepo: userRepo,
		Bot:      botInstance,
		Logger:   log.With("component", "scheduler"),
		Timezone: cfg.Report.Timezone,
		SendTime: cfg.Report.SendTime,
	})
	if err != nil {
		log.Error("failed to create report scheduler", "error", err)
		os.Exit(1)
	}

	// Запускаем планировщик
	if err := scheduler.Start(); err != nil {
		log.Error("failed to start report scheduler", "error", err)
		os.Exit(1)
	}

	// Каналы для graceful shutdown
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, syscall.SIGINT, syscall.SIGTERM)

	// Запускаем бота в горутине
	errChan := make(chan error, 1)
	go func() {
		log.Info("starting telegram bot polling")
		botInstance.Start()
		// Start() блокирующий, если вернулись - значит произошла ошибка или остановка
		errChan <- nil
	}()

	log.Info("application started successfully")

	// Ожидаем сигнал завершения или ошибку
	select {
	case sig := <-stopChan:
		log.Info("received shutdown signal", "signal", sig)
	case err := <-errChan:
		log.Error("bot error", "error", err)
	}

	// Graceful shutdown
	log.Info("starting graceful shutdown")

	// Останавливаем планировщик
	scheduler.Stop()

	// Останавливаем бота
	botInstance.Stop()

	// Закрываем базу данных
	if err := db.Close(); err != nil {
		log.Error("error closing database", "error", err)
	}

	log.Info("application stopped")
}

// getVersion возвращает версию приложения.
// В production версии следует использовать ldflags для установки версии.
func getVersion() string {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		return "dev"
	}
	return version
}
