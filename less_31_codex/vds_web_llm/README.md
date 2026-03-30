# VPS Ollama Service

Go HTTP gateway для локального экземпляра Ollama с:

- `/health`
- `/chat`
- `/v1/chat/completions`
- bearer/API-key auth
- rate limiting по фиксированному окну
- проверкой max context
- OpenWebUI для чата в браузере

## Запуск локально

1. Скопируйте `.env.example` в `.env` и задайте `API_KEY`.
2. Задайте `WEBUI_SECRET_KEY` как длинный случайный ключ.
3. Запустите стек:

```bash
docker compose up --build
```

4. Один раз скачайте модель, если её ещё нет:

```bash
docker exec -it vds-web-llm-ollama ollama pull llama3.2
```

5. Откройте веб-интерфейс:

```text
http://127.0.0.1:3000
```

6. При необходимости отправьте запрос через API:

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Authorization: Bearer change-me' \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"hello"}]}'
```

## Деплой на VDS через SSH

1. Склонируйте этот репозиторий на VDS в `/srv/vds_web_llm`.
2. Создайте `.env` на VDS и задайте `API_KEY` и `WEBUI_SECRET_KEY`.
3. С локальной машины выполните:

```bash
chmod +x deploy.sh
./deploy.sh user@your-vds-host /srv/vds_web_llm
```

4. Либо используйте `make`:

```bash
make deploy REMOTE=user@your-vds-host
```

Что делает deploy:

- подключается к VDS по SSH
- выполняет `git pull --ff-only`
- пересобирает `api` через `docker compose up -d --build --remove-orphans`
- сохраняет данные Ollama и OpenWebUI в volumes

## Доступ к UI и API

В текущей конфигурации сервисы привязаны только к `localhost` на VDS.
Чтобы открыть их со своей машины, создайте SSH-туннель:

```bash
ssh -L 3000:127.0.0.1:3000 -L 8080:127.0.0.1:8080 root@your-vds-host
```

После этого откройте:

- `http://127.0.0.1:3000` для OpenWebUI
- `http://127.0.0.1:8080` для API

## Прямой доступ из интернета

Если нужно открыть сервис наружу, прочитайте [openweb.md](./openweb.md).

## Обновление кода

Инструкция по обновлению проекта на сервере находится в [update.md](./update.md).

## Первичная настройка

Пошаговая инструкция по первичной настройке VDS находится в [startup.md](./startup.md).

## Примечания

- Ollama работает внутри compose-сети и не публикуется наружу.
- Gateway не стартует без `API_KEY`.
- Проверка max context выполнена упрощённо и намеренно лёгкая.
- OpenWebUI хранит данные в volume `open-webui-data`.
