package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
)

// Logger - глобальный логгер для приложения
var Logger *log.Logger

// InitLogger инициализирует логгер для записи в файл
func InitLogger(config *AppConfig) error {
	logFile := config.Log.FilePath

	// Если логирование отключено и файл не указан
	if !config.Log.Enabled && logFile == "" {
		Logger = log.New(io.Discard, "", 0)
		return nil
	}

	// Если указан только каталог, создаём файл в нём
	if logFile != "" {
		if info, err := os.Stat(logFile); err == nil && info.IsDir() {
			logFile = filepath.Join(logFile, "llm-client.log")
		}
	} else {
		// Логирование включено но файл не указан - отключаем
		Logger = log.New(io.Discard, "", 0)
		return nil
	}

	// Создаём или открываем файл для записи
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to create log file: %w", err)
	}

	Logger = log.New(f, "", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)
	Logger.Println("=== LLM Client started ===")
	Logger.Printf("Config: address=%s, model=%s",
		config.Server.Address, config.Model.Name)

	return nil
}

// LogError записывает ошибку в лог
func LogError(msg string, err error) {
	if err != nil {
		Logger.Printf("ERROR: %s: %v", msg, err)
	} else {
		Logger.Printf("ERROR: %s", msg)
	}
}

// LogInfo записывает информационное сообщение
func LogInfo(msg string, args ...interface{}) {
	Logger.Printf("INFO: "+msg, args...)
}

// LogDebug записывает отладочное сообщение
func LogDebug(msg string, args ...interface{}) {
	Logger.Printf("DEBUG: "+msg, args...)
}
