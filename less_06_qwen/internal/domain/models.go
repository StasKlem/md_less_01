// Package domain содержит бизнес-модели предметной области.
package domain

import (
	"time"
)

// User представляет пользователя бота.
type User struct {
	ID        int64     `gorm:"primaryKey;column:id"`
	Username  string    `gorm:"column:username;size:255"`
	FirstName string    `gorm:"column:first_name;size:255"`
	LastName  string    `gorm:"column:last_name;size:255"`
	CreatedAt time.Time `gorm:"column:created_at"`
	UpdatedAt time.Time `gorm:"column:updated_at"`
}

// TableName возвращает имя таблицы для модели User.
func (User) TableName() string {
	return "users"
}

// DailyRecord представляет ежедневную запись КБЖУ.
type DailyRecord struct {
	ID         int64     `gorm:"primaryKey;column:id"`
	UserID     int64     `gorm:"column:user_id;index:idx_user_date"`
	Date       time.Time `gorm:"column:date;index:idx_user_date;type:date"`
	Calories   int       `gorm:"column:calories"`
	Proteins   float64   `gorm:"column:proteins;type:real"`
	Fats       float64   `gorm:"column:fats;type:real"`
	Carbs      float64   `gorm:"column:carbs;type:real"`
	FoodName   string    `gorm:"column:food_name;size:255"`
	RawMessage string    `gorm:"column:raw_message;type:text"`
	CreatedAt  time.Time `gorm:"column:created_at"`
	UpdatedAt  time.Time `gorm:"column:updated_at"`
}

// TableName возвращает имя таблицы для модели DailyRecord.
func (DailyRecord) TableName() string {
	return "daily_records"
}

// DailyStats представляет статистику КБЖУ за день.
type DailyStats struct {
	Date       time.Time
	Calories   int
	Proteins   float64
	Fats       float64
	Carbs      float64
	RecordCount int
}

// MessageLog представляет лог сообщений пользователя.
type MessageLog struct {
	ID          int64     `gorm:"primaryKey;column:id"`
	UserID      int64     `gorm:"column:user_id;index"`
	MessageType string    `gorm:"column:message_type;size:50"` // text, voice, audio
	Content     string    `gorm:"column:content;type:text"`
	LLMResponse string    `gorm:"column:llm_response;type:text"`
	Error       string    `gorm:"column:error;size:500"`
	CreatedAt   time.Time `gorm:"column:created_at"`
}

// TableName возвращает имя таблицы для модели MessageLog.
func (MessageLog) TableName() string {
	return "message_logs"
}

// KBJUResult представляет результат анализа КБЖУ от LLM.
type KBJUResult struct {
	Calories int     `json:"calories"`
	Proteins float64 `json:"proteins"`
	Fats     float64 `json:"fats"`
	Carbs    float64 `json:"carbs"`
	FoodName string  `json:"food_name"`
}

// Validate проверяает корректность данных КБЖУ.
func (k *KBJUResult) Validate() bool {
	return k.Calories >= 0 &&
		k.Proteins >= 0 &&
		k.Fats >= 0 &&
		k.Carbs >= 0 &&
		k.FoodName != ""
}

// ToDailyRecord создает DailyRecord из KBJUResult.
func (k *KBJUResult) ToDailyRecord(userID int64, date time.Time, rawMessage string) DailyRecord {
	return DailyRecord{
		UserID:     userID,
		Date:       date,
		Calories:   k.Calories,
		Proteins:   k.Proteins,
		Fats:       k.Fats,
		Carbs:      k.Carbs,
		FoodName:   k.FoodName,
		RawMessage: rawMessage,
	}
}
