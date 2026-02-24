package services

import (
	"context"
	"encoding/json"
	"errors"
	"kbju-bot/internal/llm"
	"kbju-bot/internal/repository/sqlite"
	"kbju-bot/pkg/logger"
	"strings"
	"time"

	"gorm.io/gorm"
)

type KbjuService struct {
	llm             llm.LLMProvider
	db              *gorm.DB
	dailyRecordRepo *sqlite.DailyRecordRepository
	messageLogRepo  *sqlite.MessageLogRepository
	userRepo        *sqlite.UserRepository
	log             *logger.Logger
}

func NewKbjuService(
	llmClient llm.LLMProvider,
	db *gorm.DB,
	log *logger.Logger,
) *KbjuService {
	return &KbjuService{
		llm:             llmClient,
		db:              db,
		dailyRecordRepo: sqlite.NewDailyRecordRepository(db),
		messageLogRepo:  sqlite.NewMessageLogRepository(db),
		userRepo:        sqlite.NewUserRepository(db),
		log:             log,
	}
}

func (s *KbjuService) ProcessText(ctx context.Context, userID int64, text string) (*sqlite.KbjuData, string, error) {
	s.log.Info("Processing text message", "user_id", userID, "text", text)

	response, err := s.llm.SendText(ctx, text)
	if err != nil {
		s.log.Error("Failed to send text to LLM", "error", err)
		return nil, "", err
	}

	kbju, err := s.parseKBJU(response)
	if err != nil {
		s.log.Warn("Failed to parse KBJU from LLM response, using defaults", "response", response, "error", err)
		kbju = &sqlite.KbjuData{}
	}

	if err := s.dailyRecordRepo.CreateOrUpdate(ctx, userID, time.Now(), *kbju); err != nil {
		s.log.Error("Failed to save daily record", "error", err)
		return kbju, response, err
	}

	if err := s.messageLogRepo.Log(ctx, userID, "text", text, kbju, response); err != nil {
		s.log.Error("Failed to log message", "error", err)
	}

	return kbju, response, nil
}

func (s *KbjuService) ProcessAudio(ctx context.Context, userID int64, fileData []byte, fileName string) (*sqlite.KbjuData, string, error) {
	s.log.Info("Processing audio message", "user_id", userID, "file_name", fileName)

	response, err := s.llm.SendAudio(ctx, fileData, fileName)
	if err != nil {
		s.log.Error("Failed to send audio to LLM", "error", err)
		return nil, "", err
	}

	kbju, err := s.parseKBJU(response)
	if err != nil {
		s.log.Warn("Failed to parse KBJU from LLM response, using defaults", "response", response, "error", err)
		kbju = &sqlite.KbjuData{}
	}

	if err := s.dailyRecordRepo.CreateOrUpdate(ctx, userID, time.Now(), *kbju); err != nil {
		s.log.Error("Failed to save daily record", "error", err)
		return kbju, response, err
	}

	if err := s.messageLogRepo.Log(ctx, userID, "audio", fileName, kbju, response); err != nil {
		s.log.Error("Failed to log message", "error", err)
	}

	return kbju, response, nil
}

func (s *KbjuService) GetDailyStats(ctx context.Context, userID int64) (*sqlite.DailyRecord, error) {
	record, err := s.dailyRecordRepo.GetByDate(ctx, userID, time.Now())
	if err != nil {
		s.log.Error("Failed to get daily stats", "error", err)
		return nil, err
	}
	return record, nil
}

func (s *KbjuService) GetWeeklyStats(ctx context.Context, userID int64) ([]sqlite.DailyRecord, error) {
	records, err := s.dailyRecordRepo.GetUserStats(ctx, userID, 7)
	if err != nil {
		s.log.Error("Failed to get weekly stats", "error", err)
		return nil, err
	}
	return records, nil
}

func (s *KbjuService) ResetDaily(ctx context.Context, userID int64) error {
	today := time.Now()
	_, err := s.dailyRecordRepo.GetByDate(ctx, userID, today)
	if err != nil {
		s.log.Error("Failed to get daily record for reset", "error", err)
		return err
	}

	if err := s.dailyRecordRepo.CreateOrUpdate(ctx, userID, today, sqlite.KbjuData{
		Calories: 0,
		Proteins: 0,
		Fats:     0,
		Carbs:    0,
	}); err != nil {
		s.log.Error("Failed to reset daily record", "error", err)
		return err
	}

	return nil
}

func (s *KbjuService) GetAllActiveUsers(ctx context.Context) ([]int64, error) {
	var users []sqlite.User
	if err := s.db.WithContext(ctx).Where("is_active = ?", true).Find(&users).Error; err != nil {
		s.log.Error("Failed to get active users", "error", err)
		return nil, err
	}

	var userIDs []int64
	for _, u := range users {
		userIDs = append(userIDs, u.ID)
	}
	return userIDs, nil
}

func (s *KbjuService) parseKBJU(response string) (*sqlite.KbjuData, error) {
	cleanResp := strings.TrimSpace(response)
	cleanResp = strings.Trim(cleanResp, "` \n")

	jsonStart := strings.Index(cleanResp, "{")
	if jsonStart == -1 {
		return nil, sqlite.ErrInvalidJSON
	}

	jsonEnd := strings.LastIndex(cleanResp, "}")
	if jsonEnd == -1 {
		return nil, sqlite.ErrInvalidJSON
	}

	cleanResp = cleanResp[jsonStart : jsonEnd+1]

	var kbju sqlite.KbjuData
	if err := json.Unmarshal([]byte(cleanResp), &kbju); err != nil {
		return nil, err
	}

	if kbju.Calories < 0 {
		kbju.Calories = 0
	}
	if kbju.Proteins < 0 {
		kbju.Proteins = 0
	}
	if kbju.Fats < 0 {
		kbju.Fats = 0
	}
	if kbju.Carbs < 0 {
		kbju.Carbs = 0
	}

	return &kbju, nil
}

type UserService struct {
	userRepo *sqlite.UserRepository
	db       *gorm.DB
	log      *logger.Logger
}

func NewUserService(db *gorm.DB, log *logger.Logger) *UserService {
	return &UserService{
		userRepo: sqlite.NewUserRepository(db),
		db:       db,
		log:      log,
	}
}

func (s *UserService) UpsertUser(ctx context.Context, userID int64, username, firstName, lastName string) error {
	user := &sqlite.User{
		ID:        userID,
		Username:  username,
		FirstName: firstName,
		LastName:  lastName,
		IsActive:  true,
	}
	return s.userRepo.Upsert(ctx, user)
}

func (s *UserService) GetUser(ctx context.Context, userID int64) (*sqlite.User, error) {
	var user sqlite.User
	err := s.db.WithContext(ctx).Where("id = ?", userID).First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}
