// Package ui предоставляет TUI компоненты для приложения LLM Chat Client
// на базе фреймворка Bubble Tea.
package ui

import (
	"context"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"llm-client/internal/chat"
	"llm-client/internal/client"
	"llm-client/internal/config"
	"llm-client/internal/logger"
)

// === Константы приложения ===

const (
	// AppName - имя приложения
	AppName = "LLM Chat Client"
	// Version - версия приложения
	Version = "1.0.0"
)

// === Стили UI (lipgloss) ===

var (
	// Стили для контейнеров
	containerStyle = lipgloss.NewStyle().
			Padding(1, 2)

	// Стили для заголовка
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("205")).
			MarginBottom(1)

	// Стили для статуса
	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			Italic(true)

	statusErrorStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("196")).
				Bold(true)

	statusStreamingStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("214")).
				Bold(true)

	// Стили для сообщений
	messageUserStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("39")).
				Bold(true).
				MarginTop(1)

	messageAssistantStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("252")).
				MarginTop(1)

	// Стили для поля ввода
	inputStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62")).
			Padding(0, 1).
			MarginTop(1)

	inputFocusedStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(lipgloss.Color("81")).
				Padding(0, 1).
				MarginTop(1)

	// Стили для подсказок
	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			MarginTop(1)

	// Стили для скролл-области
	historyStyle = lipgloss.NewStyle().
			Margin(0, 0, 1, 0)
)

// === Статусы приложения ===

// AppStatus определяет текущий статус приложения
type AppStatus int

const (
	// StatusIdle - ожидание ввода
	StatusIdle AppStatus = iota
	// StatusSending - отправка запроса
	StatusSending
	// StatusStreaming - получение ответа
	StatusStreaming
	// StatusError - ошибка
	StatusError
)

// String возвращает строковое представление статуса
func (s AppStatus) String() string {
	switch s {
	case StatusIdle:
		return "Ожидание"
	case StatusSending:
		return "Отправка..."
	case StatusStreaming:
		return "Печатает..."
	case StatusError:
		return "Ошибка"
	default:
		return "Неизвестно"
	}
}

// === Сообщения для Bubble Tea ===

// StreamMsg представляет полученный чанк от LLM
type StreamMsg struct {
	Content string
	Done    bool
	Err     error
}

// ErrorMsg представляет ошибку приложения
type ErrorMsg struct {
	Err error
}

// === Модель приложения ===

// Model представляет состояние TUI приложения
type Model struct {
	// Конфигурация
	appConfig *config.Config
	runtime   *config.RuntimeConfig
	client    *client.Client
	logger    *logger.Logger

	// История диалога
	history *chat.ChatHistory

	// Ввод пользователя
	input      string
	inputWidth int

	// Состояние UI
	status       AppStatus
	errorMsg     string
	streamingBuf strings.Builder

	// Скроллинг истории
	scrollOffset int
	maxHeight    int

	// Контекст для отмены запроса
	ctx    context.Context
	cancel context.CancelFunc

	// Канал для получения стрима
	streamChan <-chan client.StreamChunk
}

// ModelOption - функция опция для настройки модели
type ModelOption func(*Model)

// WithLogger устанавливает логгер для модели
func WithLogger(log *logger.Logger) ModelOption {
	return func(m *Model) {
		m.logger = log
	}
}

// NewModel создаёт новую модель приложения
func NewModel(appConfig *config.Config, opts ...ModelOption) *Model {
	ctx, cancel := context.WithCancel(context.Background())
	runtimeConfig := config.NewRuntimeConfig(appConfig)

	log := logger.DefaultLogger

	model := &Model{
		appConfig:    appConfig,
		runtime:      runtimeConfig,
		client:       client.NewClient(appConfig.Server.Address, appConfig.Server.APIEndpoint, client.WithLogger(log)),
		history:      chat.NewChatHistory(runtimeConfig.SystemPrompt),
		input:        "",
		inputWidth:   80,
		maxHeight:    20,
		status:       StatusIdle,
		scrollOffset: 0,
		ctx:          ctx,
		cancel:       cancel,
		logger:       log,
	}

	// Применяем опции
	for _, opt := range opts {
		opt(model)
	}

	model.logger.Debug("Model created", "config", runtimeConfig.String())

	return model
}

