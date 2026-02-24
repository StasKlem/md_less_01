// Package services содержит бизнес-логику приложения.
package services

import (
	"context"
	"fmt"
	"time"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/llm"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// KBJUService предоставляет бизнес-логику для работы с КБЖУ.
type KBJUService struct {
	userRepo       repository.UserRepository
	recordRepo     repository.DailyRecordRepository
	messageLogRepo repository.MessageLogRepository
	llmProvider    llm.LLMProvider
	txManager      repository.TransactionManager
}

// KBJUServiceConfig содержит зависимости для KBJUService.
type KBJUServiceConfig struct {
	UserRepo       repository.UserRepository
	RecordRepo     repository.DailyRecordRepository
	MessageLogRepo repository.MessageLogRepository
	LLMProvider    llm.LLMProvider
	TXManager      repository.TransactionManager
}

// NewKBJUService создает новый KBJUService.
func NewKBJUService(cfg KBJUServiceConfig) *KBJUService {
	return &KBJUService{
		userRepo:       cfg.UserRepo,
		recordRepo:     cfg.RecordRepo,
		messageLogRepo: cfg.MessageLogRepo,
		llmProvider:    cfg.LLMProvider,
		txManager:      cfg.TXManager,
	}
}

// ProcessTextMessage обрабатывает текстовое сообщение и возвращает КБЖУ.
func (s *KBJUService) ProcessTextMessage(ctx context.Context, userID int64, username, firstName, lastName, text string) (*domain.KBJUResult, error) {
	// Создаем или получаем пользователя
	user, err := s.userRepo.GetOrCreate(ctx, userID, username, firstName, lastName)
	if err != nil {
		return nil, fmt.Errorf("get or create user: %w", err)
	}

	// Отправляем текст в LLM
	result, llmErr := s.llmProvider.SendText(ctx, text)

	// Логируем сообщение
	logEntry := &domain.MessageLog{
		UserID:      user.ID,
		MessageType: "text",
		Content:     text,
	}
	if llmErr != nil {
		logEntry.Error = llmErr.Error()
	} else {
		logEntry.LLMResponse = fmt.Sprintf("%+v", result)
	}

	// Игнорируем ошибку логирования
	_ = s.messageLogRepo.Create(ctx, logEntry)

	if llmErr != nil {
		return nil, fmt.Errorf("send to LLM: %w", llmErr)
	}

	// Сохраняем запись КБЖУ в транзакции
	err = s.txManager.WithTransaction(ctx, func(txCtx context.Context) error {
		record := result.ToDailyRecord(user.ID, time.Now(), text)
		return s.recordRepo.Create(txCtx, &record)
	})
	if err != nil {
		// Не прерываем работу, если не удалось сохранить
		return result, fmt.Errorf("save record (non-critical): %w", err)
	}

	return result, nil
}

// ProcessVoiceMessage обрабатывает голосовое сообщение и возвращает КБЖУ.
func (s *KBJUService) ProcessVoiceMessage(ctx context.Context, userID int64, username, firstName, lastName string, audioData []byte, mimeType string) (*domain.KBJUResult, error) {
	// Создаем или получаем пользователя
	user, err := s.userRepo.GetOrCreate(ctx, userID, username, firstName, lastName)
	if err != nil {
		return nil, fmt.Errorf("get or create user: %w", err)
	}

	// Отправляем аудио в LLM
	result, llmErr := s.llmProvider.SendAudio(ctx, audioData, mimeType)

	// Логируем сообщение
	logEntry := &domain.MessageLog{
		UserID:      user.ID,
		MessageType: "voice",
		Content:     fmt.Sprintf("[audio: %d bytes]", len(audioData)),
	}
	if llmErr != nil {
		logEntry.Error = llmErr.Error()
	} else {
		logEntry.LLMResponse = fmt.Sprintf("%+v", result)
	}

	// Игнорируем ошибку логирования
	_ = s.messageLogRepo.Create(ctx, logEntry)

	if llmErr != nil {
		return nil, fmt.Errorf("send audio to LLM: %w", llmErr)
	}

	// Сохраняем запись КБЖУ в транзакции
	err = s.txManager.WithTransaction(ctx, func(txCtx context.Context) error {
		record := result.ToDailyRecord(user.ID, time.Now(), logEntry.Content)
		return s.recordRepo.Create(txCtx, &record)
	})
	if err != nil {
		return result, fmt.Errorf("save record (non-critical): %w", err)
	}

	return result, nil
}

// GetDailyStats получает статистику КБЖУ за текущий день.
func (s *KBJUService) GetDailyStats(ctx context.Context, userID int64) (*domain.DailyStats, error) {
	now := time.Now()
	return s.recordRepo.GetDailyStats(ctx, userID, now)
}

// GetDailyStatsForDate получает статистику КБЖУ за указанную дату.
func (s *KBJUService) GetDailyStatsForDate(ctx context.Context, userID int64, date time.Time) (*domain.DailyStats, error) {
	return s.recordRepo.GetDailyStats(ctx, userID, date)
}

// ResetDay удаляет все записи КБЖУ за текущий день.
func (s *KBJUService) ResetDay(ctx context.Context, userID int64) error {
	now := time.Now()
	return s.recordRepo.DeleteByDate(ctx, userID, now)
}

// GenerateReport генерирует текстовый отчет за день.
func (s *KBJUService) GenerateReport(ctx context.Context, userID int64, date time.Time) (string, error) {
	stats, err := s.recordRepo.GetDailyStats(ctx, userID, date)
	if err != nil {
		return "", fmt.Errorf("get daily stats: %w", err)
	}

	// Формируем рекомендации
	recommendations := s.generateRecommendations(stats)

	report := fmt.Sprintf(`📊 *Отчет за %s*

🔥 Калории: %d ккал
🥩 Белки: %.1f г
🥑 Жиры: %.1f г
🍞 Углеводы: %.1f г

📝 Записей: %d

%s`,
		date.Format("02.01.2006"),
		stats.Calories,
		stats.Proteins,
		stats.Fats,
		stats.Carbs,
		stats.RecordCount,
		recommendations,
	)

	return report, nil
}

// generateRecommendations генерирует рекомендации на основе статистики.
func (s *KBJUService) generateRecommendations(stats *domain.DailyStats) string {
	if stats.RecordCount == 0 {
		return "📭 За день не было записей. Начните отслеживать питание!"
	}

	var rec string

	// Рекомендации по калориям
	if stats.Calories < 1200 {
		rec += "⚠️ Низкое потребление калорий. Убедитесь, что получаете достаточно энергии.\n"
	} else if stats.Calories > 3500 {
		rec += "⚠️ Высокое потребление калорий. Обратите внимание на размер порций.\n"
	}

	// Рекомендации по белкам
	proteinRatio := stats.Proteins / float64(stats.Calories) * 4 * 100 // процент калорий из белков
	if proteinRatio < 10 {
		rec += "💪 Попробуйте увеличить потребление белка для лучшего насыщения.\n"
	}

	// Рекомендации по жирам
	fatRatio := stats.Fats / float64(stats.Calories) * 9 * 100 // процент калорий из жиров
	if fatRatio > 40 {
		rec += "🥑 Потребление жиров выше рекомендуемого. Сбалансируйте рацион.\n"
	}

	if rec == "" {
		rec = "✅ Хороший баланс! Продолжайте в том же духе."
	}

	return rec
}
