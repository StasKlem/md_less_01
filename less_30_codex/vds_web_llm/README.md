# VPS Ollama Service

Go HTTP gateway for a local Ollama instance with:

- `/health`
- `/chat`
- `/v1/chat/completions`
- bearer/API-key auth
- fixed-window rate limiting
- max-context validation
- OpenWebUI for browser chat

## Run locally

1. Copy `.env.example` to `.env` and set `API_KEY`.
2. Set `WEBUI_SECRET_KEY` to a long random value.
3. Start the stack:

```bash
docker compose up --build
```

4. Pull the model once if it is not already present:

```bash
docker exec -it vds-web-llm-ollama ollama pull llama3.2
```

5. Open the browser UI at:

```text
http://localhost:3000
```

6. Send a request through the API if needed:

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Authorization: Bearer change-me' \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"hello"}]}'
```

## Deploy to VDS over SSH

1. Clone this repo on the VDS into `/srv/vds_web_llm`.
2. Create `.env` on the VDS and set `API_KEY` and `WEBUI_SECRET_KEY`.
3. From your local machine run:

```bash
chmod +x deploy.sh
./deploy.sh user@your-vds-host /srv/vds_web_llm
```

4. Or use `make`:

```bash
make deploy REMOTE=user@your-vds-host
```

What the deploy does:

- SSH into the VDS
- run `git pull --ff-only`
- rebuild the `api` image with `docker compose up -d --build --remove-orphans`
- keep Ollama and OpenWebUI data in volumes

## Notes

- Ollama is internal to the compose network.
- The gateway refuses to start without `API_KEY`.
- The max context check is approximate and intentionally lightweight.
- OpenWebUI stores its data in the `open-webui-data` volume.
