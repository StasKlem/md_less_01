package services_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/services"
	"github.com/stasklem/kbju-bot/tests/mocks"
)

func TestKBJUService_ProcessTextMessage_Success(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)
	username := "testuser"
	firstName := "Test"
	lastName := "User"
	text := "Овсянка с молоком и бананом, 200г"

	// Создаем моки
	mockUserRepo := new(mocks.MockUserRepository)
	mockRecordRepo := new(mocks.MockDailyRecordRepository)
	mockMessageLogRepo := new(mocks.MockMessageLogRepository)
	mockLLM := new(mocks.MockLLMProvider)
	mockTXManager := new(mocks.MockTransactionManager)

	// Настраиваем ожидания
	expectedUser := &domain.User{
		ID:        userID,
		Username:  username,
		FirstName: firstName,
		LastName:  lastName,
	}

	mockUserRepo.On("GetOrCreate", ctx, userID, username, firstName, lastName).
		Return(expectedUser, nil)

	expectedKBJU := &domain.KBJUResult{
		Calories: 350,
		Proteins: 12.5,
		Fats:     8.2,
		Carbs:    55.0,
		FoodName: "Овсянка с молоком и бананом",
	}

	mockLLM.On("SendText", ctx, text).Return(expectedKBJU, nil)
	mockMessageLogRepo.On("Create", mock.Anything, mock.Anything).Return(nil)
	mockRecordRepo.On("Create", mock.Anything, mock.Anything).Return(nil)
	mockTXManager.On("WithTransaction", mock.Anything, mock.Anything).Run(func(args mock.Arguments) {
		fn := args.Get(1).(func(ctx context.Context) error)
		_ = fn(ctx)
	}).Return(nil)

	// Создаем сервис
	svc := services.NewKBJUService(services.KBJUServiceConfig{
		UserRepo:       mockUserRepo,
		RecordRepo:     mockRecordRepo,
		MessageLogRepo: mockMessageLogRepo,
		LLMProvider:    mockLLM,
		TXManager:      mockTXManager,
	})

	// Act
	result, err := svc.ProcessTextMessage(ctx, userID, username, firstName, lastName, text)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, expectedKBJU.Calories, result.Calories)
	assert.Equal(t, expectedKBJU.Proteins, result.Proteins)
	assert.Equal(t, expectedKBJU.Fats, result.Fats)
	assert.Equal(t, expectedKBJU.Carbs, result.Carbs)
	assert.Equal(t, expectedKBJU.FoodName, result.FoodName)

	// Проверяем, что все ожидания выполнены
	mockUserRepo.AssertExpectations(t)
	mockLLM.AssertExpectations(t)
	mockMessageLogRepo.AssertExpectations(t)
	mockRecordRepo.AssertExpectations(t)
}

func TestKBJUService_ProcessTextMessage_LLMError(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)
	username := "testuser"
	firstName := "Test"
	lastName := "User"
	text := "Некорректный запрос"

	mockUserRepo := new(mocks.MockUserRepository)
	mockMessageLogRepo := new(mocks.MockMessageLogRepository)
	mockLLM := new(mocks.MockLLMProvider)

	expectedUser := &domain.User{
		ID:        userID,
		Username:  username,
		FirstName: firstName,
		LastName:  lastName,
	}

	mockUserRepo.On("GetOrCreate", ctx, userID, username, firstName, lastName).
		Return(expectedUser, nil)
	mockLLM.On("SendText", ctx, text).Return((*domain.KBJUResult)(nil), assert.AnError)
	mockMessageLogRepo.On("Create", mock.Anything, mock.Anything).Return(nil)

	svc := services.NewKBJUService(services.KBJUServiceConfig{
		UserRepo:       mockUserRepo,
		MessageLogRepo: mockMessageLogRepo,
		LLMProvider:    mockLLM,
	})

	// Act
	result, err := svc.ProcessTextMessage(ctx, userID, username, firstName, lastName, text)

	// Assert
	require.Error(t, err)
	assert.Nil(t, result)
	assert.Contains(t, err.Error(), "send to LLM")

	mockUserRepo.AssertExpectations(t)
	mockLLM.AssertExpectations(t)
}

