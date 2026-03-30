package domain

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatInput struct {
	Model       string
	Messages    []Message
	Temperature float64
}

type ChatResult struct {
	Model           string
	Message         Message
	InputTokens     int
	OutputTokens    int
	EstimatedTokens int
}

type ChatResponse struct {
	Answer           string    `json:"answer"`
	Model            string    `json:"model"`
	PromptTokens     int       `json:"prompt_tokens"`
	CompletionTokens int       `json:"completion_tokens"`
	EstimatedTokens  int       `json:"estimated_tokens"`
	Messages         []Message `json:"messages,omitempty"`
}
