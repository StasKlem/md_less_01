package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"app/internal/api"
	"app/internal/config"
	"app/internal/ui"
)

func main() {
	ui.SetupLogging()

	// Загружаем конфигурацию
	cfg, err := config.Load()
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	// Читаем сообщение от пользователя
	userMessage, err := ui.ReadUserInput("Введите сообщение: ")
	if err != nil {
		log.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	// Создаем общие компоненты
	parser := api.NewResponseParser()
	httpClient := &http.Client{}

	// Запрос 1: с ограничениями
	builder1 := api.NewRequestBuilderWithOptions(
		cfg.APIKey,
		cfg.APIURL,
		cfg.Model,
		500, // maxTokens = 500 для ограниченного ответа
		[]string{"[END]", "[STOP]"},
		"Ответь кратко и по делу. Заверши ответ маркером <END>. Используй не более 2-3 предложений.",
	)
	client1 := api.NewHTTPChatClient(builder1, parser, httpClient, cfg.Timeout)

	log.Println("\n🔄 Отправка запроса С ОГРАНИЧЕНИЯМИ...")
	resp1, dur1, err := client1.SendMessage(context.Background(), userMessage)
	if err != nil {
		log.Printf("Error в запросе с ограничениями: %v\n", err)
		os.Exit(1)
	}

	// Запрос 2: без ограничений (только maxTokens = 4096)
	builder2 := api.NewRequestBuilder(
		cfg.APIKey,
		cfg.APIURL,
		cfg.Model,
		cfg.MaxTokens,
	)
	client2 := api.NewHTTPChatClient(builder2, parser, httpClient, cfg.Timeout)

	log.Println("\n🔄 Отправка запроса БЕЗ ОГРАНИЧЕНИЙ...")
	resp2, dur2, err := client2.SendMessage(context.Background(), userMessage)
	if err != nil {
		log.Printf("Error в запросе без ограничений: %v\n", err)
		os.Exit(1)
	}

	// Выводим сравнение
	api.PrintComparison(resp1, resp2, dur1, dur2)
}