// Init инициализирует модель (требуется для bubbletea.Model)
func (m *Model) Init() tea.Cmd {
	m.logger.Debug("Model initialized")
	return nil
}

// Update обрабатывает сообщения и обновляет состояние
func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	m.logger.Debug("Update received", "msg_type", fmt.Sprintf("%T", msg))

	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.handleKeyPress(msg)

	case tea.WindowSizeMsg:
		return m.handleWindowSize(msg)

	case StreamMsg:
		return m.handleStreamMsg(msg)

	case ErrorMsg:
		return m.handleErrorMsg(msg)

	default:
		return m, nil
	}
}

// handleKeyPress обрабатывает нажатия клавиш
func (m *Model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	m.logger.Debug("Key pressed", "key", msg.String())

	switch msg.String() {
	case "ctrl+c", "ctrl+d":
		// Прерывание генерации или выход
		if m.status == StatusStreaming {
			m.logger.Info("Cancelling stream generation")
			m.cancel()
			m.status = StatusIdle
			m.streamingBuf.Reset()
			return m, nil
		}
		m.logger.Info("User requested exit")
		return m, tea.Quit

	case "enter":
		if m.input == "" {
			return m, nil
		}

		// Проверяем команды
		if strings.HasPrefix(m.input, "/") {
			m.logger.Debug("Processing command", "command", m.input)
			return m.handleCommand(m.input)
		}

		// Отправляем сообщение
		m.logger.Debug("Sending message", "input", m.input)
		return m.sendMessage()

	case "up":
		// Скролл вверх
		if m.scrollOffset > 0 {
			m.scrollOffset--
		}
		return m, nil

	case "down":
		// Скролл вниз
		maxScroll := m.getMaxScroll()
		if m.scrollOffset < maxScroll {
			m.scrollOffset++
		}
		return m, nil

	case "pgup":
		// Страница вверх
		m.scrollOffset -= 10
		if m.scrollOffset < 0 {
			m.scrollOffset = 0
		}
		return m, nil

	case "pgdown":
		// Страница вниз
		m.scrollOffset += 10
		maxScroll := m.getMaxScroll()
		if m.scrollOffset > maxScroll {
			m.scrollOffset = maxScroll
		}
		return m, nil

	default:
		// Ввод текста
		if m.status != StatusStreaming {
			m.input, _ = updateInput(m.input, msg)
		}
		return m, nil
	}
}

// handleWindowSize обрабатывает изменение размера окна
func (m *Model) handleWindowSize(msg tea.WindowSizeMsg) (tea.Model, tea.Cmd) {
	m.inputWidth = msg.Width - 4
	m.maxHeight = msg.Height - 10
	if m.maxHeight < 5 {
		m.maxHeight = 5
	}
	m.logger.Debug("Window size updated", "width", msg.Width, "height", msg.Height)
	return m, nil
}

// handleStreamMsg обрабатывает полученный чанк от LLM
func (m *Model) handleStreamMsg(msg StreamMsg) (tea.Model, tea.Cmd) {
	if msg.Err != nil {
		m.logger.Error("Stream message error", "error", msg.Err)
		m.status = StatusError
		m.errorMsg = msg.Err.Error()
		return m, nil
	}

	if msg.Done {
		// Генерация завершена
		m.logger.Info("Stream generation completed", "response_length", m.streamingBuf.Len())
		m.status = StatusIdle
		// Сохраняем полный ответ в историю
		m.history.AddAssistant(m.streamingBuf.String())
		m.streamingBuf.Reset()
		// Скроллим вниз чтобы показать конец ответа
		m.scrollOffset = m.getMaxScroll()
		return m, nil
	}

	// Добавляем полученный текст к буферу
	m.streamingBuf.WriteString(msg.Content)
	// Обновляем последнее сообщение в истории (для контекста)
	m.history.UpdateLastAssistant(m.streamingBuf.String())
	// Скроллим вниз
	m.scrollOffset = m.getMaxScroll()

	// Запрашиваем следующий чанк
	return m, readStreamChunk(m.streamChan)
}

// handleErrorMsg обрабатывает ошибку
func (m *Model) handleErrorMsg(msg ErrorMsg) (tea.Model, tea.Cmd) {
	m.logger.Error("Application error", "error", msg.Err)
	m.status = StatusError
	m.errorMsg = msg.Err.Error()
	return m, nil
}

