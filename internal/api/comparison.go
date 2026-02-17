package api

import (
	"fmt"
	"log"
	"strings"
	"time"
)

// GetAnswerContent извлекает текст ответа из Response
// resp - ответ от API
// Возвращает: текст сообщения от assistant или пустую строку
func GetAnswerContent(resp *Response) string {
	if len(resp.Choices) > 0 {
		return resp.Choices[0].Message.Content
	}
	return ""
}

// PrintComparison выводит сравнение двух ответов в консоль
// resp1, resp2 - ответы для сравнения
// dur1, dur2 - длительности выполнения
func PrintComparison(resp1, resp2 *Response, dur1, dur2 time.Duration) {
	content1 := GetAnswerContent(resp1)
	content2 := GetAnswerContent(resp2)

	separator := strings.Repeat("=", 60)

	log.Println("\n" + separator)
	log.Println("СРАВНЕНИЕ ОТВЕТОВ")
	log.Println(separator)

	log.Println("\n📋 ЗАПРОС 1 (с ограничениями):")
	log.Printf("   Время: %v", dur1)
	log.Printf("   Длина: %d символов", len(content1))
	log.Printf("   Токенов (примерно): %d", len(content1)/4)
	log.Println("   Ответ:")
	log.Println("   " + strings.Repeat("-", 50))
	for _, line := range strings.Split(content1, "\n") {
		log.Println("   " + line)
	}

	log.Println("\n📋 ЗАПРОС 2 (без ограничений):")
	log.Printf("   Время: %v", dur2)
	log.Printf("   Длина: %d символов", len(content2))
	log.Printf("   Токенов (примерно): %d", len(content2)/4)
	log.Println("   Ответ:")
	log.Println("   " + strings.Repeat("-", 50))
	for _, line := range strings.Split(content2, "\n") {
		log.Println("   " + line)
	}

	log.Println("\n" + separator)
	log.Println("РАЗНИЦА:")
	log.Printf("   Длина: %d символов", len(content2)-len(content1))
	log.Printf("   Время: %v", dur2-dur1)
	log.Println(separator)
}

// limitLines ограничивает количество строк в тексте
// text - исходный текст
// maxLines - максимальное количество строк
// Возвращает: текст с ограниченным количеством строк + суффикс с информацией
func limitLines(text string, maxLines int) string {
	lines := strings.Split(text, "\n")
	if len(lines) <= maxLines {
		return text
	}
	return strings.Join(lines[:maxLines], "\n") + fmt.Sprintf("\n... (+%d строк)", len(lines)-maxLines)
}
