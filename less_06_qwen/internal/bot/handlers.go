// Package bot предоставляет обработчики команд и сообщений Telegram бота.
package bot

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	tgbotapi "gopkg.in/telebot.v3"

	"github.com/stasklem/kbju-bot/internal/config"
	"github.com/stasklem/kbju-bot/internal/logger"
	"github.com/stasklem/kbju-bot/internal/services"
)

// Bot обертка над Telegram ботом с middleware и обработчиками.
type Bot struct {
	bot     *tgbotapi.Bot
	service *services.KBJUService
	config  *config.AccessControlConfig
	logger  *logger.Logger
}

// Config содержит настройки для создания бота.
type Config struct {
	Bot          *tgbotapi.Bot
	Service      *services.KBJUService
	AccessConfig *config.AccessControlConfig
	Logger       *logger.Logger
}

// New создает новый экземпляр бота с зарегистрированными обработчиками.
func New(cfg Config) *Bot {
	b := &Bot{
		bot:     cfg.Bot,
		service: cfg.Service,
		config:  cfg.AccessConfig,
		logger:  cfg.Logger,
	}

	b.setupHandlers()
	return b
}

// setupHandlers регистрирует все обработчики команд и сообщений.
func (b *Bot) setupHandlers() {
	// Команды
	b.bot.Handle("/start", b.middleware(b.handleStart))
	b.bot.Handle("/help", b.middleware(b.handleHelp))
	b.bot.Handle("/stats", b.middleware(b.handleStats))
	b.bot.Handle("/reset_day", b.middleware(b.handleResetDay))

	// Обработка текстовых сообщений (исключая команды)
	b.bot.Handle(&tgbotapi.Message{Text: ""}, b.middleware(b.handleTextMessage))

	// Обработка голосовых сообщений
	b.bot.Handle(tgbotapi.OnVoice, b.middleware(b.handleVoiceMessage))

	// Обработка аудио файлов
	b.bot.Handle(tgbotapi.OnAudio, b.middleware(b.handleAudioMessage))
}

// middleware проверяет доступ пользователя перед выполнением обработчика.
func (b *Bot) middleware(handler tgbotapi.HandlerFunc) tgbotapi.HandlerFunc {
	return func(c tgbotapi.Context) error {
		userID := c.Sender().ID

		// Проверка доступа
		if !b.config.IsUserAllowed(userID) {
			b.logger.Warn("access denied", "user_id", userID, "username", c.Sender().Username)
			return c.Reply("❌ Доступ запрещен. Вы не находитесь в списке разрешенных пользователей.")
		}

		b.logger.Debug("access granted", "user_id", userID, "username", c.Sender().Username)
		return handler(c)
	}
}