// handleCommand обрабатывает команды начинающиеся с /
func (m *Model) handleCommand(cmd string) (tea.Model, tea.Cmd) {
	parts := strings.Fields(cmd)
	if len(parts) == 0 {
		return m, nil
	}

	command := strings.TrimPrefix(parts[0], "/")
	m.logger.Info("Executing command", "command", command, "args", parts[1:])

	switch command {
	case "set":
		if len(parts) < 3 {
			m.errorMsg = "Использование: /set <param> <value>"
			m.status = StatusError
			m.logger.Error("Command /set failed", "reason", "not enough arguments")
			return m, nil
		}
		param := parts[1]
		value := parts[2]
		if err := m.runtime.SetParam(param, value); err != nil {
			m.errorMsg = fmt.Sprintf("Ошибка: %v", err)
			m.status = StatusError
		} else {
			m.errorMsg = fmt.Sprintf("Установлено: %s = %s", param, value)
			m.status = StatusIdle
			// Применяем изменения к истории
			if param == "system" || param == "system_prompt" {
				m.history.SetSystemPrompt(value)
			}
		}

	case "clear", "cls":
		m.logger.Info("Clearing chat history")
		m.history.Clear(m.runtime.SystemPrompt)
		m.scrollOffset = 0
		m.errorMsg = "История очищена"
		m.status = StatusIdle

	case "help", "h":
		m.errorMsg = "Команды: /set <param> <value>, /clear, /help, /config, /save, /stream"
		m.status = StatusIdle

	case "config", "cfg":
		m.errorMsg = m.runtime.String()
		m.status = StatusIdle

	case "save":
		// Сохраняем текущие настройки в файл
		path := "config.json"
		m.runtime.ApplyToConfig(m.appConfig)
		if err := m.appConfig.Save(path); err != nil {
			m.errorMsg = fmt.Sprintf("Ошибка сохранения: %v", err)
			m.status = StatusError
		} else {
			m.errorMsg = fmt.Sprintf("Конфигурация сохранена в %s", path)
			m.status = StatusIdle
		}

	case "stream":
		// Переключаем режим стриминга
		m.runtime.Stream = !m.runtime.Stream
		if m.runtime.Stream {
			m.errorMsg = "Stream режим включён"
		} else {
			m.errorMsg = "Stream режим выключен (batch mode)"
		}
		m.status = StatusIdle
		m.logger.Info("Stream mode toggled", "enabled", m.runtime.Stream)

	case "quit", "exit":
		m.logger.Info("User requested exit via command")
		return m, tea.Quit

	default:
		m.errorMsg = fmt.Sprintf("Неизвестная команда: %s (введите /help)", command)
		m.status = StatusError
		m.logger.Error("Unknown command", "command", command)
	}

	m.input = ""
	return m, nil
}

// sendMessage отправляет сообщение пользователя к LLM
func (m *Model) sendMessage() (tea.Model, tea.Cmd) {
	userInput := m.input
	m.logger.Info("Sending user message", "input", userInput, "length", len(userInput))

	// Добавляем сообщение в историю
	m.history.AddUser(userInput)
	m.input = ""
	m.status = StatusSending
	m.errorMsg = ""
	m.scrollOffset = m.getMaxScroll()

	// Создаём запрос
	req := &client.ChatRequest{
		Model:       m.runtime.Model,
		Messages:    m.history.GetMessages(),
		Stream:      m.runtime.Stream,
		Temperature: m.runtime.Temperature,
		TopP:        m.runtime.TopP,
	}
	m.logger.Debug("Built chat request",
		"model", req.Model,
		"messages", len(req.Messages),
		"temp", req.Temperature,
		"stream", req.Stream,
	)

	// Возвращаем команду для стриминга
	return m, m.startStreaming(req)
}

// startStreaming запускает потоковое получение ответа
func (m *Model) startStreaming(req *client.ChatRequest) tea.Cmd {
	m.logger.Info("Starting stream request")

	// Создаём новый контекст для этого запроса
	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	// Сохраняем канал стрима в модели
	m.streamChan = m.client.ChatStream(ctx, req)
	m.status = StatusStreaming

	// Возвращаем команду для чтения первого чанка
	return readStreamChunk(m.streamChan)
}

