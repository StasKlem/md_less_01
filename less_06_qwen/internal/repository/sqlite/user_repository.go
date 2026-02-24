package sqlite

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gorm.io/gorm"

	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// userRepository реализует repository.UserRepository для SQLite.
type userRepository struct {
	db *gorm.DB
}

// NewUserRepository создает новый UserRepository.
func NewUserRepository(db *gorm.DB) repository.UserRepository {
	return &userRepository{db: db}
}

// GetOrCreate получает пользователя или создает нового.
func (r *userRepository) GetOrCreate(ctx context.Context, id int64, username, firstName, lastName string) (*domain.User, error) {
	var user domain.User

	// Пытаемся найти существующего пользователя
	result := r.db.WithContext(ctx).Where("id = ?", id).First(&user)

	if result.Error == nil {
		// Пользователь найден, обновляем информацию если изменилась
		if user.Username != username || user.FirstName != firstName || user.LastName != lastName {
			updates := make(map[string]interface{})
			if user.Username != username {
				updates["username"] = username
			}
			if user.FirstName != firstName {
				updates["first_name"] = firstName
			}
			if user.LastName != lastName {
				updates["last_name"] = lastName
			}
			updates["updated_at"] = time.Now()

			if err := r.db.WithContext(ctx).Model(&user).Updates(updates).Error; err != nil {
				return nil, fmt.Errorf("update user: %w", err)
			}
		}
		return &user, nil
	}

	if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("get user: %w", result.Error)
	}

	// Пользователь не найден, создаем нового
	now := time.Now()
	user = domain.User{
		ID:        id,
		Username:  username,
		FirstName: firstName,
		LastName:  lastName,
		CreatedAt: now,
		UpdatedAt: now,
	}

	if err := r.db.WithContext(ctx).Create(&user).Error; err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}

	return &user, nil
}

// GetByID получает пользователя по ID.
func (r *userRepository) GetByID(ctx context.Context, id int64) (*domain.User, error) {
	var user domain.User

	result := r.db.WithContext(ctx).Where("id = ?", id).First(&user)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, fmt.Errorf("get user by id: %w", result.Error)
	}

	return &user, nil
}

// Ensure userRepository implements repository.UserRepository.
var _ repository.UserRepository = (*userRepository)(nil)
