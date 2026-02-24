package bot

import (
	"context"
	"fmt"
	"io"
	"kbju-bot/internal/config"
	"kbju-bot/internal/services"
	"kbju-bot/pkg/logger"
	"net/http"
	"time"

	tgbot "github.com/go-telegram/bot"
	"github.com/go-telegram/bot/models"
)

type BotHandler struct {
	kbjuService *services.KbjuService
	userService *services.UserService
	log         *logger.Logger
}

func NewBotHandler(kbjuService *services.KbjuService, userService *services.UserService, log *logger.Logger) *BotHandler {
	return &BotHandler{
		kbjuService: kbjuService,
		userService: userService,
		log:         log,
	}
}

func (h *BotHandler) HandleStart(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	user := update.Message.From
	if err := h.userService.UpsertUser(context.Background(), user.ID, user.Username, user.FirstName, user.LastName); err != nil {
		h.log.Error("Failed to upsert user", "error", err)
	}

	helpText := `👋 Привет! Я бот для подсчета КБЖУ.

📝 Я могу принять:
- Текстовое сообщение с описанием еды
- Голосовое сообщение

📊 Команды:
/start - Начать работу
/help - Помощь
/stats - Статистика за сегодня
/week_stats - Статистика за неделю
/reset_day - Сбросить дневную статистику`

	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   helpText,
	})
}

func (h *BotHandler) HandleHelp(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	helpText := `📋 Справка по боту:

Я помогаю считать КБЖУ ваших приемов пищи.

✨ Как использовать:
1. Отправьте текст: "съел 200г курицы" или "яблоко 100 грамм"
2. Отправьте голосовое сообщение: "назови что я съел"

📊 Команды:
/start - Регистрация
/help - Эта справка
/stats - Статистика за сегодня
/week_stats - Статистика за 7 дней
/reset_day - Сбросить дневную статистику`

	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   helpText,
	})
}

func (h *BotHandler) HandleStats(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	userID := update.Message.From.ID

	record, err := h.kbjuService.GetDailyStats(context.Background(), userID)
	if err != nil {
		h.log.Error("Failed to get daily stats", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Ошибка при получении статистики",
		})
		return
	}

	if record == nil {
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "📊 За сегодня записей пока нет.\nПросто отправьте мне что вы съели!",
		})
		return
	}

	statsText := fmt.Sprintf(`📊 Статистика за сегодня (%s):

Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г`,
		record.Date.Format("02.01.2006"),
		record.Calories,
		record.Proteins,
		record.Fats,
		record.Carbs,
	)

	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   statsText,
	})
}

func (h *BotHandler) HandleWeekStats(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	userID := update.Message.From.ID

	records, err := h.kbjuService.GetWeeklyStats(context.Background(), userID)
	if err != nil {
		h.log.Error("Failed to get weekly stats", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Ошибка при получении статистики",
		})
		return
	}

	if len(records) == 0 {
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "📊 За неделю записей пока нет.",
		})
		return
	}

	var totalCal, totalProt, totalFats, totalCarbs float64
	for _, r := range records {
		totalCal += r.Calories
		totalProt += r.Proteins
		totalFats += r.Fats
		totalCarbs += r.Carbs
	}

	daysCount := float64(len(records))
	avgCal := totalCal / daysCount
	avgProt := totalProt / daysCount
	avgFats := totalFats / daysCount
	avgCarbs := totalCarbs / daysCount

	statsText := fmt.Sprintf(`📊 Статистика за неделю (последние %d дней):

Среднее за день:
Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г

Всего за неделю:
Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г`,
		len(records),
		avgCal, avgProt, avgFats, avgCarbs,
		totalCal, totalProt, totalFats, totalCarbs,
	)

	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   statsText,
	})
}

func (h *BotHandler) HandleResetDay(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	userID := update.Message.From.ID

	if err := h.kbjuService.ResetDaily(context.Background(), userID); err != nil {
		h.log.Error("Failed to reset daily stats", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Ошибка при сбросе статистики",
		})
		return
	}

	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   "✅ Дневная статистика сброшена!",
	})
}

func (h *BotHandler) HandleText(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil {
		return
	}

	user := update.Message.From
	text := update.Message.Text

	if err := h.userService.UpsertUser(context.Background(), user.ID, user.Username, user.FirstName, user.LastName); err != nil {
		h.log.Error("Failed to upsert user", "error", err)
	}

	kbju, llmResponse, err := h.kbjuService.ProcessText(context.Background(), user.ID, text)
	if err != nil {
		h.log.Error("Failed to process text", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Произошла ошибка при обработке. Попробуйте позже.",
		})
		return
	}

	if kbju.FoodName == "" {
		kbju.FoodName = text
	}

	response := fmt.Sprintf(`✅ Записано: %s

Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г`,
		kbju.FoodName,
		kbju.Calories,
		kbju.Proteins,
		kbju.Fats,
		kbju.Carbs,
	)

	h.log.Info("Text processed successfully", "user_id", user.ID, "kbju", llmResponse)
	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   response,
	})
}

