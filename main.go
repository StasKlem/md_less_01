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

func main() {
	// Настройка логирования: убираем временные метки, выводим в stdout
	log.SetFlags(0)
	log.SetOutput(os.Stdout)

	// Получаем API ключ из переменной окружения
	apiKey := os.Getenv("ROUTERAI_API_KEY")
	if apiKey == "" {
		log.Println("Error: ROUTERAI_API_KEY environment variable not set")
		os.Exit(1)
	}

	// URL API эндпоинта
	url := "https://routerai.ru/api/v1/chat/completions"

	// Запрос сообщения у пользователя
	fmt.Print("Введите сообщение: ")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	userMessage := scanner.Text()

	// Формирование тела запроса
	reqBody := Request{
		Model: "deepseek/deepseek-v3.2",
		Messages: []Message{
			{Role: "user", Content: userMessage},
		},
	}

	// Преобразование структуры запроса в JSON с форматированием
	jsonData, err := json.MarshalIndent(reqBody, "", "  ")
	if err != nil {
		log.Printf("Error marshaling JSON: %v\n", err)
		os.Exit(1)
	}

	// Логирование исходящего запроса
	log.Println("→ Request:")
	log.Println(string(jsonData))

	// Создание HTTP запроса
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		log.Printf("Error creating request: %v\n", err)
		os.Exit(1)
	}

	// Установка заголовков запроса
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	// Замер времени начала запроса
	start := time.Now()

	// Отправка HTTP запроса
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("Error making request: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	// Логирование времени выполнения и статуса ответа
	log.Printf("← Response time: %v, status: %d", time.Since(start), resp.StatusCode)

	// Чтение тела ответа
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("Error reading response: %v\n", err)
		os.Exit(1)
	}

	// Парсинг ответа в generic map для красивого вывода JSON
	var rawResponse map[string]interface{}
	if err := json.Unmarshal(body, &rawResponse); err != nil {
		log.Printf("Error parsing response: %v\n", err)
		os.Exit(1)
	}

	// Форматирование и логирование ответа в JSON
	formattedResponse, _ := json.MarshalIndent(rawResponse, "", "  ")
	log.Println("← Response:")
	log.Println(string(formattedResponse))

	// Проверка статуса ответа
	if resp.StatusCode != http.StatusOK {
		log.Printf("Error: HTTP %d\n%s\n", resp.StatusCode, string(body))
		os.Exit(1)
	}

	// Парсинг ответа в структуру для получения текста
	var result Response
	if err := json.Unmarshal(body, &result); err != nil {
		log.Printf("Error parsing JSON: %v\n", err)
		os.Exit(1)
	}

	// Вывод ответа от API
	if len(result.Choices) > 0 {
		log.Println("→ Answer:", result.Choices[0].Message.Content)
	} else {
		log.Println("No response from API")
	}
}
