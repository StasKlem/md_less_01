# Build stage
FROM golang:1.24-alpine AS builder

# Устанавливаем необходимые зависимости
RUN apk add --no-cache git ca-certificates tzdata

# Создаем non-root пользователя для сборки
RUN adduser -D -g '' builduser

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем go.mod и go.sum для кэширования зависимостей
COPY go.mod go.sum ./
RUN go mod download

# Копируем исходный код
COPY . .

# Устанавливаем версию приложения из переменной окружения или используем 'dev'
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

# Собираем бинарный файл с оптимизациями
# -ldflags "-s -w" удаляет символы отладки для уменьшения размера
RUN CGO_ENABLED=1 GOOS=linux go build \
    -ldflags "-s -w -X main.appVersion=${APP_VERSION}" \
    -o /app/bin/kbju-bot \
    ./cmd/bot

# Runtime stage
FROM alpine:3.21

# Устанавливаем часовой пояс и CA сертификаты
RUN apk add --no-cache ca-certificates tzdata sqlite-libs && \
    addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D -h /app appuser

# Создаем директорию для данных
RUN mkdir -p /app/data && chown -R appuser:appgroup /app/data

# Копируем бинарный файл из builder
COPY --from=builder /app/bin/kbju-bot /app/bin/kbju-bot

# Устанавливаем рабочую директорию
WORKDIR /app

# Переключаемся на non-root пользователя
USER appuser

# Выставляем переменные окружения по умолчанию
ENV APP_VERSION=prod \
    DATABASE_PATH=/app/data/kbju.db \
    TZ=Europe/Moscow

# Health check (проверка что процесс запущен)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f kbju-bot || exit 1

# Запускаем приложение
ENTRYPOINT ["/app/bin/kbju-bot"]
