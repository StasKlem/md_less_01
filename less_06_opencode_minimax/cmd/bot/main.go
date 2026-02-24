package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	appBot "kbju-bot/internal/bot"
	"kbju-bot/internal/config"
	"kbju-bot/internal/llm"
	"kbju-bot/internal/repository/sqlite"
	"kbju-bot/internal/services"
	appLogger "kbju-bot/pkg/logger"

	tgbot "github.com/go-telegram/bot"
	"github.com/go-telegram/bot/models"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func main() {
	fmt.Println("Starting KBJU Bot...")

	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}

	log := appLogger.New(cfg.Logging.Level, cfg.Logging.Format)
	log.Info("Config loaded", "access_mode", cfg.Access.Mode)

	db, err := initDatabase(cfg, log)
	if err != nil {
		log.Error("Failed to initialize database", "error", err)
		os.Exit(1)
	}
	log.Info("Database initialized")

	llmClient := llm.NewClient(llm.LLMConfig{
		APIKey:  cfg.LLM.APIKey,
		BaseURL: cfg.LLM.BaseURL,
		Model:   cfg.LLM.Model,
		Timeout: cfg.LLM.TimeOut,
	})
	log.Info("LLM client initialized")

	kbjuService := services.NewKbjuService(llmClient, db, log)
	userService := services.NewUserService(db, log)
	log.Info("Services initialized")

	botHandler := appBot.NewBotHandler(kbjuService, userService, log)
	middleware := appBot.NewMiddleware(cfg, log)

	tb, err := tgbot.New(cfg.Bot.Token)
	if err != nil {
		log.Error("Failed to create bot", "error", err)
		os.Exit(1)
	}
	log.Info("Telegram bot created")

	accessMiddleware := middleware.AccessControl()

	tb.RegisterHandlerMatchFunc(func(update *models.Update) bool {
		if update.Message == nil {
			return false
		}
		if update.Message.Text == "/start" {
			return true
		}
		if update.Message.Text == "/help" {
			return true
		}
		if update.Message.Text == "/stats" {
			return true
		}
		if update.Message.Text == "/week_stats" {
			return true
		}
		if update.Message.Text == "/reset_day" {
			return true
		}
		return false
	}, func(ctx context.Context, b *tgbot.Bot, update *models.Update) {
		if !accessMiddleware(ctx, b, update) {
			return
		}
		switch update.Message.Text {
		case "/start":
			botHandler.HandleStart(ctx, b, update)
		case "/help":
			botHandler.HandleHelp(ctx, b, update)
		case "/stats":
			botHandler.HandleStats(ctx, b, update)
		case "/week_stats":
			botHandler.HandleWeekStats(ctx, b, update)
		case "/reset_day":
			botHandler.HandleResetDay(ctx, b, update)
		}
	})

	tb.RegisterHandler(tgbot.HandlerTypeMessageText, "", tgbot.MatchTypeExact, func(ctx context.Context, b *tgbot.Bot, update *models.Update) {
		if update.Message == nil {
			return
		}
		if !accessMiddleware(ctx, b, update) {
			return
		}
		botHandler.HandleText(ctx, b, update)
	})

	tb.RegisterHandlerMatchFunc(func(update *models.Update) bool {
		if update.Message == nil {
			return false
		}
		return update.Message.Voice != nil
	}, func(ctx context.Context, b *tgbot.Bot, update *models.Update) {
		if update.Message == nil {
			return
		}
		if !accessMiddleware(ctx, b, update) {
			return
		}
		botHandler.HandleVoice(ctx, b, update)
	})

	scheduler := appBot.NewScheduler(kbjuService, tb, cfg, log)
	scheduler.Start()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		log.Info("Shutting down...")
		scheduler.Stop()
		sqlDB, err := db.DB()
		if err != nil {
			log.Error("Failed to get database instance", "error", err)
		} else {
			if err := sqlDB.Close(); err != nil {
				log.Error("Failed to close database", "error", err)
			}
		}
		log.Info("Bot stopped")
	}()

	log.Info("Bot is running...")
	tb.Start(ctx)
}

func initDatabase(cfg *config.Config, log *appLogger.Logger) (*gorm.DB, error) {
	db, err := sqlite.New(cfg.Database.Path, logger.Default.LogMode(logger.Silent))
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	if err := sqlite.Migrate(db); err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)

	return db, nil
}
