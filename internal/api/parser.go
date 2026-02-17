package api

import (
	"encoding/json"
	"fmt"
)

// JSONResponseParser парсит JSON ответы от API
type JSONResponseParser struct{}

// NewResponseParser создает новый парсер
func NewResponseParser() *JSONResponseParser {
	return &JSONResponseParser{}
}

// Parse преобразует JSON тело ответа в структуру Response
// body - тело HTTP ответа в формате JSON
// Возвращает: распарсенный Response или ошибку парсинга
func (p *JSONResponseParser) Parse(body []byte) (*Response, error) {
	var result Response
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("ошибка парсинга JSON: %w", err)
	}
	return &result, nil
}
