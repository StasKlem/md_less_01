// Package repository определяет интерфейсы для доступа к данным.
package repository

import (
	"context"
	"time"

	"github.com/stasklem/kbju-bot/internal/domain"
)

// UserRepository определяет интерфейс для работы с пользователями.
type UserRepository interface {
	// GetOrCreate получает пользователя или создает нового.
	GetOrCreate(ctx context.Context, id int64, username, firstName, lastName string) (*domain.User, error)
	// GetByID получает пользователя по ID.
	GetByID(ctx context.Context, id int64) (*domain.User, error)
}

// DailyRecordRepository определяет интерфейс для работы с записями КБЖУ.
type DailyRecordRepository interface {
	// Create создает новую запись КБЖУ.
	Create(ctx context.Context, record *domain.DailyRecord) error
	// GetByDate получает записи пользователя за конкретную дату.
	GetByDate(ctx context.Context, userID int64, date time.Time) ([]domain.DailyRecord, error)
	// GetDailyStats получает статистику КБЖУ за конкретную дату.
	GetDailyStats(ctx context.Context, userID int64, date time.Time) (*domain.DailyStats, error)
	// DeleteByDate удаляет все записи пользователя за конкретную дату.
	DeleteByDate(ctx context.Context, userID int64, date time.Time) error
	// GetDateRange получает записи за период.
	GetDateRange(ctx context.Context, userID int64, start, end time.Time) ([]domain.DailyRecord, error)
}

// MessageLogRepository определяет интерфейс для работы с логами сообщений.
type MessageLogRepository interface {
	// Create создает запись лога сообщения.
	Create(ctx context.Context, log *domain.MessageLog) error
	// GetByUser получает логи сообщений пользователя.
	GetByUser(ctx context.Context, userID int64, limit int) ([]domain.MessageLog, error)
}

// TransactionManager определяет интерфейс для управления транзакциями.
type TransactionManager interface {
	// WithTransaction выполняет функцию в рамках транзакции.
	WithTransaction(ctx context.Context, fn func(ctx context.Context) error) error
}
