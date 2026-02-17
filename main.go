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
		client:        &http.Client{Timeout: 30 * time.Second},
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
	log.Println(string(jsonData))
	return nil
}

// LogResponse логирует ответ
func LogResponse(body []byte, duration time.Duration, statusCode int) {
	log.Printf("← Response time: %v, status: %d", duration, statusCode)

	var rawResponse map[string]interface{}
	if err := json.Unmarshal(body, &rawResponse); err == nil {
		formattedResponse, _ := json.MarshalIndent(rawResponse, "", "  ")
		log.Println("← Response:")
		log.Println(string(formattedResponse))
	}
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

	// Настройка ограничения на длину ответа (500 токенов)
	client.SetMaxTokens(500)

	// Настройка stop sequences для явного завершения ответа
	client.SetStopSequences([]string{"[END]", "[STOP]"})

	// Настройка формата ответа с явными инструкциями
	formatDesc := `Ответь кратко и по делу. 
Заверши ответ маркером <END>.
Используй не более 2-3 предложений.`
	client.SetFormatDescription(formatDesc)

	req, err := client.CreateChatRequest(userMessage)
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	// Логируем тело запроса для отладки
	bodyBytes, _ := io.ReadAll(req.Body)
	req.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
	var reqBody Request
	json.Unmarshal(bodyBytes, &reqBody)
	LogRequest(reqBody)
	req.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

	body, duration, err := client.SendRequest(req)
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	LogResponse(body, duration, http.StatusOK)

	response, err := ParseResponse(body)
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	PrintAnswer(response)
}
