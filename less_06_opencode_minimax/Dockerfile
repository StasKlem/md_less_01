FROM golang:1.21-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=1 GOOS=linux go build -o /kbju-bot ./cmd/bot

FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /kbju-bot .

RUN adduser -D -u 1000 appuser
USER appuser

ENV TZ=UTC

CMD ["./kbju-bot"]