func (h *BotHandler) HandleVoice(ctx context.Context, b *tgbot.Bot, update *models.Update) {
	if update.Message == nil || update.Message.Voice == nil {
		return
	}

	user := update.Message.From

	if err := h.userService.UpsertUser(context.Background(), user.ID, user.Username, user.FirstName, user.LastName); err != nil {
		h.log.Error("Failed to upsert user", "error", err)
	}

	fileID := update.Message.Voice.FileID

	file, err := b.GetFile(ctx, &tgbot.GetFileParams{FileID: fileID})
	if err != nil {
		h.log.Error("Failed to get voice file", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Не удалось получить голосовое сообщение",
		})
		return
	}

	downloadURL := b.FileDownloadLink(file)
	resp, err := http.Get(downloadURL)
	if err != nil {
		h.log.Error("Failed to download voice file", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Не удалось скачать голосовое сообщение",
		})
		return
	}
	defer resp.Body.Close()

	fileData, err := io.ReadAll(resp.Body)
	if err != nil {
		h.log.Error("Failed to read voice file", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Не удалось прочитать голосовое сообщение",
		})
		return
	}

	kbju, llmResponse, err := h.kbjuService.ProcessAudio(context.Background(), user.ID, fileData, "voice.ogg")
	if err != nil {
		h.log.Error("Failed to process voice", "error", err)
		b.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: update.Message.Chat.ID,
			Text:   "❌ Произошла ошибка при обработке голосового. Попробуйте позже.",
		})
		return
	}

	response := fmt.Sprintf(`✅ Распознано: %s

Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г`,
		kbju.FoodName,
		kbju.Calories,
		kbju.Proteins,
		kbju.Fats,
		kbju.Carbs,
	)

	h.log.Info("Voice processed successfully", "user_id", user.ID, "kbju", llmResponse)
	b.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID: update.Message.Chat.ID,
		Text:   response,
	})
}

type Middleware struct {
	cfg *config.Config
	log *logger.Logger
}

func NewMiddleware(cfg *config.Config, log *logger.Logger) *Middleware {
	return &Middleware{
		cfg: cfg,
		log: log,
	}
}

func (m *Middleware) AccessControl() func(ctx context.Context, b *tgbot.Bot, update *models.Update) bool {
	return func(ctx context.Context, b *tgbot.Bot, update *models.Update) bool {
		if update.Message == nil {
			return true
		}

		userID := update.Message.From.ID

		if !m.cfg.IsUserAllowed(userID) {
			m.log.Warn("Access denied for user", "user_id", userID, "mode", m.cfg.Access.Mode)
			b.SendMessage(ctx, &tgbot.SendMessageParams{
				ChatID: update.Message.Chat.ID,
				Text:   "⛔ Доступ запрещен. Обратитесь к администратору.",
			})
			return false
		}

		return true
	}
}

type Scheduler struct {
	kbjuService *services.KbjuService
	tgbot       *tgbot.Bot
	cfg         *config.Config
	log         *logger.Logger
	ticker      *time.Ticker
	stopCh      chan struct{}
}

func NewScheduler(kbjuService *services.KbjuService, botInstance *tgbot.Bot, cfg *config.Config, log *logger.Logger) *Scheduler {
	return &Scheduler{
		kbjuService: kbjuService,
		tgbot:       botInstance,
		cfg:         cfg,
		log:         log,
		stopCh:      make(chan struct{}),
	}
}

func (s *Scheduler) Start() {
	s.ticker = time.NewTicker(s.cfg.Scheduler.ReportTicker)
	go s.run()
	s.log.Info("Scheduler started", "interval", s.cfg.Scheduler.ReportTicker)
}

func (s *Scheduler) Stop() {
	s.ticker.Stop()
	close(s.stopCh)
	s.log.Info("Scheduler stopped")
}

func (s *Scheduler) run() {
	for {
		select {
		case <-s.ticker.C:
			s.sendDailyReports()
		case <-s.stopCh:
			return
		}
	}
}

func (s *Scheduler) sendDailyReports() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	userIDs, err := s.kbjuService.GetAllActiveUsers(ctx)
	if err != nil {
		s.log.Error("Failed to get active users", "error", err)
		return
	}

	for _, userID := range userIDs {
		record, err := s.kbjuService.GetDailyStats(ctx, userID)
		if err != nil {
			s.log.Error("Failed to get daily stats for user", "user_id", userID, "error", err)
			continue
		}

		if record == nil {
			continue
		}

		recommendation := ""
		if record.Calories > 2000 {
			recommendation = "\n⚠️ Вы превысили дневную норму калорий!"
		} else if record.Calories < 1200 {
			recommendation = "\n💡 Вы можете съесть немного больше."
		}

		report := fmt.Sprintf(`📊 Ежедневный отчет (%s):

Калории: %.0f ккал
Белки: %.1f г
Жиры: %.1f г
Углеводы: %.1f г%s`,
			record.Date.Format("02.01.2006"),
			record.Calories,
			record.Proteins,
			record.Fats,
			record.Carbs,
			recommendation,
		)

		s.tgbot.SendMessage(ctx, &tgbot.SendMessageParams{
			ChatID: userID,
			Text:   report,
		})
	}
}
