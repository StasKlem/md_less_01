package sqlite

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// dailyRecordRepository реализует repository.DailyRecordRepository для SQLite.
type dailyRecordRepository struct {
	db *gorm.DB
}

// NewDailyRecordRepository создает новый DailyRecordRepository.
func NewDailyRecordRepository(db *gorm.DB) repository.DailyRecordRepository {
	return &dailyRecordRepository{db: db}
}

// Create создает новую запись КБЖУ.
func (r *dailyRecordRepository) Create(ctx context.Context, record *domain.DailyRecord) error {
	now := time.Now()
	record.CreatedAt = now
	record.UpdatedAt = now

	if err := r.db.WithContext(ctx).Create(record).Error; err != nil {
		return fmt.Errorf("create daily record: %w", err)
	}

	return nil
}

// GetByDate получает записи пользователя за конкретную дату.
func (r *dailyRecordRepository) GetByDate(ctx context.Context, userID int64, date time.Time) ([]domain.DailyRecord, error) {
	// Нормализуем дату до начала дня
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())
	endOfDay := startOfDay.Add(24 * time.Hour)

	var records []domain.DailyRecord
	result := r.db.WithContext(ctx).
		Where("user_id = ? AND date >= ? AND date < ?", userID, startOfDay, endOfDay).
		Order("created_at ASC").
		Find(&records)

	if result.Error != nil {
		return nil, fmt.Errorf("get records by date: %w", result.Error)
	}

	return records, nil
}

// GetDailyStats получает статистику КБЖУ за конкретную дату.
func (r *dailyRecordRepository) GetDailyStats(ctx context.Context, userID int64, date time.Time) (*domain.DailyStats, error) {
	// Нормализуем дату до начала дня
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())
	endOfDay := startOfDay.Add(24 * time.Hour)

	var stats domain.DailyStats
	stats.Date = startOfDay

	result := r.db.WithContext(ctx).
		Model(&domain.DailyRecord{}).
		Select("SUM(calories) as calories, SUM(proteins) as proteins, SUM(fats) as fats, SUM(carbs) as carbs, COUNT(*) as record_count").
		Where("user_id = ? AND date >= ? AND date < ?", userID, startOfDay, endOfDay).
		Scan(&stats)

	if result.Error != nil {
		return nil, fmt.Errorf("get daily stats: %w", result.Error)
	}

	return &stats, nil
}

// DeleteByDate удаляет все записи пользователя за конкретную дату.
func (r *dailyRecordRepository) DeleteByDate(ctx context.Context, userID int64, date time.Time) error {
	// Нормализуем дату до начала дня
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())
	endOfDay := startOfDay.Add(24 * time.Hour)

	result := r.db.WithContext(ctx).
		Where("user_id = ? AND date >= ? AND date < ?", userID, startOfDay, endOfDay).
		Delete(&domain.DailyRecord{})

	if result.Error != nil {
		return fmt.Errorf("delete records by date: %w", result.Error)
	}

	return nil
}

// GetDateRange получает записи за период.
func (r *dailyRecordRepository) GetDateRange(ctx context.Context, userID int64, start, end time.Time) ([]domain.DailyRecord, error) {
	var records []domain.DailyRecord

	result := r.db.WithContext(ctx).
		Where("user_id = ? AND date >= ? AND date <= ?", userID, start, end).
		Order("date ASC, created_at ASC").
		Find(&records)

	if result.Error != nil {
		return nil, fmt.Errorf("get date range: %w", result.Error)
	}

	return records, nil
}

// Ensure dailyRecordRepository implements repository.DailyRecordRepository.
var _ repository.DailyRecordRepository = (*dailyRecordRepository)(nil)
