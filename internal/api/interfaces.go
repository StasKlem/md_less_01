package api

import (
	"context"
	"net/http"
	"time"
)

// ChatClient определяет интерфейс для работы с API чата
type ChatClient interface {
	// SendMessage отправляет сообщение к API и возвращает ответ
	// ctx позволяет контролировать таймаут и отмену запроса
	// message - текст сообщения пользователя
	// Возвращает: ответ API, длительность выполнения, ошибку
	SendMessage(ctx context.Context, message string) (*Response, time.Duration, error)
}

// HTTPDoer определяет интерфейс для выполнения HTTP запросов
// Используется для возможности mock'ирования в тестах
type HTTPDoer interface {
	// Do выполняет HTTP запрос и возвращает ответ
	Do(req *http.Request) (*http.Response, error)
}

// RequestBuilder определяет интерфейс для создания HTTP запросов
type RequestBuilder interface {
	// Build создает HTTP запрос из сообщения пользователя
	// userMessage - текст сообщения для отправки
	// Возвращает: готовый HTTP запрос или ошибку
	Build(userMessage string) (*http.Request, error)
}

// ResponseParser определяет интерфейс для парсинга ответов API
type ResponseParser interface {
	// Parse преобразует тело ответа в структуру Response
	// body - тело HTTP ответа
	// Возвращает: распарсенный Response или ошибку
	Parse(body []byte) (*Response, error)
}
