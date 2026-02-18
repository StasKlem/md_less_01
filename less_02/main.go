package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// Анимация загрузки
var loadingFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// Loader - анимация загрузки
type Loader struct {
	stop   chan struct{}
	done   chan struct{}
	message string
}

// NewLoader создает новый лоадер
func NewLoader(message string) *Loader {
	return &Loader{
		stop:    make(chan struct{}),
		done:    make(chan struct{}),
		message: message,
	}
}

// Start запускает анимацию
func (l *Loader) Start() {
	go func() {
		i := 0
		for {
			select {
			case <-l.stop:
				fmt.Printf("\r\033[K") // Очистить строку
				close(l.done)
				return
			default:
				fmt.Printf("\r\033[K%s %s", loadingFrames[i%len(loadingFrames)], l.message)
				i++
				time.Sleep(100 * time.Millisecond)
			}
		}
	}()
}

// Stop останавливает анимацию
func (l *Loader) Stop() {
	close(l.stop)
	<-l.done
}

const (
	apiEndpoint = "https://routerai.ru/api/v1/chat/completions"
)

// LLMMessage - сообщение для LLM API
type LLMMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// LLMRequest - запрос к LLM API
type LLMRequest struct {
	Model       string       `json:"model"`
	Messages    []LLMMessage `json:"messages"`
	Temperature float64      `json:"temperature"`
}

// LLMResponse - ответ от LLM API
type LLMResponse struct {
	Choices []struct {
		Message LLMMessage `json:"message"`
	} `json:"choices"`
}

// PizzaOrder - структура заказа пиццы
type PizzaOrder struct {
	Message string   `json:"message"`
	Pizza   []string `json:"pizza"`
}

// PizzaBot - основной тип приложения
type PizzaBot struct {
	client      *http.Client
	messages    []LLMMessage
	ingredients []string
	reader      *bufio.Reader
	logger      *log.Logger
	logFile     *os.File
}

// NewPizzaBot создает нового бота
func NewPizzaBot() *PizzaBot {
	// Открываем файл для логирования
	logFile, err := os.OpenFile("pizza-bot.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		fmt.Printf("Ошибка открытия файла логов: %v\n", err)
		os.Exit(1)
	}

	logger := log.New(logFile, "", log.Ldate|log.Ltime|log.Lmicroseconds)

	return &PizzaBot{
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		messages:    make([]LLMMessage, 0),
		ingredients: make([]string, 0),
		reader:      bufio.NewReader(os.Stdin),
		logger:      logger,
		logFile:     logFile,
	}
}

// getAPIKey получает API ключ из переменной окружения
func getAPIKey() string {
	key := os.Getenv("LLM_API_KEY")
	if key == "" {
		return ""
	}
	return key
}

// getSystemPrompt возвращает системный промпт для бота
func getSystemPrompt() string {
	return `Ты робот для заказа пиццы. Твоя задача - помочь пользователю составить пиццу.
Пользователь будет называть ингредиенты, которые он хочет добавить в пиццу.
Ты должен отвечать ТОЛЬКО в формате JSON:
{
	"message": "твое сообщение пользователю",
	"pizza": ["ингредиент1", "ингредиент2", ...]
}

В массив pizza включай все ингредиенты, которые назвал пользователь за все время общения.
Когда пользователь пишет "Все", это значит что он закончил заказ. В этом случае ответь:
{
	"message": "Заказ принят",
	"pizza": ["список всех ингредиентов"]
}

Не добавляй никакого текста кроме JSON.`
}

