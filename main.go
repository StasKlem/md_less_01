package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	defaultModel     = "deepseek/deepseek-v3.2"
	apiURL           = "https://routerai.ru/api/v1/chat/completions"
	apiKeyEnv        = "ROUTERAI_API_KEY"
	defaultMaxTokens = 500
)

// Request представляет структуру запроса к API
type Request struct {
	Model          string          `json:"model"`
	Messages       []Message       `json:"messages"`
	MaxTokens      int             `json:"max_tokens,omitempty"`
	Stop           []string        `json:"stop,omitempty"`
	ResponseFormat *ResponseFormat `json:"response_format,omitempty"`
}

// ResponseFormat представляет формат ответа
type ResponseFormat struct {
	Type       string      `json:"type"`
	JSONSchema *JSONSchema `json:"json_schema,omitempty"`
}

// JSONSchema представляет JSON схему для структурированного вывода
type JSONSchema struct {
	Name   string                 `json:"name"`
	Strict bool                   `json:"strict"`
	Schema map[string]interface{} `json:"schema"`
}

// Message представляет сообщение в чате
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Response представляет структуру ответа от API
type Response struct {
	Choices []Choice `json:"choices"`
}

// Choice представляет вариант ответа от API
type Choice struct {
	Message Message `json:"message"`
}

// APIClient представляет клиент для работы с API
type APIClient struct {
	apiKey            string
	client            *http.Client
	model             string
	maxTokens         int
	stopSequences     []string
	responseFormat    *ResponseFormat
	formatDescription string
}

// NewAPIClient создает новый клиент API
func NewAPIClient(apiKey string) *APIClient {
	return &APIClient{
		apiKey:        apiKey,
		client:        &http.Client{Timeout: 240 * time.Second},
		model:         defaultModel,
		maxTokens:     defaultMaxTokens,
		stopSequences: []string{},
	}
}

// SetModel устанавливает модель для запросов
func (c *APIClient) SetModel(model string) {
	c.model = model
}

// SetMaxTokens устанавливает максимальное количество токенов
func (c *APIClient) SetMaxTokens(tokens int) {
	c.maxTokens = tokens
}

// SetStopSequences устанавливает stop sequences для завершения генерации
func (c *APIClient) SetStopSequences(sequences []string) {
	c.stopSequences = sequences
}

// SetResponseFormat устанавливает формат ответа (json_object или text)
func (c *APIClient) SetResponseFormat(formatType string) {
	c.responseFormat = &ResponseFormat{
		Type: formatType,
	}
}

// SetJSONSchema устанавливает JSON схему для структурированного вывода
func (c *APIClient) SetJSONSchema(name string, schema map[string]interface{}) {
	c.responseFormat = &ResponseFormat{
		Type: "json_schema",
		JSONSchema: &JSONSchema{
			Name:   name,
			Strict: true,
			Schema: schema,
		},
	}
}

// SetFormatDescription устанавливает текстовое описание формата ответа (через системное сообщение)
func (c *APIClient) SetFormatDescription(description string) {
	c.formatDescription = description
}

