// Package errors предоставляет типизированные ошибки для приложения LLM Chat Client.
package errors

import (
	"errors"
	"fmt"
)

// Типы ошибок приложения
var (
	// ErrConfigNotFound возвращается когда файл конфигурации не найден
	ErrConfigNotFound = errors.New("config file not found")

	// ErrConfigInvalid возвращается когда конфигурация невалидна
	ErrConfigInvalid = errors.New("invalid configuration")

	// ErrConfigParse возвращается когда не удалось распарсить конфигурацию
	ErrConfigParse = errors.New("failed to parse configuration")

	// ErrClientNotInitialized возвращается когда клиент не инициализирован
	ErrClientNotInitialized = errors.New("client not initialized")

	// ErrRequestFailed возвращается когда HTTP запрос не удался
	ErrRequestFailed = errors.New("request failed")

	// ErrInvalidResponse возвращается когда получен невалидный ответ от API
	ErrInvalidResponse = errors.New("invalid API response")

	// ErrStreamFailed возвращается когда потоковая передача не удалась
	ErrStreamFailed = errors.New("stream failed")

	// ErrContextCancelled возвращается когда контекст отменён
	ErrContextCancelled = errors.New("context cancelled")

	// ErrInvalidMessage возвращается когда сообщение невалидно
	ErrInvalidMessage = errors.New("invalid message")

	// ErrEmptyHistory возвращается когда история пуста
	ErrEmptyHistory = errors.New("empty history")

	// ErrLoggerNotInitialized возвращается когда логгер не инициализирован
	ErrLoggerNotInitialized = errors.New("logger not initialized")
)

// ErrorKind определяет категорию ошибки
type ErrorKind string

const (
	// KindConfig - ошибки конфигурации
	KindConfig ErrorKind = "config"
	// KindNetwork - сетевые ошибки
	KindNetwork ErrorKind = "network"
	// KindAPI - ошибки API
	KindAPI ErrorKind = "api"
	// KindStream - ошибки стриминга
	KindStream ErrorKind = "stream"
	// KindValidation - ошибки валидации
	KindValidation ErrorKind = "validation"
	// KindInternal - внутренние ошибки
	KindInternal ErrorKind = "internal"
)

// AppError представляет ошибку приложения с дополнительной информацией
type AppError struct {
	Kind    ErrorKind // Категория ошибки
	Code    string    // Код ошибки для программной обработки
	Message string    // Сообщение об ошибке
	Err     error     // Оригинальная ошибка (причина)
	Context map[string]any
}

// Error реализует интерфейс error
func (e *AppError) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("[%s:%s] %s: %v", e.Kind, e.Code, e.Message, e.Err)
	}
	return fmt.Sprintf("[%s:%s] %s", e.Kind, e.Code, e.Message)
}

// Unwrap возвращает обёрнутую ошибку для совместимости с errors.Is/As
func (e *AppError) Unwrap() error {
	return e.Err
}

// WithContext добавляет контекст к ошибке
func (e *AppError) WithContext(key string, value any) *AppError {
	if e.Context == nil {
		e.Context = make(map[string]any)
	}
	e.Context[key] = value
	return e
}

// NewConfigError создаёт ошибку конфигурации
func NewConfigError(code, message string, err error) *AppError {
	return &AppError{
		Kind:    KindConfig,
		Code:    code,
		Message: message,
		Err:     err,
		Context: make(map[string]any),
	}
}

// NewNetworkError создаёт сетевую ошибку
func NewNetworkError(code, message string, err error) *AppError {
	return &AppError{
		Kind:    KindNetwork,
		Code:    code,
		Message: message,
		Err:     err,
		Context: make(map[string]any),
	}
}

// NewAPIError создаёт ошибку API
func NewAPIError(code, message string, err error, statusCode int) *AppError {
	return &AppError{
		Kind:    KindAPI,
		Code:    code,
		Message: message,
		Err:     err,
		Context: map[string]any{"status_code": statusCode},
	}
}

// NewStreamError создаёт ошибку стриминга
func NewStreamError(code, message string, err error) *AppError {
	return &AppError{
		Kind:    KindStream,
		Code:    code,
		Message: message,
		Err:     err,
		Context: make(map[string]any),
	}
}

// NewValidationError создаёт ошибку валидации
func NewValidationError(code, message string, err error) *AppError {
	return &AppError{
		Kind:    KindValidation,
		Code:    code,
		Message: message,
		Err:     err,
		Context: make(map[string]any),
	}
}

// NewInternalError создаёт внутреннюю ошибку
func NewInternalError(code, message string, err error) *AppError {
	return &AppError{
		Kind:    KindInternal,
		Code:    code,
		Message: message,
		Err:     err,
		Context: make(map[string]any),
	}
}

// IsConfigError проверяет является ли ошибка ошибкой конфигурации
func IsConfigError(err error) bool {
	var appErr *AppError
	if errors.As(err, &appErr) {
		return appErr.Kind == KindConfig
	}
	return false
}

// IsNetworkError проверяет является ли ошибка сетевой
func IsNetworkError(err error) bool {
	var appErr *AppError
	if errors.As(err, &appErr) {
		return appErr.Kind == KindNetwork
	}
	return false
}

// IsAPIError проверяет является ли ошибка ошибкой API
func IsAPIError(err error) bool {
	var appErr *AppError
	if errors.As(err, &appErr) {
		return appErr.Kind == KindAPI
	}
	return false
}

// GetStatusCode извлекает HTTP статус код из ошибки API
func GetStatusCode(err error) int {
	var appErr *AppError
	if errors.As(err, &appErr) {
		if code, ok := appErr.Context["status_code"].(int); ok {
			return code
		}
	}
	return 0
}
