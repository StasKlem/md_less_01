package api

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HTTPChatClient реализует интерфейс ChatClient
type HTTPChatClient struct {
	builder RequestBuilder
	parser  ResponseParser
	client  HTTPDoer
	timeout time.Duration
}

// NewHTTPChatClient создает новый HTTP клиент для API чата
// builder - строитель HTTP запросов
// parser - парсер ответов
// httpClient - HTTP клиент (может быть mock для тестов)
// timeout - глобальный таймаут для запроса
func NewHTTPChatClient(
	builder RequestBuilder,
	parser ResponseParser,
	httpClient HTTPDoer,
	timeout time.Duration,
) *HTTPChatClient {
	return &HTTPChatClient{
		builder: builder,
		parser:  parser,
		client:  httpClient,
		timeout: timeout,
	}
}

// SendMessage отправляет сообщение к API и возвращает ответ
// ctx - родительский контекст (может быть context.Background())
// message - текст сообщения пользователя
// Возвращает: ответ API, длительность выполнения, ошибку
// Использует context.WithTimeout для глобального таймаута запроса
func (c *HTTPChatClient) SendMessage(
	ctx context.Context,
	message string,
) (*Response, time.Duration, error) {
	// Создаем контекст с таймаутом
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	start := time.Now()

	// Создаем HTTP запрос
	req, err := c.builder.Build(message)
	if err != nil {
		return nil, 0, err
	}

	// Привязываем контекст к запросу для возможности отмены
	req = req.WithContext(ctx)

	// Отправляем запрос
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, time.Since(start), fmt.Errorf("ошибка отправки запроса: %w", err)
	}
	defer resp.Body.Close()

	// Читаем тело ответа
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, time.Since(start), fmt.Errorf("ошибка чтения ответа: %w", err)
	}

	duration := time.Since(start)

	// Проверяем статус ответа
	if resp.StatusCode != http.StatusOK {
		return nil, duration, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	// Парсим ответ
	result, err := c.parser.Parse(body)
	if err != nil {
		return nil, duration, err
	}

	return result, duration, nil
}
