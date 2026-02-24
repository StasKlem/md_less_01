.PHONY: build run test lint migrate clean docker-build docker-run docker-stop

BINARY_NAME=kbju-bot
MAIN_PATH=cmd/bot/main.go

build:
	@echo "Building application..."
	CGO_ENABLED=1 GOOS=linux go build -o $(BINARY_NAME) $(MAIN_PATH)

run: build
	@echo "Running application..."
	./$(BINARY_NAME)

test:
	@echo "Running tests..."
	go test -v -cover ./...

lint:
	@echo "Running linter..."
	golangci-lint run ./...

migrate:
	@echo "Running migrations..."
	go run cmd/migrate/main.go

clean:
	@echo "Cleaning up..."
	rm -f $(BINARY_NAME)
	rm -rf ./data/*.db*

docker-build:
	@echo "Building Docker image..."
	docker build -t kbju-bot:latest .

docker-run:
	@echo "Running Docker container..."
	docker-compose up -d

docker-stop:
	@echo "Stopping Docker container..."
	docker-compose down

docker-logs:
	docker-compose logs -f

help:
	@echo "Available commands:"
	@echo "  make build        - Build the application"
	@echo "  make run          - Run the application"
	@echo "  make test         - Run tests"
	@echo "  make lint         - Run linter"
	@echo "  make migrate      - Run database migrations"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make docker-build - Build Docker image"
	@echo "  make docker-run   - Run Docker container"
	@echo "  make docker-stop  - Stop Docker container"
