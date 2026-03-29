# Первичная настройка VDS

Это руководство предполагает:
- на VDS установлен Ubuntu 22.04 или 24.04
- у вас есть root-доступ по SSH или пользователь с `sudo`
- сервис должен быть закрытым и не публиковаться в интернет напрямую

## 1. Обновите сервер

```bash
apt update
apt upgrade -y
apt install -y ca-certificates curl git
```

## 2. Установите Docker и Compose

Используем официальные пакеты Docker для Ubuntu:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

source /etc/os-release

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
```

Проверьте установку:

```bash
docker --version
docker compose version
```

## 3. Склонируйте проект

```bash
mkdir -p /srv
cd /srv
git clone <your-repo-url> vds_web_llm
cd /srv/vds_web_llm
```

Если репозиторий уже есть на сервере, обновите его:

```bash
git pull --ff-only
```

## 4. Создайте файл окружения

Скопируйте пример и задайте секреты:

```bash
cp .env.example .env
openssl rand -hex 32
```

Минимально заполните в `.env`:
- `API_KEY`
- `WEBUI_SECRET_KEY`

Дополнительно можно настроить:
- `RATE_LIMIT_PER_MINUTE`
- `MAX_CONTEXT_TOKENS`
- `REQUEST_TIMEOUT_SECONDS`
- `OLLAMA_MODEL`
- `OPEN_WEBUI_PORT`

## 5. Запустите стек

Поднимите контейнеры:

```bash
docker compose up -d --build
```

Проверьте состояние:

```bash
docker compose ps
docker compose logs --tail=50
```

## 6. Скачайте модель

Один раз загрузите модель внутри контейнера Ollama:

```bash
docker exec -it vds-web-llm-ollama ollama pull llama3.2
```

Если хотите другую модель, измените `OLLAMA_MODEL` в `.env` и скачайте нужную модель вместо `llama3.2`.

## 7. Проверьте сервис

Проверка здоровья:

```bash
curl http://127.0.0.1:8080/health
```

Ожидаемый ответ:

```json
{"status":"ok"}
```

Запрос в чат через API-ключ:

```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"hello"}]}'
```

## 8. Откройте веб-интерфейс

В проекте OpenWebUI привязан только к `localhost`.
Чтобы открыть его со своего компьютера, создайте SSH-туннель:

```bash
ssh -L 3000:127.0.0.1:3000 -L 8080:127.0.0.1:8080 root@<vds-host>
```

После этого откройте:

- `http://127.0.0.1:3000` для OpenWebUI
- `http://127.0.0.1:8080` для API

## 9. Как обновлять деплой

Когда код меняется, обновляйте сервер так:

```bash
git pull --ff-only
docker compose up -d --build --remove-orphans
```

Или запустите helper-скрипт со своей машины:

```bash
./deploy.sh root@<vds-host> /srv/vds_web_llm
```

## 10. Частые проблемы

- Если `docker compose` не стартует, сначала проверьте `.env`.
- Если OpenWebUI ещё не готов, подождите завершения первой инициализации и миграций.
- Если API отвечает `401`, убедитесь, что `API_KEY` в запросе совпадает с ключом в `.env`.
- Если Ollama отвечает медленно на первом запросе, проверьте, что модель была успешно загружена.
