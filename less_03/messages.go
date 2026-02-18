package main

// Role определяет роль участника диалога
type Role string

const (
	RoleSystem    Role = "system"
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Message представляет одно сообщение в диалоге
type Message struct {
	Role    Role   `json:"role"`
	Content string `json:"content"`
}

// ChatHistory хранит историю диалога для поддержания контекста
type ChatHistory struct {
	messages []Message
}

// NewChatHistory создаёт новую историю диалога с системным промптом
func NewChatHistory(systemPrompt string) *ChatHistory {
	h := &ChatHistory{
		messages: make([]Message, 0),
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
	h.messages = append(h.messages, Message{
		Role:    RoleUser,
		Content: content,
	})
}

// AddAssistant добавляет ответ ассистента в историю
func (h *ChatHistory) AddAssistant(content string) {
	h.messages = append(h.messages, Message{
		Role:    RoleAssistant,
		Content: content,
	})
}

// UpdateLastAssistant обновляет последнее сообщение ассистента
// Используется при потоковом получении ответа
func (h *ChatHistory) UpdateLastAssistant(content string) {
	if len(h.messages) > 0 && h.messages[len(h.messages)-1].Role == RoleAssistant {
		h.messages[len(h.messages)-1].Content = content
	}
}

// GetMessages возвращает все сообщения истории
func (h *ChatHistory) GetMessages() []Message {
	return h.messages
}

// GetDisplayMessages возвращает сообщения для отображения (без системных)
func (h *ChatHistory) GetDisplayMessages() []Message {
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
	return len(h.messages)
}

// LastUserMessage возвращает последнее сообщение пользователя
func (h *ChatHistory) LastUserMessage() *Message {
	for i := len(h.messages) - 1; i >= 0; i-- {
		if h.messages[i].Role == RoleUser {
			return &h.messages[i]
		}
	}
	return nil
}
