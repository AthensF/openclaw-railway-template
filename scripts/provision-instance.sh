#!/usr/bin/env bash
# One-time per-instance provisioning for an openclaw + gbrain instance.
# The image already bakes openclaw + gbrain + bun. This sets up the per-instance
# state that lives on the /data volume / the instance's own brain DB.
#
# Run ONCE after first deploy, from your machine:
#   railway ssh --service <svc> --environment <env> --project <proj> \
#     "bash -s" < scripts/provision-instance.sh
# or paste it into a `railway ssh` shell. It is idempotent — safe to re-run.
#
# Required env (set as Railway service variables before running):
#   GBRAIN_DATABASE_URL, GBRAIN_DIRECT_DATABASE_URL, ZEROENTROPY_API_KEY,
#   OLLAMA_CLOUD_API_KEY   (ANTHROPIC_API_KEY optional, for the anthropic models)
# Baked into the image as defaults: HOME, GBRAIN_HOME, GBRAIN_EMBEDDING_MODEL,
#   GBRAIN_EMBEDDING_DIMENSIONS.
set -uo pipefail

echo "==> 1/4 brain: init if this instance's DB has no schema yet"
if gbrain doctor --fast >/dev/null 2>&1; then
  echo "    brain already initialized"
else
  gbrain init --non-interactive --url "$GBRAIN_DATABASE_URL"
fi

echo "==> 2/4 openclaw: register Ollama Cloud provider (key via env-ref) + default model"
cat > /tmp/ollama-provider.json <<'JSON'
{
  "models": {
    "providers": {
      "ollama-cloud": {
        "api": "ollama",
        "baseUrl": "https://ollama.com",
        "apiKey": { "source": "env", "provider": "ollama-cloud", "id": "OLLAMA_CLOUD_API_KEY" },
        "models": [ { "id": "gemma4:31b-cloud", "name": "gemma4:31b-cloud" } ]
      }
    }
  }
}
JSON
openclaw config patch --file /tmp/ollama-provider.json
rm -f /tmp/ollama-provider.json
openclaw plugins install @openclaw/ollama-provider >/dev/null 2>&1 || true
openclaw plugins enable  @openclaw/ollama-provider  >/dev/null 2>&1 || true
openclaw models set ollama-cloud/gemma4:31b-cloud

echo "==> 3/4 agent: install gbrain skillpack (from the baked gbrain package)"
G="$(dirname "$(readlink -f "$(command -v gbrain)")")/../install/global/node_modules/gbrain/skills"
[ -d "$G" ] || G=/opt/bun/install/global/node_modules/gbrain/skills
for s in query ingest enrich maintain; do
  openclaw skills install "$G/$s" --force >/dev/null 2>&1 && echo "    installed skill: $s" || echo "    skill $s: skipped"
done

echo "==> 4/4 agent: inject brain-first protocol into workspace AGENTS.md (idempotent)"
A=/data/.openclaw/workspace/AGENTS.md
if [ -f "$A" ] && ! grep -q gbrain-brain-first-protocol "$A"; then
cat >> "$A" <<'MD'

<!-- gbrain-brain-first-protocol -->
## GBrain — Brain-First Lookup (world knowledge)
GBrain is your persistent world-knowledge memory (people, companies, deals, meetings,
concepts). The `gbrain` CLI is on PATH. For ANY entity/knowledge question, query the
brain BEFORE answering from memory or grep:
1. `gbrain search "name"`  2. `gbrain query "what do we know about X"`  3. `gbrain get <slug>`
After writing a brain page: `gbrain sync --no-pull --no-embed`.
<!-- /gbrain-brain-first-protocol -->
MD
  echo "    AGENTS.md injected"
else
  echo "    AGENTS.md already has protocol (or missing workspace)"
fi

echo "==> verify"
gbrain doctor --json 2>/dev/null | grep -oE '"(connection|pgvector|schema_version|embedding_provider)":[^,]*' | head
openclaw models status 2>/dev/null | grep -i default
echo "DONE"