func TestKBJUService_GetDailyStats_Success(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)
	now := time.Now()

	mockRecordRepo := new(mocks.MockDailyRecordRepository)

	expectedStats := &domain.DailyStats{
		Date:        now,
		Calories:    2500,
		Proteins:    150.5,
		Fats:        85.2,
		Carbs:       320.0,
		RecordCount: 5,
	}

	mockRecordRepo.On("GetDailyStats", ctx, userID, mock.MatchedBy(func(t time.Time) bool {
		return t.Year() == now.Year() && t.Month() == now.Month() && t.Day() == now.Day()
	})).Return(expectedStats, nil)

	svc := services.NewKBJUService(services.KBJUServiceConfig{
		RecordRepo: mockRecordRepo,
	})

	// Act
	result, err := svc.GetDailyStats(ctx, userID)

	// Assert
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, expectedStats.Calories, result.Calories)
	assert.Equal(t, expectedStats.Proteins, result.Proteins)
	assert.Equal(t, expectedStats.Fats, result.Fats)
	assert.Equal(t, expectedStats.Carbs, result.Carbs)
	assert.Equal(t, expectedStats.RecordCount, result.RecordCount)

	mockRecordRepo.AssertExpectations(t)
}

func TestKBJUService_ResetDay_Success(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)

	mockRecordRepo := new(mocks.MockDailyRecordRepository)
	mockRecordRepo.On("DeleteByDate", ctx, userID, mock.MatchedBy(func(t time.Time) bool {
		now := time.Now()
		return t.Year() == now.Year() && t.Month() == now.Month() && t.Day() == now.Day()
	})).Return(nil)

	svc := services.NewKBJUService(services.KBJUServiceConfig{
		RecordRepo: mockRecordRepo,
	})

	// Act
	err := svc.ResetDay(ctx, userID)

	// Assert
	require.NoError(t, err)
	mockRecordRepo.AssertExpectations(t)
}

func TestKBJUService_GenerateReport_Success(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)
	testDate := time.Date(2024, 1, 15, 0, 0, 0, 0, time.UTC)

	mockRecordRepo := new(mocks.MockDailyRecordRepository)

	stats := &domain.DailyStats{
		Date:        testDate,
		Calories:    2200,
		Proteins:    120.0,
		Fats:        70.0,
		Carbs:       280.0,
		RecordCount: 4,
	}

	mockRecordRepo.On("GetDailyStats", ctx, userID, testDate).Return(stats, nil)

	svc := services.NewKBJUService(services.KBJUServiceConfig{
		RecordRepo: mockRecordRepo,
	})

	// Act
	report, err := svc.GenerateReport(ctx, userID, testDate)

	// Assert
	require.NoError(t, err)
	require.NotEmpty(t, report)
	assert.Contains(t, report, "2200")
	assert.Contains(t, report, "120.0")
	assert.Contains(t, report, "70.0")
	assert.Contains(t, report, "280.0")
	assert.Contains(t, report, "4")

	mockRecordRepo.AssertExpectations(t)
}

func TestKBJUService_GenerateReport_EmptyStats(t *testing.T) {
	t.Parallel()

	// Arrange
	ctx := context.Background()
	userID := int64(123456789)
	testDate := time.Date(2024, 1, 15, 0, 0, 0, 0, time.UTC)

	mockRecordRepo := new(mocks.MockDailyRecordRepository)

	stats := &domain.DailyStats{
		Date:        testDate,
		Calories:    0,
		Proteins:    0,
		Fats:        0,
		Carbs:       0,
		RecordCount: 0,
	}

	mockRecordRepo.On("GetDailyStats", ctx, userID, testDate).Return(stats, nil)

	svc := services.NewKBJUService(services.KBJUServiceConfig{
		RecordRepo: mockRecordRepo,
	})

	// Act
	report, err := svc.GenerateReport(ctx, userID, testDate)

	// Assert
	require.NoError(t, err)
	require.NotEmpty(t, report)
	assert.Contains(t, report, "не было записей")

	mockRecordRepo.AssertExpectations(t)
}

func TestKBJUResult_Validate(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		result   domain.KBJUResult
		expected bool
	}{
		{
			name: "valid result",
			result: domain.KBJUResult{
				Calories: 350,
				Proteins: 12.5,
				Fats:     8.2,
				Carbs:    55.0,
				FoodName: "Овсянка",
			},
			expected: true,
		},
		{
			name: "negative calories",
			result: domain.KBJUResult{
				Calories: -100,
				Proteins: 12.5,
				Fats:     8.2,
				Carbs:    55.0,
				FoodName: "Овсянка",
			},
			expected: false,
		},
		{
			name: "empty food name",
			result: domain.KBJUResult{
				Calories: 350,
				Proteins: 12.5,
				Fats:     8.2,
				Carbs:    55.0,
				FoodName: "",
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.expected, tt.result.Validate())
		})
	}
}
