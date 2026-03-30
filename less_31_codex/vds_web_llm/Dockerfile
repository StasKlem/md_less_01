FROM golang:1.22-alpine AS build
WORKDIR /src

COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal

RUN go build -o /out/vds-web-llm ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/vds-web-llm /app/vds-web-llm

EXPOSE 8080
ENTRYPOINT ["/app/vds-web-llm"]

