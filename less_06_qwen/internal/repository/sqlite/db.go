// Package sqlite предоставляет реализацию репозиториев для SQLite.
package sqlite

import (
	"context"
	"database/sql"
	"fmt"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/stasklem/kbju-bot/internal/config"
	"github.com/stasklem/kbju-bot/internal/domain"
	"github.com/stasklem/kbju-bot/internal/repository"
)

// DB представляет обертку над gorm.DB с поддержкой транзакций.
type DB struct {
	*gorm.DB
}

// New создает новое подключение к SQLite с оптимизированными настройками.
func New(cfg config.DatabaseConfig) (*DB, error) {
	// SQLite требует специальных настроек для конкурентности
	// WAL режим улучшает производительность при записи
	dsn := fmt.Sprintf("%s?_journal_mode=WAL&_busy_timeout=5000&_foreign_keys=ON", cfg.Path)

	// DriverName должен быть "sqlite3" для gorm.io/driver/sqlite
	sqlDB, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite connection: %w", err)
	}

	// Настройка пула соединений для SQLite
	// Важно: SQLite не поддерживает параллельную запись, поэтому ограничиваем соединения
	sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	sqlDB.SetConnMaxLifetime(cfg.ConnMaxLifetime)

	db, err := gorm.Open(sqlite.New(sqlite.Config{
		Conn: sqlDB,
	}), &gorm.Config{
		// Отключаем автоматическое переименование таблиц во множественное число
		SkipDefaultTransaction: true,
	})
	if err != nil {
		return nil, fmt.Errorf("initialize gorm: %w", err)
	}

	return &DB{DB: db}, nil
}

// AutoMigrate выполняет миграцию схем базы данных.
func (db *DB) AutoMigrate() error {
	models := []interface{}{
		&domain.User{},
		&domain.DailyRecord{},
		&domain.MessageLog{},
	}

	for _, model := range models {
		if err := db.DB.AutoMigrate(model); err != nil {
			return fmt.Errorf("migrate %T: %w", model, err)
		}
	}

	return nil
}

// Close закрывает подключение к базе данных.
func (db *DB) Close() error {
	sqlDB, err := db.DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}

// WithTransaction выполняет функцию в рамках транзакции.
func (db *DB) WithTransaction(ctx context.Context, fn func(ctx context.Context) error) error {
	return db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return fn(ctx)
	})
}

// Ensure DB implements repository.TransactionManager.
var _ repository.TransactionManager = (*DB)(nil)
