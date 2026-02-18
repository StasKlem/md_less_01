// Package chat предоставляет модели данных и логику для управления историей диалога.
package chat

import (
	"errors"
	"sync"
)

// Role определяет роль участника диалога
type Role string

const (
	// RoleSystem - системное сообщение (инструкции для модели)
	RoleSystem Role = "system"
	// RoleUser - сообщение от пользователя
	RoleUser Role = "user"
	// RoleAssistant - сообщение от ассистента (модели)
	RoleAssistant Role = "assistant"
)

// Все возможные роли для валидации
var validRoles = map[Role]bool{
	RoleSystem:    true,
	RoleUser:      true,
	RoleAssistant: true,
}

// IsValid проверяет является ли роль валидной
func (r Role) IsValid() bool {
	return validRoles[r]
}

// String возвращает строковое представление роли
func (r Role) String() string {
	return string(r)
}

// Message представляет одно сообщение в диалоге
type Message struct {
	Role    Role   `json:"role"`
	Content string `json:"content"`
}

// NewMessage создаёт новое сообщение с валидацией
func NewMessage(role Role, content string) (Message, error) {
	if !role.IsValid() {
		return Message{}, errors.New("invalid role")
	}
	return Message{
		Role:    role,
		Content: content,
	}, nil
}

// ChatHistory хранит историю диалога для поддержания контекста
// Потокобезопасная реализация с использованием мьютекса
type ChatHistory struct {
	mu           sync.RWMutex
	messages     []Message
	systemPrompt string
}

// NewChatHistory создаёт новую историю диалога с системным промптом
func NewChatHistory(systemPrompt string) *ChatHistory {
	h := &ChatHistory{
		messages:     make([]Message, 0),
		systemPrompt: systemPrompt,
	}
	if systemPrompt != "" {
		h.messages = append(h.messages, Message{
			Role:    RoleSystem,
			Content: systemPrompt,
		})
	}
	return h
}

// AddUser добавляет сообщение пользователя в историю
func (h *ChatHistory) AddUser(content string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.messages = append(h.messages, Message{
		Role:    RoleUser,
		Content: content,
	})
}

// AddAssistant добавляет ответ ассистента в историю
func (h *ChatHistory) AddAssistant(content string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.messages = append(h.messages, Message{
		Role:    RoleAssistant,
		Content: content,
	})
}

// UpdateLastAssistant обновляет последнее сообщение ассистента
// Используется при потоковом получении ответа
// Возвращает false если не удалось обновить (нет сообщений ассистента)
func (h *ChatHistory) UpdateLastAssistant(content string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()

	if len(h.messages) > 0 && h.messages[len(h.messages)-1].Role == RoleAssistant {
		h.messages[len(h.messages)-1].Content = content
		return true
	}
	return false
}

// GetMessages возвращает все сообщения истории (копия для безопасности)
func (h *ChatHistory) GetMessages() []Message {
	h.mu.RLock()
	defer h.mu.RUnlock()

	// Возвращаем копию слайса для безопасности
	result := make([]Message, len(h.messages))
	copy(result, h.messages)
	return result
}

// GetDisplayMessages возвращает сообщения для отображения (без системных)
func (h *ChatHistory) GetDisplayMessages() []Message {
	h.mu.RLock()
	defer h.mu.RUnlock()

	result := make([]Message, 0)
	for _, msg := range h.messages {
		if msg.Role != RoleSystem {
			result = append(result, msg)
		}
	}
	return result
}

// Clear очищает историю, сохраняя только системный промпт
func (h *ChatHistory) Clear(systemPrompt string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.systemPrompt = systemPrompt
	h.messages = make([]Message, 0)
	if systemPrompt != "" {
		h.messages = append(h.messages, Message{
			Role:    RoleSystem,
			Content: systemPrompt,
		})
	}
}

// Len возвращает количество сообщений в истории
func (h *ChatHistory) Len() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.messages)
}

// LastUserMessage возвращает последнее сообщение пользователя
func (h *ChatHistory) LastUserMessage() *Message {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for i := len(h.messages) - 1; i >= 0; i-- {
		if h.messages[i].Role == RoleUser {
			// Возвращаем копию
			msg := h.messages[i]
			return &msg
		}
	}
	return nil
}

// LastAssistantMessage возвращает последнее сообщение ассистента
func (h *ChatHistory) LastAssistantMessage() *Message {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for i := len(h.messages) - 1; i >= 0; i-- {
		if h.messages[i].Role == RoleAssistant {
			msg := h.messages[i]
			return &msg
		}
	}
	return nil
}

// SetSystemPrompt устанавливает или обновляет системный промпт
func (h *ChatHistory) SetSystemPrompt(prompt string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.systemPrompt = prompt

	// Если есть системное сообщение, обновляем его
	if len(h.messages) > 0 && h.messages[0].Role == RoleSystem {
		h.messages[0].Content = prompt
	} else if prompt != "" {
		// Вставляем системное сообщение в начало
		newMessages := make([]Message, 0, len(h.messages)+1)
		newMessages = append(newMessages, Message{
			Role:    RoleSystem,
			Content: prompt,
		})
		newMessages = append(newMessages, h.messages...)
		h.messages = newMessages
	}
}

// GetSystemPrompt возвращает текущий системный промпт
func (h *ChatHistory) GetSystemPrompt() string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.systemPrompt
}

// RemoveLast удаляет последнее сообщение из истории
// Возвращает false если история пуста или содержит только системный промпт
func (h *ChatHistory) RemoveLast() bool {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Не удаляем системный промпт
	if len(h.messages) <= 1 {
		return false
	}

	h.messages = h.messages[:len(h.messages)-1]
	return true
}

// TokenEstimate возвращает приблизительную оценку количества токенов
// Использует простую эвристику: 1 токен ≈ 4 символа
func (h *ChatHistory) TokenEstimate() int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	totalChars := 0
	for _, msg := range h.messages {
		totalChars += len(msg.Content)
	}
	// Примерно 4 символа на токен + накладные расходы
	return totalChars/4 + 100
}

// Copy создаёт глубокую копию истории
func (h *ChatHistory) Copy() *ChatHistory {
	h.mu.RLock()
	defer h.mu.RUnlock()

	newHistory := &ChatHistory{
		messages:     make([]Message, len(h.messages)),
		systemPrompt: h.systemPrompt,
	}
	copy(newHistory.messages, h.messages)
	return newHistory
}
