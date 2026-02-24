package bot

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/robfig/cron/v3"

	"github.com/stasklem/kbju-bot/internal/logger"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// ReportScheduler управляет планировщиком ежедневных отчетов.
type ReportScheduler struct {
	cron         *cron.Cron
	userRepo     repository.UserRepository
	bot          *Bot
	logger       *logger.Logger
	timezone     *time.Location
	sendTime     string
	mu           sync.RWMutex
	userIDs      []int64
}

// ReportSchedulerConfig содержит настройки планировщика.
type ReportSchedulerConfig struct {
	UserRepo repository.UserRepository
	Bot      *Bot
	Logger   *logger.Logger
	Timezone string
	SendTime string
}

// NewReportScheduler создает новый планировщик отчетов.
func NewReportScheduler(cfg ReportSchedulerConfig) (*ReportScheduler, error) {
	loc, err := time.LoadLocation(cfg.Timezone)
	if err != nil {
		return nil, fmt.Errorf("load timezone: %w", err)
	}

	s := &ReportScheduler{
		cron:     cron.New(cron.WithLocation(loc)),
		userRepo: cfg.UserRepo,
		bot:      cfg.Bot,
		logger:   cfg.Logger,
		timezone: loc,
		sendTime: cfg.SendTime,
		userIDs:  make([]int64, 0),
	}

	return s, nil
}

// Start запускает планировщик.
func (s *ReportScheduler) Start() error {
	// Парсим время отчета
	_, err := s.cron.AddFunc(s.sendTime, s.sendReports)
	if err != nil {
		return fmt.Errorf("add cron job: %w", err)
	}

	s.cron.Start()
	s.logger.Info("report scheduler started", "send_time", s.sendTime, "timezone", s.timezone.String())

	return nil
}

// Stop останавливает планировщик.
func (s *ReportScheduler) Stop() {
	ctx := s.cron.Stop()
	<-ctx.Done()
	s.logger.Info("report scheduler stopped")
}

// RefreshUsers обновляет список пользователей для рассылки.
func (s *ReportScheduler) RefreshUsers(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Получаем всех пользователей из БД
	// В реальной реализации нужен метод GetAllUsers в репозитории
	// Для простоты используем заглушку - в production нужно добавить метод
	s.userIDs = make([]int64, 0)

	return nil
}

// sendReports отправляет отчеты всем пользователям.
func (s *ReportScheduler) sendReports() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	s.mu.RLock()
	userIDs := make([]int64, len(s.userIDs))
	copy(userIDs, s.userIDs)
	s.mu.RUnlock()

	yesterday := time.Now().AddDate(0, 0, -1)
	sentCount := 0
	errorCount := 0

	for _, userID := range userIDs {
		if err := s.bot.SendDailyReport(ctx, userID, yesterday); err != nil {
			s.logger.Error("send daily report", "error", err, "user_id", userID)
			errorCount++
		} else {
			sentCount++
		}

		// Небольшая задержка между отправками
		select {
		case <-ctx.Done():
			return
		case <-time.After(100 * time.Millisecond):
		}
	}

	s.logger.Info("daily reports sent", "sent", sentCount, "errors", errorCount)
}

// AddUser добавляет пользователя в список рассылки.
func (s *ReportScheduler) AddUser(userID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, id := range s.userIDs {
		if id == userID {
			return
		}
	}
	s.userIDs = append(s.userIDs, userID)
}

// RemoveUser удаляет пользователя из списка рассылки.
func (s *ReportScheduler) RemoveUser(userID int64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for i, id := range s.userIDs {
		if id == userID {
			s.userIDs = append(s.userIDs[:i], s.userIDs[i+1:]...)
			return
		}
	}
}
