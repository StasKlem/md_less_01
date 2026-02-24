# Makefile для Telegram бота КБЖУ
# Использование: make <target>

# Переменные
BINARY_NAME=kbju-bot
BINARY_PATH=bin/$(BINARY_NAME)
MAIN_PATH=./cmd/bot
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME=$(shell date -u '+%Y-%m-%d_%H:%M:%S')

# Go параметры
GO=go
GOFLAGS=-v
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION) -X main.buildTime=$(BUILD_TIME)"

# Docker параметры
DOCKER_IMAGE=kbju-bot
DOCKER_TAG=latest

.PHONY: all build run test clean lint migrate docker-build docker-run docker-stop help

# Цель по умолчанию
all: lint test build

# Сборка бинарного файла
build:
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p bin
	CGO_ENABLED=1 $(GO) build $(GOFLAGS) $(LDFLAGS) -o $(BINARY_PATH) $(MAIN_PATH)
	@echo "Build completed: $(BINARY_PATH)"

# Запуск приложения
run: build
	@echo "Running $(BINARY_NAME)..."
	@./$(BINARY_PATH)

# Запуск в режиме разработки (с авто-рестартом при изменениях)
run-dev:
	@echo "Running in dev mode..."
	@go run $(LDFLAGS) $(MAIN_PATH)

# Запуск тестов
test:
	@echo "Running tests..."
	$(GO) test $(GOFLAGS) -race -coverprofile=coverage.out ./...
	@echo "Tests completed."

# Запуск тестов с выводом покрытия
test-coverage: test
	@echo "Opening coverage report..."
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

# Очистка
clean:
	@echo "Cleaning..."
	@rm -rf bin/
	@rm -f coverage.out coverage.html
	@rm -f data/*.db data/*.db-shm data/*.db-wal
	@echo "Clean completed."

# Линтинг кода
lint:
	@echo "Running linter..."
	@golangci-lint run ./... || echo "Warning: golangci-lint not installed or found"

# Форматирование кода
fmt:
	@echo "Formatting code..."
	@$(GO) fmt ./...
	@goimports -w . 2>/dev/null || true

# Запуск миграций (создание БД)
migrate:
	@echo "Running database migrations..."
	@mkdir -p data
	@$(GO) run $(MAIN_PATH) || true

# Сборка Docker образа
docker-build:
	@echo "Building Docker image..."
	@docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) --build-arg APP_VERSION=$(VERSION) .
	@echo "Docker image built: $(DOCKER_IMAGE):$(DOCKER_TAG)"

# Запуск в Docker
docker-run:
	@echo "Running Docker container..."
	@docker-compose up -d
	@echo "Container started."

# Остановка Docker контейнера
docker-stop:
	@echo "Stopping Docker container..."
	@docker-compose down
	@echo "Container stopped."

# Пересборка и перезапуск в Docker
docker-restart: docker-stop docker-build docker-run

# Просмотр логов Docker
docker-logs:
	@docker-compose logs -f

# Валидация docker-compose
docker-validate:
	@docker-compose config

# Генерация mock'ов для тестов (требует mockgen)
mocks:
	@echo "Generating mocks..."
	@mockgen -source=internal/repository/repository.go -destination=tests/mocks/repository_mock.go -package=mocks || echo "Warning: mockgen not installed"

# Установка зависимостей
deps:
	@echo "Downloading dependencies..."
	@$(GO) mod download
	@$(GO) mod tidy

# Проверка зависимостей
deps-check:
	@echo "Checking dependencies..."
	@$(GO) mod verify

# Вывод справки
help:
	@echo "KBJU Bot - Makefile Commands"
	@echo ""
	@echo "  make build          - Сборка бинарного файла"
	@echo "  make run            - Сборка и запуск приложения"
	@echo "  make run-dev        - Запуск в режиме разработки"
	@echo "  make test           - Запуск тестов"
	@echo "  make test-coverage  - Запуск тестов с отчетом о покрытии"
	@echo "  make clean          - Очистка артефактов сборки"
	@echo "  make lint           - Запуск линтера"
	@echo "  make fmt            - Форматирование кода"
	@echo "  make migrate        - Запуск миграций БД"
	@echo "  make docker-build   - Сборка Docker образа"
	@echo "  make docker-run     - Запуск Docker контейнера"
	@echo "  make docker-stop    - Остановка Docker контейнера"
	@echo "  make docker-restart - Пересборка и перезапуск"
	@echo "  make docker-logs    - Просмотр логов Docker"
	@echo "  make mocks          - Генерация mock'ов для тестов"
	@echo "  make deps           - Установка зависимостей"
	@echo "  make help           - Эта справка"
