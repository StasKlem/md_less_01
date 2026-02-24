package sqlite

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"gorm.io/gorm"
)

type DailyRecordRepository struct {
	db *gorm.DB
}

func NewDailyRecordRepository(db *gorm.DB) *DailyRecordRepository {
	return &DailyRecordRepository{db: db}
}

func (r *DailyRecordRepository) CreateOrUpdate(ctx context.Context, userID int64, date time.Time, kbju KbjuData) error {
	date = time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())

	var record DailyRecord
	db := r.db.WithContext(ctx)
	err := db.Where("user_id = ? AND date = ?", userID, date).First(&record).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		record = DailyRecord{
			UserID:    userID,
			Date:      date,
			Calories:  kbju.Calories,
			Proteins:  kbju.Proteins,
			Fats:      kbju.Fats,
			Carbs:     kbju.Carbs,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		return db.Create(&record).Error
	}

	if err != nil {
		return err
	}

	record.Calories += kbju.Calories
	record.Proteins += kbju.Proteins
	record.Fats += kbju.Fats
	record.Carbs += kbju.Carbs
	record.UpdatedAt = time.Now()

	return db.Save(&record).Error
}

func (r *DailyRecordRepository) GetByDate(ctx context.Context, userID int64, date time.Time) (*DailyRecord, error) {
	date = time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())

	var record DailyRecord
	db := r.db.WithContext(ctx)
	err := db.Where("user_id = ? AND date = ?", userID, date).First(&record).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return &record, nil
}

func (r *DailyRecordRepository) GetUserStats(ctx context.Context, userID int64, days int) ([]DailyRecord, error) {
	var records []DailyRecord
	db := r.db.WithContext(ctx)
	startDate := time.Now().AddDate(0, 0, -days)
	err := db.Where("user_id = ? AND date >= ?", userID, startDate).Find(&records).Error
	if err != nil {
		return nil, err
	}
	return records, nil
}

type MessageLogRepository struct {
	db *gorm.DB
}

func NewMessageLogRepository(db *gorm.DB) *MessageLogRepository {
	return &MessageLogRepository{db: db}
}

func (r *MessageLogRepository) Log(ctx context.Context, userID int64, msgType string, content string, kbju *KbjuData, rawLLMResp string) error {
	kbjuJSON, _ := json.Marshal(kbju)

	log := MessageLog{
		UserID:     userID,
		Type:       msgType,
		Content:    content,
		KBJUData:   string(kbjuJSON),
		RawLLMResp: rawLLMResp,
		CreatedAt:  time.Now(),
	}

	db := r.db.WithContext(ctx)
	return db.Create(&log).Error
}

type KbjuData struct {
	Calories float64 `json:"calories"`
	Proteins float64 `json:"proteins"`
	Fats     float64 `json:"fats"`
	Carbs    float64 `json:"carbs"`
	FoodName string  `json:"food_name"`
}

var ErrInvalidJSON = errors.New("invalid JSON response from LLM")

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Upsert(ctx context.Context, user *User) error {
	db := r.db.WithContext(ctx)
	var existing User

	err := db.Where("id = ?", user.ID).First(&existing).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		user.CreatedAt = time.Now()
		user.UpdatedAt = time.Now()
		return db.Create(user).Error
	}

	if err != nil {
		return err
	}

	existing.Username = user.Username
	existing.FirstName = user.FirstName
	existing.LastName = user.LastName
	existing.UpdatedAt = time.Now()

	return db.Save(&existing).Error
}