// readStreamChunk создаёт команду для чтения одного чанка из стрима
func readStreamChunk(stream <-chan client.StreamChunk) tea.Cmd {
	return func() tea.Msg {
		chunk, ok := <-stream
		if !ok {
			return StreamMsg{Done: true}
		}
		return StreamMsg{
			Content: chunk.Content,
			Done:    chunk.Done,
			Err:     chunk.Error,
		}
	}
}

// getMaxScroll возвращает максимальное значение скролла
func (m *Model) getMaxScroll() int {
	messages := m.history.GetDisplayMessages()
	if len(messages) == 0 {
		return 0
	}

	totalLines := 0
	for _, msg := range messages {
		// +1 для заголовка сообщения
		lines := strings.Count(msg.Content, "\n") + 1 + 1
		totalLines += lines
	}

	// Добавляем текущий стриминг буфер
	if m.streamingBuf.Len() > 0 {
		totalLines += strings.Count(m.streamingBuf.String(), "\n") + 2
	}

	maxScroll := totalLines - m.maxHeight
	if maxScroll < 0 {
		return 0
	}
	return maxScroll
}

// View рендерит UI
func (m *Model) View() string {
	var b strings.Builder

	m.logger.Debug("View rendering", "status", m.status, "input_len", len(m.input))

	// Заголовок
	b.WriteString(titleStyle.Render(AppName))
	b.WriteString("\n")

	// Строка статуса
	b.WriteString(m.renderStatus())
	b.WriteString("\n\n")

	// История сообщений
	b.WriteString(m.renderHistory())

	// Поле ввода
	b.WriteString(m.renderInput())

	// Подсказки
	b.WriteString("\n")
	b.WriteString(helpStyle.Render("↑↓: скролл | Enter: отправить | /help: команды | Ctrl+C: выход"))

	result := b.String()
	m.logger.Debug("View rendered", "bytes", len(result))
	return result
}

// renderStatus рендерит строку статуса
func (m *Model) renderStatus() string {
	switch m.status {
	case StatusError:
		return statusErrorStyle.Render(fmt.Sprintf("✗ %s: %s", m.status, m.errorMsg))
	case StatusStreaming:
		return statusStreamingStyle.Render(fmt.Sprintf("● %s", m.status))
	default:
		return statusStyle.Render(fmt.Sprintf("○ %s | %s", m.status, m.runtime.String()))
	}
}

// renderHistory рендерит историю сообщений
func (m *Model) renderHistory() string {
	var b strings.Builder

	messages := m.history.GetDisplayMessages()

	if len(messages) == 0 {
		b.WriteString(lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			Italic(true).
			Render("Начните диалог, напишите сообщение и нажмите Enter"))
		b.WriteString("\n")
	} else {
		// Рендерим сообщения с учётом скролла
		lines := m.renderMessagesToLines(messages)

		// Применяем скролл
		start := m.scrollOffset
		end := start + m.maxHeight
		if end > len(lines) {
			end = len(lines)
		}
		if start > end {
			start = end
		}

		for i := start; i < end; i++ {
			b.WriteString(lines[i])
			b.WriteString("\n")
		}

		// Индикатор скролла
		if m.scrollOffset > 0 {
			b.WriteString(lipgloss.NewStyle().
				Foreground(lipgloss.Color("241")).
				Render("... ▲"))
			b.WriteString("\n")
		}
		if end < len(lines) {
			b.WriteString(lipgloss.NewStyle().
				Foreground(lipgloss.Color("241")).
				Render("... ▼"))
			b.WriteString("\n")
		}
	}

	return historyStyle.Render(b.String())
}

// renderMessagesToLines конвертирует сообщения в строки для рендеринга
func (m *Model) renderMessagesToLines(messages []chat.Message) []string {
	var lines []string

	for _, msg := range messages {
		switch msg.Role {
		case chat.RoleUser:
			lines = append(lines, m.renderUserMessage(msg.Content)...)
		case chat.RoleAssistant:
			lines = append(lines, m.renderAssistantMessage(msg.Content)...)
		}
	}

	// Добавляем текущий стриминг буфер если есть
	if m.streamingBuf.Len() > 0 {
		lines = append(lines, m.renderAssistantMessage(m.streamingBuf.String())...)
	}

	return lines
}

