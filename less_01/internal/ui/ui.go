// Package ui содержит функции для взаимодействия с пользователем
package ui

import (
	"bufio"
	"fmt"
	"log"
	"os"
)

// ReadUserInput читает строку ввода от пользователя
// prompt - текст приглашения для ввода (будет выведен перед ожиданием ввода)
// Возвращает: введенный текст или ошибку чтения
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

// SetupLogging настраивает стандартный logger
// Убирает временные метки и направляет вывод в stdout
func SetupLogging() {
	log.SetFlags(0)
	log.SetOutput(os.Stdout)
}
