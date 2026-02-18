package chat

import (
	"testing"
)

func TestRole_IsValid(t *testing.T) {
	tests := []struct {
		name     string
		role     Role
		expected bool
	}{
		{"system is valid", RoleSystem, true},
		{"user is valid", RoleUser, true},
		{"assistant is valid", RoleAssistant, true},
		{"empty is invalid", Role(""), false},
		{"unknown is invalid", Role("unknown"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.role.IsValid()
			if got != tt.expected {
				t.Errorf("Role.IsValid() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestRole_String(t *testing.T) {
	tests := []struct {
		name     string
		role     Role
		expected string
	}{
		{"system", RoleSystem, "system"},
		{"user", RoleUser, "user"},
		{"assistant", RoleAssistant, "assistant"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.role.String()
			if got != tt.expected {
				t.Errorf("Role.String() = %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestNewMessage(t *testing.T) {
	tests := []struct {
		name    string
		role    Role
		content string
		wantErr bool
	}{
		{"valid user message", RoleUser, "Hello", false},
		{"valid assistant message", RoleAssistant, "Hi there", false},
		{"valid system message", RoleSystem, "You are helpful", false},
		{"empty content allowed", RoleUser, "", false},
		{"invalid role", Role("invalid"), "content", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg, err := NewMessage(tt.role, tt.content)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewMessage() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr {
				if msg.Role != tt.role {
					t.Errorf("Message.Role = %v, want %v", msg.Role, tt.role)
				}
				if msg.Content != tt.content {
					t.Errorf("Message.Content = %q, want %q", msg.Content, tt.content)
				}
			}
		})
	}
}

func TestNewChatHistory(t *testing.T) {
	t.Run("with system prompt", func(t *testing.T) {
		h := NewChatHistory("You are helpful")
		if h.Len() != 1 {
			t.Errorf("Len() = %d, want 1", h.Len())
		}
		msg := h.LastUserMessage() // Should be nil
		if msg != nil {
			t.Errorf("LastUserMessage() should be nil")
		}
	})

	t.Run("without system prompt", func(t *testing.T) {
		h := NewChatHistory("")
		if h.Len() != 0 {
			t.Errorf("Len() = %d, want 0", h.Len())
		}
	})
}

func TestChatHistory_AddUser(t *testing.T) {
	h := NewChatHistory("system")
	h.AddUser("Hello")
	h.AddUser("How are you?")

	if h.Len() != 3 { // system + 2 user messages
		t.Errorf("Len() = %d, want 3", h.Len())
	}

	lastUser := h.LastUserMessage()
	if lastUser == nil {
		t.Fatalf("LastUserMessage() should not be nil")
	}
	if lastUser.Content != "How are you?" {
		t.Errorf("LastUserMessage().Content = %q, want %q", lastUser.Content, "How are you?")
	}
}

func TestChatHistory_AddAssistant(t *testing.T) {
	h := NewChatHistory("")
	h.AddUser("Hello")
	h.AddAssistant("Hi there!")

	if h.Len() != 2 {
		t.Errorf("Len() = %d, want 2", h.Len())
	}

	lastAssistant := h.LastAssistantMessage()
	if lastAssistant == nil {
		t.Fatalf("LastAssistantMessage() should not be nil")
	}
	if lastAssistant.Content != "Hi there!" {
		t.Errorf("LastAssistantMessage().Content = %q, want %q", lastAssistant.Content, "Hi there!")
	}
}

func TestChatHistory_UpdateLastAssistant(t *testing.T) {
	t.Run("update existing", func(t *testing.T) {
		h := NewChatHistory("")
		h.AddUser("Hello")
		h.AddAssistant("Hi")

		ok := h.UpdateLastAssistant("Hi there!")
		if !ok {
			t.Errorf("UpdateLastAssistant() = false, want true")
		}

		lastAssistant := h.LastAssistantMessage()
		if lastAssistant.Content != "Hi there!" {
			t.Errorf("Content = %q, want %q", lastAssistant.Content, "Hi there!")
		}
	})

	t.Run("no assistant message", func(t *testing.T) {
		h := NewChatHistory("")
		h.AddUser("Hello")

		ok := h.UpdateLastAssistant("Hi")
		if ok {
			t.Errorf("UpdateLastAssistant() = true, want false")
		}
	})
}

func TestChatHistory_GetMessages(t *testing.T) {
	h := NewChatHistory("system")
	h.AddUser("Hello")
	h.AddAssistant("Hi")

	messages := h.GetMessages()
	if len(messages) != 3 {
		t.Errorf("len(messages) = %d, want 3", len(messages))
	}

	// Проверяем что возвращается копия
	messages[0].Content = "modified"
	original := h.GetMessages()
	if original[0].Content == "modified" {
		t.Errorf("GetMessages() should return a copy")
	}
}

func TestChatHistory_GetDisplayMessages(t *testing.T) {
	h := NewChatHistory("system prompt")
	h.AddUser("Hello")
	h.AddAssistant("Hi")

	display := h.GetDisplayMessages()
	if len(display) != 2 {
		t.Errorf("len(display) = %d, want 2", len(display))
	}

	// Проверяем что системное сообщение исключено
	for _, msg := range display {
		if msg.Role == RoleSystem {
			t.Errorf("GetDisplayMessages() should not include system messages")
		}
	}
}

func TestChatHistory_Clear(t *testing.T) {
	h := NewChatHistory("original system")
	h.AddUser("Hello")
	h.AddAssistant("Hi")

	h.Clear("new system")

	if h.Len() != 1 {
		t.Errorf("Len() = %d, want 1", h.Len())
	}
	if h.GetSystemPrompt() != "new system" {
		t.Errorf("GetSystemPrompt() = %q, want %q", h.GetSystemPrompt(), "new system")
	}
}

func TestChatHistory_SetSystemPrompt(t *testing.T) {
	t.Run("add system prompt to empty history", func(t *testing.T) {
		h := NewChatHistory("")
		h.SetSystemPrompt("New system")

		if h.Len() != 1 {
			t.Errorf("Len() = %d, want 1", h.Len())
		}
		if h.GetSystemPrompt() != "New system" {
			t.Errorf("GetSystemPrompt() = %q, want %q", h.GetSystemPrompt(), "New system")
		}
	})

	t.Run("update existing system prompt", func(t *testing.T) {
		h := NewChatHistory("Old system")
		h.AddUser("Hello")

		h.SetSystemPrompt("New system")

		if h.GetSystemPrompt() != "New system" {
			t.Errorf("GetSystemPrompt() = %q, want %q", h.GetSystemPrompt(), "New system")
		}
		// Проверяем что первое сообщение - системное
		messages := h.GetMessages()
		if messages[0].Role != RoleSystem {
			t.Errorf("First message should be system")
		}
		if messages[0].Content != "New system" {
			t.Errorf("System content = %q, want %q", messages[0].Content, "New system")
		}
	})
}

func TestChatHistory_RemoveLast(t *testing.T) {
	t.Run("remove user message", func(t *testing.T) {
		h := NewChatHistory("system")
		h.AddUser("Hello")
		h.AddAssistant("Hi")

		ok := h.RemoveLast()
		if !ok {
			t.Errorf("RemoveLast() = false, want true")
		}
		if h.Len() != 2 {
			t.Errorf("Len() = %d, want 2", h.Len())
		}
	})

	t.Run("cannot remove only system", func(t *testing.T) {
		h := NewChatHistory("system")

		ok := h.RemoveLast()
		if ok {
			t.Errorf("RemoveLast() = true, want false")
		}
		if h.Len() != 1 {
			t.Errorf("Len() = %d, want 1", h.Len())
		}
	})

	t.Run("cannot remove empty", func(t *testing.T) {
		h := NewChatHistory("")

		ok := h.RemoveLast()
		if ok {
			t.Errorf("RemoveLast() = true, want false")
		}
	})
}

func TestChatHistory_TokenEstimate(t *testing.T) {
	h := NewChatHistory("")
	h.AddUser("Hello World") // 11 chars ≈ 2-3 tokens + 100 overhead

	estimate := h.TokenEstimate()
	if estimate < 100 {
		t.Errorf("TokenEstimate() = %d, should be at least 100", estimate)
	}
}

func TestChatHistory_Copy(t *testing.T) {
	h := NewChatHistory("system")
	h.AddUser("Hello")
	h.AddAssistant("Hi")

	historyCopy := h.Copy()

	if historyCopy.Len() != h.Len() {
		t.Errorf("Copy Len() = %d, want %d", historyCopy.Len(), h.Len())
	}
	if historyCopy.GetSystemPrompt() != h.GetSystemPrompt() {
		t.Errorf("Copy GetSystemPrompt() = %q, want %q", historyCopy.GetSystemPrompt(), h.GetSystemPrompt())
	}

	// Проверяем что это независимая копия
	historyCopy.AddUser("Modified")
	if h.Len() == historyCopy.Len() {
		t.Errorf("Original should not be modified")
	}
}

func TestChatHistory_ConcurrentAccess(t *testing.T) {
	h := NewChatHistory("system")

	done := make(chan bool)

	// Запускаем несколько горутин для записи
	for i := 0; i < 10; i++ {
		go func() {
			h.AddUser("message")
			h.AddAssistant("response")
			h.GetMessages()
			h.GetDisplayMessages()
			done <- true
		}()
	}

	// Ждём завершения
	for i := 0; i < 10; i++ {
		<-done
	}

	// Проверяем что нет паник и данные корректны
	if h.Len() < 1 {
		t.Errorf("Concurrent access failed")
	}
}
