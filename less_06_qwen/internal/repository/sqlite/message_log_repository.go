package sqlite

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// messageLogRepository реализует repository.MessageLogRepository для SQLite.
type messageLogRepository struct {
	db *gorm.DB
}

// NewMessageLogRepository создает новый MessageLogRepository.
func NewMessageLogRepository(db *gorm.DB) repository.MessageLogRepository {
	return &messageLogRepository{db: db}
}

// Create создает запись лога сообщения.
func (r *messageLogRepository) Create(ctx context.Context, log *domain.MessageLog) error {
	log.CreatedAt = time.Now()

	if err := r.db.WithContext(ctx).Create(log).Error; err != nil {
		return fmt.Errorf("create message log: %w", err)
	}

	return nil
}

// GetByUser получает логи сообщений пользователя.
func (r *messageLogRepository) GetByUser(ctx context.Context, userID int64, limit int) ([]domain.MessageLog, error) {
	var logs []domain.MessageLog

	query := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC")

	if limit > 0 {
		query = query.Limit(limit)
	}

	result := query.Find(&logs)
	if result.Error != nil {
		return nil, fmt.Errorf("get message logs by user: %w", result.Error)
	}

	return logs, nil
}

// Ensure messageLogRepository implements repository.MessageLogRepository.
var _ repository.MessageLogRepository = (*messageLogRepository)(nil)