// renderUserMessage форматирует сообщение пользователя
func (m *Model) renderUserMessage(content string) []string {
	contentWidth := m.getContentWidth()
	return m.formatMessage(content, "▸ Вы: ", messageUserStyle, contentWidth)
}

// renderAssistantMessage форматирует сообщение от ассистента
func (m *Model) renderAssistantMessage(content string) []string {
	contentWidth := m.getContentWidth()
	return m.formatMessage(content, "▸ AI: ", messageAssistantStyle, contentWidth)
}

// formatMessage форматирует текст сообщения с префиксом и переносом строк
func (m *Model) formatMessage(content, prefix string, style lipgloss.Style, contentWidth int) []string {
	var lines []string

	// Разбиваем контент на абзацы по \n
	paragraphs := strings.Split(content, "\n")
	firstLine := true

	for _, para := range paragraphs {
		// Разбиваем абзац на строки по ширине
		wrappedLines := wrapText(para, contentWidth)

		for i, line := range wrappedLines {
			if firstLine && i == 0 {
				// Первая строка сообщения с префиксом
				lines = append(lines, style.Render(prefix+line))
			} else {
				// Все остальные строки только с отступом
				lines = append(lines, style.Render("  "+line))
			}
		}

		// После первой строки префикс больше не нужен
		firstLine = false

		// Если абзац был пустым (был \n), добавляем пустую строку
		if len(wrappedLines) == 0 {
			lines = append(lines, "")
		}
	}

	return lines
}

// getContentWidth возвращает доступную ширину для контента
func (m *Model) getContentWidth() int {
	width := m.inputWidth - 6 // Учитываем отступы и префиксы
	if width < 20 {
		width = 20
	}
	return width
}

// wrapText разбивает текст на строки по максимальной ширине
func wrapText(text string, maxWidth int) []string {
	if maxWidth <= 0 {
		return []string{text}
	}

	var lines []string
	currentLine := ""

	// Разбиваем текст на слова
	words := strings.Fields(text)
	for _, word := range words {
		// Если слово слишком длинное, разбиваем его
		if len(word) > maxWidth {
			// Сначала добавляем текущую строку если она не пустая
			if currentLine != "" {
				lines = append(lines, currentLine)
				currentLine = ""
			}
			// Разбиваем длинное слово на части
			for len(word) > maxWidth {
				lines = append(lines, word[:maxWidth])
				word = word[maxWidth:]
			}
			if word != "" {
				currentLine = word
			}
			continue
		}

		// Проверяем влезет ли слово в текущую строку
		testLine := currentLine
		if testLine == "" {
			testLine = word
		} else {
			testLine = currentLine + " " + word
		}

		if len(testLine) <= maxWidth {
			currentLine = testLine
		} else {
			// Слово не влезает, добавляем текущую строку и начинаем новую
			if currentLine != "" {
				lines = append(lines, currentLine)
			}
			currentLine = word
		}
	}

	// Добавляем последнюю строку
	if currentLine != "" {
		lines = append(lines, currentLine)
	}

	return lines
}

// renderInput рендерит поле ввода
func (m *Model) renderInput() string {
	style := inputStyle
	if m.status == StatusStreaming {
		style = style.Foreground(lipgloss.Color("241"))
	}

	prompt := "> "
	if m.status == StatusStreaming {
		prompt = "│ "
	}

	return style.Render(prompt + m.input + cursor())
}

// cursor возвращает символ курсора
func cursor() string {
	return "█"
}

// updateInput обновляет строку ввода при нажатии клавиш
func updateInput(input string, msg tea.KeyMsg) (string, tea.Cmd) {
	switch msg.Type {
	case tea.KeyRunes:
		return input + string(msg.Runes), nil
	case tea.KeySpace:
		return input + " ", nil
	case tea.KeyBackspace:
		if len(input) > 0 {
			return input[:len(input)-1], nil
		}
	case tea.KeyDelete:
		// Простая реализация - ничего не делаем
		return input, nil
	}
	return input, nil
}

// GetHistory возвращает историю диалога
func (m *Model) GetHistory() *chat.ChatHistory {
	return m.history
}

// GetRuntimeConfig возвращает текущую конфигурацию
func (m *Model) GetRuntimeConfig() *config.RuntimeConfig {
	return m.runtime
}

// GetStatus возвращает текущий статус
func (m *Model) GetStatus() AppStatus {
	return m.status
}
