# Как обновлять код на сервере из репозитория

Эта инструкция нужна, если проект уже развернут на VDS и вы хотите обновлять его без ручного редактирования файлов на сервере.

## Базовый сценарий

Если код хранится в git-репозитории на самом VDS, обновление выглядит так:

```bash
cd /srv/vds_web_llm
git pull --ff-only
docker compose up -d --build --remove-orphans
```

Что происходит:
- `git pull --ff-only` забирает только fast-forward изменения без лишних merge-коммитов
- `docker compose up -d --build` пересобирает локальный `api`-контейнер
- `--remove-orphans` убирает старые контейнеры, если состав compose изменился

## Обновление через helper-скрипт

В проекте есть `deploy.sh`. Его удобно запускать с локальной машины:

```bash
chmod +x deploy.sh
./deploy.sh root@<vds-host> /srv/vds_web_llm
```

Скрипт делает то же самое:
- подключается к серверу по SSH
- заходит в каталог проекта
- выполняет `git pull --ff-only`
- запускает `docker compose up -d --build --remove-orphans`

## Обновление через Makefile

Если удобнее использовать `make`, можно запускать:

```bash
make deploy REMOTE=root@<vds-host>
```

Также полезны команды:

```bash
make up
make down
make restart
make logs
make status
```

## Рекомендуемый рабочий процесс

1. Внесите изменения локально.
2. Закоммитьте их в git.
3. Отправьте изменения в удалённый репозиторий.
4. На сервере выполните обновление:

```bash
cd /srv/vds_web_llm
git pull --ff-only
docker compose up -d --build --remove-orphans
```

Если вы используете SSH-деплой, можно запускать:

```bash
./deploy.sh root@<vds-host> /srv/vds_web_llm
```

## После обновления

Проверьте, что сервисы поднялись:

```bash
docker compose ps
docker compose logs --tail=50
```

Проверьте API:

```bash
curl http://127.0.0.1:8080/health
```

Если нужен тест чата:

```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"hello"}]}'
```

## Что обновляется автоматически

- код `api` пересобирается из текущего репозитория
- `Ollama` и `OpenWebUI` остаются с данными в volume
- модель в Ollama не пропадает при обычном `docker compose up -d`

## Что может понадобиться отдельно

- если вы поменяли модель, выполните:

```bash
docker exec -it vds-web-llm-ollama ollama pull llama3.2
```

- если вы изменили `.env`, перезапустите стек:

```bash
docker compose up -d --build
```

## Откат

Если новая версия сломалась, можно:

1. Вернуть предыдущий commit в git.
2. Выполнить снова:

```bash
docker compose up -d --build --remove-orphans
```

Если проблема только в контейнерах, помогает полный рестарт:

```bash
docker compose down
docker compose up -d --build
```
