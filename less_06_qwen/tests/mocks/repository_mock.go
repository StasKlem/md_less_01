// Package mocks содержит mock реализации для тестирования.
package mocks

import (
	"context"
	"time"

	"github.com/stretchr/testify/mock"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/llm"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// MockUserRepository mock реализация repository.UserRepository.
type MockUserRepository struct {
	mock.Mock
}

// GetOrCreate получает пользователя или создает нового.
func (m *MockUserRepository) GetOrCreate(ctx context.Context, id int64, username, firstName, lastName string) (*domain.User, error) {
	args := m.Called(ctx, id, username, firstName, lastName)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.User), args.Error(1)
}

// GetByID получает пользователя по ID.
func (m *MockUserRepository) GetByID(ctx context.Context, id int64) (*domain.User, error) {
	args := m.Called(ctx, id)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.User), args.Error(1)
}

// MockDailyRecordRepository mock реализация repository.DailyRecordRepository.
type MockDailyRecordRepository struct {
	mock.Mock
}

// Create создает новую запись КБЖУ.
func (m *MockDailyRecordRepository) Create(ctx context.Context, record *domain.DailyRecord) error {
	args := m.Called(ctx, record)
	return args.Error(0)
}

// GetByDate получает записи пользователя за конкретную дату.
func (m *MockDailyRecordRepository) GetByDate(ctx context.Context, userID int64, date time.Time) ([]domain.DailyRecord, error) {
	args := m.Called(ctx, userID, date)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]domain.DailyRecord), args.Error(1)
}

// GetDailyStats получает статистику КБЖУ за конкретную дату.
func (m *MockDailyRecordRepository) GetDailyStats(ctx context.Context, userID int64, date time.Time) (*domain.DailyStats, error) {
	args := m.Called(ctx, userID, date)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.DailyStats), args.Error(1)
}

// DeleteByDate удаляет все записи пользователя за конкретную дату.
func (m *MockDailyRecordRepository) DeleteByDate(ctx context.Context, userID int64, date time.Time) error {
	args := m.Called(ctx, userID, date)
	return args.Error(0)
}

// GetDateRange получает записи за период.
func (m *MockDailyRecordRepository) GetDateRange(ctx context.Context, userID int64, start, end time.Time) ([]domain.DailyRecord, error) {
	args := m.Called(ctx, userID, start, end)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]domain.DailyRecord), args.Error(1)
}

// MockMessageLogRepository mock реализация repository.MessageLogRepository.
type MockMessageLogRepository struct {
	mock.Mock
}

// Create создает запись лога сообщения.
func (m *MockMessageLogRepository) Create(ctx context.Context, log *domain.MessageLog) error {
	args := m.Called(ctx, log)
	return args.Error(0)
}

// GetByUser получает логи сообщений пользователя.
func (m *MockMessageLogRepository) GetByUser(ctx context.Context, userID int64, limit int) ([]domain.MessageLog, error) {
	args := m.Called(ctx, userID, limit)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]domain.MessageLog), args.Error(1)
}

// MockTransactionManager mock реализация repository.TransactionManager.
type MockTransactionManager struct {
	mock.Mock
}

// WithTransaction выполняет функцию в рамках транзакции.
func (m *MockTransactionManager) WithTransaction(ctx context.Context, fn func(ctx context.Context) error) error {
	args := m.Called(ctx, fn)
	if args.Error(0) == nil {
		// Вызываем функцию для реальной работы в тестах
		return fn(ctx)
	}
	return args.Error(0)
}

// MockLLMProvider mock реализация llm.LLMProvider.
type MockLLMProvider struct {
	mock.Mock
}

// SendText отправляет текстовое сообщение в LLM.
func (m *MockLLMProvider) SendText(ctx context.Context, text string) (*domain.KBJUResult, error) {
	args := m.Called(ctx, text)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.KBJUResult), args.Error(1)
}

// SendAudio отправляет аудиофайл в LLM.
func (m *MockLLMProvider) SendAudio(ctx context.Context, audioData []byte, mimeType string) (*domain.KBJUResult, error) {
	args := m.Called(ctx, audioData, mimeType)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.KBJUResult), args.Error(1)
}

// Ensure interfaces are implemented.
var (
	_ repository.UserRepository       = (*MockUserRepository)(nil)
	_ repository.DailyRecordRepository = (*MockDailyRecordRepository)(nil)
	_ repository.MessageLogRepository = (*MockMessageLogRepository)(nil)
	_ repository.TransactionManager   = (*MockTransactionManager)(nil)
	_ llm.LLMProvider                 = (*MockLLMProvider)(nil)
)
