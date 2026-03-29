SHELL := /bin/sh

PROJECT_NAME ?= vds_web_llm
COMPOSE ?= docker compose
REMOTE ?=
REMOTE_DIR ?= /srv/$(PROJECT_NAME)

.PHONY: help up down restart logs pull-model deploy status

help:
	@printf '%s\n' \
		'Targets:' \
		'  make up         - start the full stack locally' \
		'  make down       - stop the full stack' \
		'  make restart    - recreate and start the stack' \
		'  make logs       - tail container logs' \
		'  make pull-model - pull the Ollama model inside the ollama container' \
		'  make deploy     - deploy to REMOTE via SSH (set REMOTE=user@host)' \
		'  make status     - show compose service status'

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) up -d --build --remove-orphans

logs:
	$(COMPOSE) logs -f --tail=100

pull-model:
	$(COMPOSE) exec ollama ollama pull $${OLLAMA_MODEL:-llama3.2}

status:
	$(COMPOSE) ps

deploy:
	@test -n "$(REMOTE)" || (printf '%s\n' 'REMOTE is required, for example: make deploy REMOTE=user@host' && exit 1)
	ssh "$(REMOTE)" 'cd "$(REMOTE_DIR)" && git pull --ff-only && docker compose up -d --build --remove-orphans'

