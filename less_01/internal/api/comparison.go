package api

import (
	"encoding/json"
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

// truncateText обрезает текст до maxLen символов, показывая начало и конец
// text - исходный текст
// maxLen - максимальная длина (должна быть >= 10)
// Возвращает: обрезанный текст с <вырезаный текст> в середине
func truncateText(text string, maxLen int) string {
	if len(text) <= maxLen {
		return text
	}

	// Оставляем половину от maxLen для начала и конца
	// Учитываем длину маркера "\n<вырезаный текст>\n" (19 символов)
	markerLen := 19
	half := (maxLen - markerLen) / 2
	return text[:half] + "\n<вырезаный текст>\n" + text[len(text)-half:]
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
	truncated1 := truncateText(content1, 500)
	for _, line := range strings.Split(truncated1, "\n") {
		log.Println("   " + line)
	}

	log.Println("\n📋 ЗАПРОС 2 (без ограничений):")
	log.Printf("   Время: %v", dur2)
	log.Printf("   Длина: %d символов", len(content2))
	log.Printf("   Токенов (примерно): %d", len(content2)/4)
	log.Println("   Ответ:")
	log.Println("   " + strings.Repeat("-", 50))
	truncated2 := truncateText(content2, 500)
	for _, line := range strings.Split(truncated2, "\n") {
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

// LogRequestJSON логирует тело запроса в формате JSON
// reqBody - тело запроса для логирования
// Вывод ограничен 3000 символами, с показом начала и конца
func LogRequestJSON(reqBody *Request) {
	jsonData, err := json.MarshalIndent(reqBody, "", "  ")
	if err != nil {
		log.Printf("Ошибка маршалинга запроса: %v", err)
		return
	}
	log.Println("→ Request JSON:")
	log.Println(truncateText(string(jsonData), 3000))
}