// sendMessage отправляет сообщение LLM и получает ответ
func (pb *PizzaBot) sendMessage(ctx context.Context, userMessage string) (*PizzaOrder, error) {
	// Логируем входное сообщение
	pb.logger.Printf("Входное сообщение: %s", userMessage)

	// Добавляем сообщение пользователя в историю
	pb.messages = append(pb.messages, LLMMessage{
		Role:    "user",
		Content: userMessage,
	})

	// Формируем запрос
	request := LLMRequest{
		Model: "deepseek/deepseek-v3.2",
		Messages: append([]LLMMessage{
			{Role: "system", Content: getSystemPrompt()},
		}, pb.messages...),
		Temperature: 0.7,
	}

	// Сериализуем запрос в JSON
	requestBody, err := json.MarshalIndent(request, "", "  ")
	if err != nil {
		pb.logger.Printf("Ошибка сериализации запроса: %v", err)
		return nil, fmt.Errorf("ошибка сериализации запроса: %w", err)
	}

	// Логируем тело запроса
	pb.logger.Printf("Тело запроса:\n%s", string(requestBody))

	// Создаем HTTP запрос
	req, err := http.NewRequestWithContext(ctx, "POST", apiEndpoint, bytes.NewReader(requestBody))
	if err != nil {
		pb.logger.Printf("Ошибка создания запроса: %v", err)
		return nil, fmt.Errorf("ошибка создания запроса: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+getAPIKey())

	// Отправляем запрос
	pb.logger.Printf("Отправка запроса на %s", apiEndpoint)
	
	// Запускаем анимацию загрузки
	loader := NewLoader("Получаю ответ от нейросети...")
	loader.Start()
	
	resp, err := pb.client.Do(req)
	
	// Останавливаем анимацию
	loader.Stop()
	
	if err != nil {
		pb.logger.Printf("Ошибка отправки запроса: %v", err)
		return nil, fmt.Errorf("ошибка отправки запроса: %w", err)
	}
	defer resp.Body.Close()

	// Читаем ответ
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		pb.logger.Printf("Ошибка чтения ответа: %v", err)
		return nil, fmt.Errorf("ошибка чтения ответа: %w", err)
	}

	// Логируем ответ
	pb.logger.Printf("Статус ответа: %d", resp.StatusCode)

	// Форматируем ответ для красивого вывода
	var formattedBody json.RawMessage
	if err := json.Unmarshal(body, &formattedBody); err != nil {
		pb.logger.Printf("Тело ответа: %s", string(body))
	} else {
		indentBody, _ := json.MarshalIndent(formattedBody, "", "  ")
		pb.logger.Printf("Тело ответа:\n%s", string(indentBody))
	}

	if resp.StatusCode != http.StatusOK {
		pb.logger.Printf("Ошибка API: статус %d", resp.StatusCode)
		return nil, fmt.Errorf("ошибка API (статус %d): %s", resp.StatusCode, string(body))
	}

	// Парсим ответ
	var llmResponse LLMResponse
	if err := json.Unmarshal(body, &llmResponse); err != nil {
		pb.logger.Printf("Ошибка парсинга ответа: %v", err)
		return nil, fmt.Errorf("ошибка парсинга ответа: %w", err)
	}

	if len(llmResponse.Choices) == 0 {
		pb.logger.Printf("Пустой ответ от API")
		return nil, fmt.Errorf("пустой ответ от API")
	}

	// Извлекаем сообщение от LLM
	content := llmResponse.Choices[0].Message.Content
	pb.logger.Printf("Сообщение от LLM: %s", content)

	// Добавляем ответ ассистента в историю
	pb.messages = append(pb.messages, LLMMessage{
		Role:    "assistant",
		Content: content,
	})

	// Парсим JSON ответ от LLM
	var order PizzaOrder
	if err := json.Unmarshal([]byte(content), &order); err != nil {
		pb.logger.Printf("Ошибка парсинга JSON ответа: %v", err)
		return nil, fmt.Errorf("ошибка парсинга JSON ответа: %w", err)
	}

	pb.logger.Printf("Распарсенный заказ: message=%s, pizza=%v", order.Message, order.Pizza)

	return &order, nil
}

// Run запускает основной цикл приложения
func (pb *PizzaBot) Run() {
	defer pb.logFile.Close()

	ctx := context.Background()

	pb.logger.Println("=== Запуск приложения ===")

	fmt.Println("🍕 Добро пожаловать в пиццерию!")
	fmt.Println("Назовите ингредиенты для вашей пиццы.")
	fmt.Println("Когда закончите, введите 'Все'.")
	fmt.Println(strings.Repeat("-", 40))

	for {
		fmt.Print("\nВы: ")

		input, err := pb.reader.ReadString('\n')
		if err != nil {
			pb.logger.Printf("Ошибка ввода: %v", err)
			fmt.Printf("Ошибка ввода: %v\n", err)
			continue
		}

		input = strings.TrimSpace(input)
		if input == "" {
			continue
		}

		pb.logger.Printf("Пользователь ввел: %s", input)

		// Отправляем сообщение LLM
		order, err := pb.sendMessage(ctx, input)
		if err != nil {
			pb.logger.Printf("Ошибка sendMessage: %v", err)
			fmt.Printf("Ошибка: %v\n", err)
			continue
		}

		// Выводим ответ
		fmt.Printf("\n🤖 Бот: %s\n", order.Message)

		// Обновляем список ингредиентов
		if len(order.Pizza) > 0 {
			pb.ingredients = order.Pizza
			fmt.Printf("📋 Ингредиенты в пицце: %v\n", pb.ingredients)
		}

		// Проверяем, закончен ли заказ
		if strings.Contains(strings.ToLower(order.Message), "заказ принят") {
			pb.logger.Println("=== Заказ завершен ===")
			fmt.Println("\n✅ Спасибо за заказ! Приятного аппетита!")
			break
		}
	}
}

func main() {
	if getAPIKey() == "" {
		fmt.Println("Ошибка: укажите API ключ в переменной окружения LLM_API_KEY")
		os.Exit(1)
	}

	bot := NewPizzaBot()
	bot.Run()
}