// handleStart обрабатывает команду /start.
func (b *Bot) handleStart(c tgbotapi.Context) error {
	user := c.Sender()
	message := fmt.Sprintf(
		"👋 Привет, %s!\n\n"+
			"Я бот для учета КБЖУ (калории, белки, жиры, углеводы).\n\n"+
			"📝 *Что я умею:*\n"+
			"• Анализировать описание еды и рассчитывать КБЖУ\n"+
			"• Распознавать голосовые сообщения\n"+
			"• Вести ежедневную статистику\n"+
			"• Формировать отчеты\n\n"+
			"📌 *Команды:*\n"+
			"/stats - статистика за сегодня\n"+
			"/reset_day - сбросить записи за сегодня\n"+
			"/help - справка\n\n"+
			"Просто отправьте мне описание еды или голосовое сообщение!",
		getUserName(user),
	)

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// handleHelp обрабатывает команду /help.
func (b *Bot) handleHelp(c tgbotapi.Context) error {
	message := `📖 *Справка по боту КБЖУ*

*Как использовать:*
1. Отправьте описание еды (например: "Овсянка с молоком и бананом, 200г")
2. Или отправьте голосовое сообщение с описанием
3. Бот распознает данные и сохранит КБЖУ

*Команды:*
/start - начать работу
/stats - показать статистику за сегодня
/reset_day - удалить все записи за сегодня
/help - эта справка

*Ежедневный отчет:*
Бот автоматически отправит отчет в 21:00 с рекомендациями.

*Вопросы?*
Обратитесь к разработчику.`

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// handleStats обрабатывает команду /stats.
func (b *Bot) handleStats(c tgbotapi.Context) error {
	userID := c.Sender().ID
	ctx := context.Background()

	stats, err := b.service.GetDailyStats(ctx, userID)
	if err != nil {
		b.logger.Error("get daily stats", "error", err, "user_id", userID)
		return c.Reply("❌ Произошла ошибка при получении статистики.")
	}

	message := fmt.Sprintf(
		"📊 *Статистика за сегодня*\n\n"+
			"🔥 Калории: *%d ккал*\n"+
			"🥩 Белки: *%.1f г*\n"+
			"🥑 Жиры: *%.1f г*\n"+
			"🍞 Углеводы: *%.1f г*\n\n"+
			"📝 Записей: %d",
		stats.Calories,
		stats.Proteins,
		stats.Fats,
		stats.Carbs,
		stats.RecordCount,
	)

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// handleResetDay обрабатывает команду /reset_day.
func (b *Bot) handleResetDay(c tgbotapi.Context) error {
	userID := c.Sender().ID
	ctx := context.Background()

	if err := b.service.ResetDay(ctx, userID); err != nil {
		b.logger.Error("reset day", "error", err, "user_id", userID)
		return c.Reply("❌ Произошла ошибка при сбросе записей.")
	}

	return c.Reply("✅ Все записи за сегодня удалены.")
}

// handleTextMessage обрабатывает текстовые сообщения.
func (b *Bot) handleTextMessage(c tgbotapi.Context) error {
	m := c.Message()
	if m == nil {
		return nil
	}

	text := m.Text
	if text == "" {
		return nil
	}

	// Игнорируем команды (они уже обработаны)
	if len(text) > 0 && text[0] == '/' {
		return nil
	}

	user := m.Sender
	if user == nil {
		return nil
	}

	b.logger.Info("processing text message", "user_id", user.ID, "text_length", len(text))

	// Показываем индикатор набора
	_ = b.bot.Notify(m.Chat, tgbotapi.Typing)

	ctx := context.Background()
	result, err := b.service.ProcessTextMessage(
		ctx,
		user.ID,
		user.Username,
		user.FirstName,
		user.LastName,
		text,
	)
	if err != nil {
		b.logger.Error("process text message", "error", err, "user_id", user.ID)
		return c.Reply("❌ Произошла ошибка при анализе сообщения. Попробуйте еще раз.")
	}

	message := fmt.Sprintf(
		"🍽️ *%s*\n\n"+
			"🔥 Калории: *%d ккал*\n"+
			"🥩 Белки: *%.1f г*\n"+
			"🥑 Жиры: *%.1f г*\n"+
			"🍞 Углеводы: *%.1f г*\n\n"+
			"✅ Запись сохранена!",
		result.FoodName,
		result.Calories,
		result.Proteins,
		result.Fats,
		result.Carbs,
	)

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// downloadFile загружает файл из Telegram.
func (b *Bot) downloadFile(fileID string) ([]byte, error) {
	// Создаем объект File с FileID
	file := &tgbotapi.File{FileID: fileID}

	// Получаем поток данных файла из Telegram
	rc, err := b.bot.File(file)
	if err != nil {
		return nil, fmt.Errorf("get file: %w", err)
	}
	defer rc.Close()

	// Читаем все данные
	data, err := io.ReadAll(rc)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	return data, nil
}

// handleVoiceMessage обрабатывает голосовые сообщения.
func (b *Bot) handleVoiceMessage(c tgbotapi.Context) error {
	m := c.Message()
	if m == nil {
		return nil
	}

	voice := m.Voice
	if voice == nil {
		return nil
	}

	user := m.Sender
	if user == nil {
		return nil
	}

	b.logger.Info("processing voice message", "user_id", user.ID, "duration", voice.Duration)

	// Показываем индикатор набора
	_ = b.bot.Notify(m.Chat, tgbotapi.Typing)

	// Скачиваем файл
	fileData, err := b.downloadFile(voice.FileID)
	if err != nil {
		b.logger.Error("download voice file", "error", err, "user_id", user.ID)
		return c.Reply("❌ Не удалось загрузить голосовое сообщение.")
	}

	ctx := context.Background()
	result, err := b.service.ProcessVoiceMessage(
		ctx,
		user.ID,
		user.Username,
		user.FirstName,
		user.LastName,
		fileData,
		"audio/ogg", // Telegram voice messages are typically OGG
	)
	if err != nil {
		b.logger.Error("process voice message", "error", err, "user_id", user.ID)
		return c.Reply("❌ Произошла ошибка при распознавании голоса. Попробуйте еще раз.")
	}

	message := fmt.Sprintf(
		"🎤 *Распознано: %s*\n\n"+
			"🔥 Калории: *%d ккал*\n"+
			"🥩 Белки: *%.1f г*\n"+
			"🥑 Жиры: *%.1f г*\n"+
			"🍞 Углеводы: *%.1f г*\n\n"+
			"✅ Запись сохранена!",
		result.FoodName,
		result.Calories,
		result.Proteins,
		result.Fats,
		result.Carbs,
	)

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// handleAudioMessage обрабатывает аудио файлы.
func (b *Bot) handleAudioMessage(c tgbotapi.Context) error {
	m := c.Message()
	if m == nil {
		return nil
	}

	audio := m.Audio
	if audio == nil {
		return nil
	}

	user := m.Sender
	if user == nil {
		return nil
	}

	b.logger.Info("processing audio file", "user_id", user.ID, "file_name", audio.FileName)

	// Показываем индикатор набора
	_ = b.bot.Notify(m.Chat, tgbotapi.Typing)

	// Скачиваем файл
	fileData, err := b.downloadFile(audio.FileID)
	if err != nil {
		b.logger.Error("download audio file", "error", err, "user_id", user.ID)
		return c.Reply("❌ Не удалось загрузить аудио файл.")
	}

	ctx := context.Background()
	mimeType := "audio/mpeg" // Default to MP3

	result, err := b.service.ProcessVoiceMessage(
		ctx,
		user.ID,
		user.Username,
		user.FirstName,
		user.LastName,
		fileData,
		mimeType,
	)
	if err != nil {
		b.logger.Error("process audio message", "error", err, "user_id", user.ID)
		return c.Reply("❌ Произошла ошибка при распознавании аудио. Попробуйте еще раз.")
	}

	message := fmt.Sprintf(
		"🎵 *Распознано: %s*\n\n"+
			"🔥 Калории: *%d ккал*\n"+
			"🥩 Белки: *%.1f г*\n"+
			"🥑 Жиры: *%.1f г*\n"+
			"🍞 Углеводы: *%.1f г*\n\n"+
			"✅ Запись сохранена!",
		result.FoodName,
		result.Calories,
		result.Proteins,
		result.Fats,
		result.Carbs,
	)

	return c.Reply(message, tgbotapi.ModeMarkdown)
}

// SendDailyReport отправляет ежедневный отчет пользователю.
func (b *Bot) SendDailyReport(ctx context.Context, userID int64, date time.Time) error {
	report, err := b.service.GenerateReport(ctx, userID, date)
	if err != nil {
		return fmt.Errorf("generate report: %w", err)
	}

	chat := &tgbotapi.Chat{ID: userID}
	_, err = b.bot.Send(chat, report, tgbotapi.ModeMarkdown)
	if err != nil {
		// Игнорируем ошибки, если пользователь заблокировал бота
		var botErr *tgbotapi.Error
		if errors.As(err, &botErr) && botErr.Code == 403 {
			b.logger.Info("user blocked bot", "user_id", userID)
			return nil
		}
		return fmt.Errorf("send report: %w", err)
	}

	return nil
}

// Start запускает бота.
func (b *Bot) Start() {
	b.logger.Info("starting bot")
	b.bot.Start()
}

// Stop останавливает бота.
func (b *Bot) Stop() {
	b.logger.Info("stopping bot")
	b.bot.Stop()
}

// getUserName возвращает имя пользователя для отображения.
func getUserName(user *tgbotapi.User) string {
	if user.Username != "" {
		return "@" + user.Username
	}
	if user.FirstName != "" {
		return user.FirstName
	}
	return "Пользователь"
}

// bufferPool - пул буферов для эффективной работы с памятью.
var bufferPool = sync.Pool{
	New: func() interface{} {
		return new(bytes.Buffer)
	},
}
