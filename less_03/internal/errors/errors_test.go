package errors

import (
	"errors"
	"fmt"
	"testing"
)

func TestAppError_Error(t *testing.T) {
	tests := []struct {
		name     string
		err      *AppError
		expected string
	}{
		{
			name: "with wrapped error",
			err: &AppError{
				Kind:    KindConfig,
				Code:    "FILE_NOT_FOUND",
				Message: "config file not found",
				Err:     fmt.Errorf("no such file"),
			},
			expected: "[config:FILE_NOT_FOUND] config file not found: no such file",
		},
		{
			name: "without wrapped error",
			err: &AppError{
				Kind:    KindValidation,
				Code:    "INVALID_VALUE",
				Message: "temperature out of range",
				Err:     nil,
			},
			expected: "[validation:INVALID_VALUE] temperature out of range",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.err.Error()
			if got != tt.expected {
				t.Errorf("AppError.Error() = %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestAppError_Unwrap(t *testing.T) {
	original := fmt.Errorf("original error")
	appErr := &AppError{
		Kind:    KindNetwork,
		Code:    "CONNECTION_FAILED",
		Message: "failed to connect",
		Err:     original,
	}

	unwrapped := errors.Unwrap(appErr)
	if unwrapped != original {
		t.Errorf("Unwrap() = %v, want %v", unwrapped, original)
	}
}

func TestAppError_WithContext(t *testing.T) {
	err := &AppError{
		Kind:    KindAPI,
		Code:    "RATE_LIMITED",
		Message: "rate limit exceeded",
		Err:     fmt.Errorf("too many requests"),
	}

	err = err.WithContext("retry_after", 60).WithContext("endpoint", "/v1/chat")

	if err.Context["retry_after"] != 60 {
		t.Errorf("WithContext() failed for retry_after")
	}
	if err.Context["endpoint"] != "/v1/chat" {
		t.Errorf("WithContext() failed for endpoint")
	}
}

func TestNewConfigError(t *testing.T) {
	origErr := fmt.Errorf("file not found")
	err := NewConfigError("FILE_NOT_FOUND", "config file missing", origErr)

	if err.Kind != KindConfig {
		t.Errorf("Kind = %v, want %v", err.Kind, KindConfig)
	}
	if err.Code != "FILE_NOT_FOUND" {
		t.Errorf("Code = %v, want FILE_NOT_FOUND", err.Code)
	}
	if !errors.Is(err.Unwrap(), origErr) {
		t.Errorf("Unwrap() should return original error")
	}
}

func TestNewNetworkError(t *testing.T) {
	origErr := fmt.Errorf("connection refused")
	err := NewNetworkError("CONNECTION_FAILED", "cannot connect to server", origErr)

	if err.Kind != KindNetwork {
		t.Errorf("Kind = %v, want %v", err.Kind, KindNetwork)
	}
	if err.Code != "CONNECTION_FAILED" {
		t.Errorf("Code = %v, want CONNECTION_FAILED", err.Code)
	}
}

func TestNewAPIError(t *testing.T) {
	origErr := fmt.Errorf("unauthorized")
	err := NewAPIError("UNAUTHORIZED", "invalid API key", origErr, 401)

	if err.Kind != KindAPI {
		t.Errorf("Kind = %v, want %v", err.Kind, KindAPI)
	}
	if err.Context["status_code"] != 401 {
		t.Errorf("status_code = %v, want 401", err.Context["status_code"])
	}
}

func TestNewStreamError(t *testing.T) {
	origErr := fmt.Errorf("stream closed")
	err := NewStreamError("STREAM_CLOSED", "connection lost", origErr)

	if err.Kind != KindStream {
		t.Errorf("Kind = %v, want %v", err.Kind, KindStream)
	}
}

func TestNewValidationError(t *testing.T) {
	err := NewValidationError("INVALID_RANGE", "temperature must be 0-2", nil)

	if err.Kind != KindValidation {
		t.Errorf("Kind = %v, want %v", err.Kind, KindValidation)
	}
	if err.Err != nil {
		t.Errorf("Err should be nil")
	}
}

func TestNewInternalError(t *testing.T) {
	origErr := fmt.Errorf("nil pointer dereference")
	err := NewInternalError("PANIC", "unexpected error", origErr)

	if err.Kind != KindInternal {
		t.Errorf("Kind = %v, want %v", err.Kind, KindInternal)
	}
}

func TestIsConfigError(t *testing.T) {
	configErr := NewConfigError("TEST", "test", nil)
	networkErr := NewNetworkError("TEST", "test", nil)

	if !IsConfigError(configErr) {
		t.Errorf("IsConfigError() = false, want true")
	}
	if IsConfigError(networkErr) {
		t.Errorf("IsConfigError() = true, want false")
	}
	if IsConfigError(fmt.Errorf("plain error")) {
		t.Errorf("IsConfigError() = true, want false for plain error")
	}
}

func TestIsNetworkError(t *testing.T) {
	networkErr := NewNetworkError("TEST", "test", nil)
	configErr := NewConfigError("TEST", "test", nil)

	if !IsNetworkError(networkErr) {
		t.Errorf("IsNetworkError() = false, want true")
	}
	if IsNetworkError(configErr) {
		t.Errorf("IsNetworkError() = true, want false")
	}
}

func TestIsAPIError(t *testing.T) {
	apiErr := NewAPIError("TEST", "test", nil, 500)
	configErr := NewConfigError("TEST", "test", nil)

	if !IsAPIError(apiErr) {
		t.Errorf("IsAPIError() = false, want true")
	}
	if IsAPIError(configErr) {
		t.Errorf("IsAPIError() = true, want false")
	}
}

func TestGetStatusCode(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected int
	}{
		{
			name:     "API error with status code",
			err:      NewAPIError("TEST", "test", nil, 404),
			expected: 404,
		},
		{
			name:     "API error without status code",
			err:      NewConfigError("TEST", "test", nil),
			expected: 0,
		},
		{
			name:     "plain error",
			err:      fmt.Errorf("plain error"),
			expected: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := GetStatusCode(tt.err)
			if got != tt.expected {
				t.Errorf("GetStatusCode() = %d, want %d", got, tt.expected)
			}
		})
	}
}

func TestErrorWrapping(t *testing.T) {
	// Проверяем что errors.Is работает с обёрнутыми ошибками
	origErr := NewConfigError("FILE_NOT_FOUND", "config missing", ErrConfigNotFound)
	wrappedErr := fmt.Errorf("loading config: %w", origErr)

	if !errors.Is(wrappedErr, ErrConfigNotFound) {
		t.Errorf("errors.Is() should detect wrapped sentinel error")
	}

	var appErr *AppError
	if !errors.As(wrappedErr, &appErr) {
		t.Errorf("errors.As() should extract AppError")
	}
}