// CreateChatRequest создает запрос к API чата
func (c *APIClient) CreateChatRequest(userMessage string) (*http.Request, error) {
	messages := []Message{}

	// Добавляем системное сообщение с инструкциями о формате, если оно задано
	if c.formatDescription != "" {
		messages = append(messages, Message{
			Role:    "system",
			Content: c.formatDescription,
		})
	}

	// Добавляем сообщение пользователя
	messages = append(messages, Message{
		Role:    "user",
		Content: userMessage,
	})

	reqBody := Request{
		Model:          c.model,
		Messages:       messages,
		MaxTokens:      c.maxTokens,
		ResponseFormat: c.responseFormat,
	}

	// Добавляем stop sequences, если они заданы
	if len(c.stopSequences) > 0 {
		reqBody.Stop = c.stopSequences
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("ошибка маршалинга JSON: %w", err)
	}

	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("ошибка создания запроса: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	return req, nil
}

// SendRequest отправляет запрос и возвращает ответ
func (c *APIClient) SendRequest(req *http.Request) ([]byte, time.Duration, error) {
	start := time.Now()
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("ошибка отправки запроса: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(start)

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, duration, fmt.Errorf("ошибка чтения ответа: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return body, duration, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	return body, duration, nil
}

// ParseResponse парсит ответ API
func ParseResponse(body []byte) (*Response, error) {
	var result Response
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("ошибка парсинга JSON: %w", err)
	}
	return &result, nil
}

// LogRequest логирует запрос
func LogRequest(reqBody Request) error {
	jsonData, err := json.MarshalIndent(reqBody, "", "  ")
	if err != nil {
		return err
	}
	log.Println("→ Request:")
	log.Println(limitLines(string(jsonData), 20))
	return nil
}

// LogResponse логирует ответ
func LogResponse(body []byte, duration time.Duration, statusCode int) {
	log.Printf("← Response time: %v, status: %d", duration, statusCode)

	var rawResponse map[string]interface{}
	if err := json.Unmarshal(body, &rawResponse); err == nil {
		formattedResponse, _ := json.MarshalIndent(rawResponse, "", "  ")
		log.Println("← Response:")
		log.Println(limitLines(string(formattedResponse), 20))
	}
}

// limitLines ограничивает вывод указанным количеством строк
func limitLines(text string, maxLines int) string {
	lines := strings.Split(text, "\n")
	if len(lines) <= maxLines {
		return text
	}
	return strings.Join(lines[:maxLines], "\n") + fmt.Sprintf("\n... (+%d строк)", len(lines)-maxLines)
}

// ReadUserInput читает ввод пользователя
func ReadUserInput(prompt string) (string, error) {
	fmt.Print(prompt)
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		if err := scanner.Err(); err != nil {
			return "", fmt.Errorf("ошибка чтения ввода: %w", err)
		}
		return "", fmt.Errorf("ввод прерван")
	}
	return scanner.Text(), nil
}

// PrintAnswer выводит ответ
func PrintAnswer(response *Response) {
	if len(response.Choices) > 0 {
		log.Println("→ Answer:", response.Choices[0].Message.Content)
	} else {
		log.Println("Нет ответа от API")
	}
}

// GetAnswerContent возвращает текст ответа
func GetAnswerContent(response *Response) string {
	if len(response.Choices) > 0 {
		return response.Choices[0].Message.Content
	}
	return ""
}

// ResetConstraints сбрасывает все ограничения клиента (устанавливает maxTokens = 4096 вместо неограниченного)
func (c *APIClient) ResetConstraints() {
	c.maxTokens = 4096
	c.stopSequences = []string{}
	c.responseFormat = nil
	c.formatDescription = ""
}

// PrintComparison выводит сравнение двух ответов
func PrintComparison(response1 *Response, duration1 time.Duration, response2 *Response, duration2 time.Duration) {
	content1 := GetAnswerContent(response1)
	content2 := GetAnswerContent(response2)

	log.Println("\n" + strings.Repeat("=", 60))
	log.Println("СРАВНЕНИЕ ОТВЕТОВ")
	log.Println(strings.Repeat("=", 60))

	log.Println("\n📋 ЗАПРОС 1 (с ограничениями):")
	log.Printf("   Время: %v", duration1)
	log.Printf("   Длина: %d символов", len(content1))
	log.Printf("   Токенов (примерно): %d", len(content1)/4)
	log.Println("   Ответ:")
	log.Println("   " + strings.Repeat("-", 50))
	for _, line := range strings.Split(content1, "\n") {
		log.Println("   " + line)
	}

	log.Println("\n📋 ЗАПРОС 2 (без ограничений):")
	log.Printf("   Время: %v", duration2)
	log.Printf("   Длина: %d символов", len(content2))
	log.Printf("   Токенов (примерно): %d", len(content2)/4)
	log.Println("   Ответ:")
	log.Println("   " + strings.Repeat("-", 50))
	for _, line := range strings.Split(content2, "\n") {
		log.Println("   " + line)
	}

	log.Println("\n" + strings.Repeat("=", 60))
	log.Println("РАЗНИЦА:")
	log.Printf("   Длина: %d символов", len(content2)-len(content1))
	log.Printf("   Время: %v", duration2-duration1)
	log.Println(strings.Repeat("=", 60))
}

// GetAPIKey получает API ключ из переменной окружения
func GetAPIKey() (string, error) {
	apiKey := os.Getenv(apiKeyEnv)
	if apiKey == "" {
		return "", fmt.Errorf("переменная окружения %s не установлена", apiKeyEnv)
	}
	return apiKey, nil
}

// SetupLogging настраивает логирование
func SetupLogging() {
	log.SetFlags(0)
	log.SetOutput(os.Stdout)
}

// makeRequest выполняет один запрос и возвращает ответ
func makeRequest(client *APIClient, userMessage string, withConstraints bool) (*Response, time.Duration, error) {
	if withConstraints {
		// Настройка ограничений
		client.SetMaxTokens(500)
		client.SetStopSequences([]string{"[END]", "[STOP]"})
		formatDesc := `Ответь кратко и по делу. 
Заверши ответ маркером <END>.
Используй не более 2-3 предложений.`
		client.SetFormatDescription(formatDesc)
		log.Println("\n🔄 Отправка запроса С ОГРАНИЧЕНИЯМИ...")
	} else {
		// Сброс ограничений
		client.ResetConstraints()
		log.Println("\n🔄 Отправка запроса БЕЗ ОГРАНИЧЕНИЙ...")
	}

	req, err := client.CreateChatRequest(userMessage)
	if err != nil {
		return nil, 0, err
	}

	body, duration, err := client.SendRequest(req)
	if err != nil {
		return nil, duration, err
	}

	response, err := ParseResponse(body)
	if err != nil {
		return nil, duration, err
	}

	return response, duration, nil
}

func main() {
	SetupLogging()

	apiKey, err := GetAPIKey()
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	userMessage, err := ReadUserInput("Введите сообщение: ")
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	client := NewAPIClient(apiKey)

	// Запрос 1: с ограничениями
	response1, duration1, err := makeRequest(client, userMessage, true)
	if err != nil {
		log.Printf("Error в запросе с ограничениями: %v\n", err)
		os.Exit(1)
	}

	// Запрос 2: без ограничений
	response2, duration2, err := makeRequest(client, userMessage, false)
	if err != nil {
		log.Printf("Error в запросе без ограничений: %v\n", err)
		os.Exit(1)
	}

	// Вывод сравнения
	PrintComparison(response1, duration1, response2, duration2)
}
