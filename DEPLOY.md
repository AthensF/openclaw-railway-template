# Spin up an openclaw + GBrain instance

This image (`Dockerfile`) bakes **openclaw**, **gbrain**, and **bun** in — so a fresh
container has the tools immediately. Per-instance setup (each instance gets its **own
brain DB**) is a single idempotent provisioning run.

## Environment variables

Per-instance secrets (set these):

| Variable | Notes |
|---|---|
| `GBRAIN_DATABASE_URL` | Postgres+pgvector connection (Supabase **transaction pooler**, port 6543). Use a **new/distinct** DB per instance for an isolated brain. |
| `GBRAIN_DIRECT_DATABASE_URL` | Direct connection string (port 5432) for migrations. |
| `ZEROENTROPY_API_KEY` | Embedding provider (zeroentropyai:zembed-1, 1280-dim). |
| `OLLAMA_CLOUD_API_KEY` | Ollama Cloud key (default model `ollama-cloud/gemma4:31b-cloud`). |
| `ANTHROPIC_API_KEY` | Optional — enables the anthropic models. |

Baked into the image as defaults (override only if needed): `HOME=/data`,
`GBRAIN_HOME=/data`, `GBRAIN_EMBEDDING_MODEL=zeroentropyai:zembed-1`,
`GBRAIN_EMBEDDING_DIMENSIONS=1280`, `ALPHACLAW_ROOT_DIR=/data`.

A `/data` volume must be mounted (openclaw/alphaclaw state). ~5GB is plenty.

## Railway

**One-click (template):** deploy the published Railway template — it creates the
service, a `/data` volume, and prompts for the env vars above.

**Manual:** new service → connect this repo (`AthensF/openclaw-railway-template`) →
add a volume at `/data` → set the env vars → deploy.

## Any provider (Docker)

```bash
docker run -d --name openclaw \
  -p 3000:3000 \
  -v openclaw-data:/data \
  -e GBRAIN_DATABASE_URL=... \
  -e GBRAIN_DIRECT_DATABASE_URL=... \
  -e ZEROENTROPY_API_KEY=... \
  -e OLLAMA_CLOUD_API_KEY=... \
  ghcr.io/athensf/openclaw-railway-template:latest
```

Works the same on Fly, Render, or Kubernetes — provide the env vars and a `/data` volume.

## One-time provisioning (per instance)

After the first deploy is healthy (`/health` → 200), run once to init this instance's
brain + wire the agent (idempotent):

```bash
# Railway:
railway ssh --service <svc> --environment <env> --project <proj> "bash -s" \
  < scripts/provision-instance.sh
# Docker:
docker exec -i openclaw bash -s < scripts/provision-instance.sh
```

It runs `gbrain init` (if the DB is new), registers the Ollama Cloud provider, sets the
default model, installs the gbrain skillpack, and injects the brain-first protocol into
`AGENTS.md`. Verify: `gbrain doctor` is green and the agent answers via `gbrain query`.
