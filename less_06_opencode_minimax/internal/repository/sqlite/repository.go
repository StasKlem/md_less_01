package sqlite

import (
	"fmt"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func New(dbPath string, log logger.Interface) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: log,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Exec("PRAGMA journal_mode=WAL").Error; err != nil {
		return nil, fmt.Errorf("failed to enable WAL mode: %w", err)
	}

	return db, nil
}

func Migrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&User{},
		&DailyRecord{},
		&MessageLog{},
	)
}

type User struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Username  string    `gorm:"size:255" json:"username"`
	FirstName string    `gorm:"size:255" json:"first_name"`
	LastName  string    `gorm:"size:255" json:"last_name"`
	IsActive  bool      `gorm:"default:true" json:"is_active"`
}

func (User) TableName() string {
	return "users"
}

type DailyRecord struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	UserID    int64     `gorm:"index;not null" json:"user_id"`
	Date      time.Time `gorm:"type:date;index" json:"date"`
	Calories  float64   `gorm:"default:0" json:"calories"`
	Proteins  float64   `gorm:"default:0" json:"proteins"`
	Fats      float64   `gorm:"default:0" json:"fats"`
	Carbs     float64   `gorm:"default:0" json:"carbs"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (DailyRecord) TableName() string {
	return "daily_records"
}

type MessageLog struct {
	ID         int64     `gorm:"primaryKey" json:"id"`
	UserID     int64     `gorm:"index;not null" json:"user_id"`
	Type       string    `gorm:"size:20;not null" json:"type"`
	Content    string    `gorm:"type:text" json:"content"`
	KBJUData   string    `gorm:"type:text" json:"kbju_data"`
	RawLLMResp string    `gorm:"type:text" json:"raw_llm_resp"`
	CreatedAt  time.Time `json:"created_at"`
}

func (MessageLog) TableName() string {
	return "message_logs"
}
