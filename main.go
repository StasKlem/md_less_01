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
	defaultModel = "deepseek/deepseek-v3.2"
	apiURL       = "https://routerai.ru/api/v1/chat/completions"
	apiKeyEnv    = "ROUTERAI_API_KEY"
)

// Request представляет структуру запроса к API
type Request struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
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
	apiKey string
	client *http.Client
	model  string
}

// NewAPIClient создает новый клиент API
func NewAPIClient(apiKey string) *APIClient {
	return &APIClient{
		apiKey: apiKey,
		client: &http.Client{Timeout: 30 * time.Second},
		model:  defaultModel,
	}
}

// SetModel устанавливает модель для запросов
func (c *APIClient) SetModel(model string) {
	c.model = model
}

// CreateChatRequest создает запрос к API чата
func (c *APIClient) CreateChatRequest(userMessage string) (*http.Request, error) {
	reqBody := Request{
		Model: c.model,
		Messages: []Message{
			{Role: "user", Content: userMessage},
		},
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

	reqBody := Request{
		Model: defaultModel,
		Messages: []Message{
			{Role: "user", Content: userMessage},
		},
	}
	LogRequest(reqBody)

	req, err := client.CreateChatRequest(userMessage)
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

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
