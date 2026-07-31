FROM node:22-slim

# unzip is required by the bun installer (below).
RUN apt-get update && apt-get install -y git curl unzip procps python3 make g++ cron tini && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --prefer-online && npm cache clean --force

# Bake the openclaw binary into the image. alphaclaw fatally requires it, and
# the transitive install via `npm ci` has proven non-reproducible (binary/curl going
# missing at runtime). Install it explicitly, version-matched to alphaclaw's dep, and
# fail the build loudly if it is not on PATH afterward (lands in /usr/local/bin).
RUN npm install -g openclaw@2026.7.1 && command -v openclaw

# Bake gbrain (the personal-knowledge brain CLI) into the IMAGE, not the volume.
# It installs to /opt/bun (NOT /data) so the runtime volume mount can't mask it.
# gbrain is a bun TS CLI (gbrain -> src/cli.ts) so bun must be on PATH too; symlink
# both into /usr/local/bin (already on PATH). The image is self-contained: a fresh
# instance has gbrain immediately, with no install-at-boot.
ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | bash \
 && /opt/bun/bin/bun install -g github:garrytan/gbrain \
 && ln -sf /opt/bun/bin/bun /usr/local/bin/bun \
 && ln -sf /opt/bun/bin/gbrain /usr/local/bin/gbrain \
 && command -v gbrain && command -v bun

ENV PATH="/app/node_modules/.bin:/opt/bun/bin:$PATH"
ENV ALPHACLAW_ROOT_DIR=/data
# GBrain runtime defaults (per-instance secrets like GBRAIN_DATABASE_URL /
# ZEROENTROPY_API_KEY are supplied as service env vars).
ENV HOME=/data
ENV GBRAIN_HOME=/data
ENV GBRAIN_EMBEDDING_MODEL=zeroentropyai:zembed-1
ENV GBRAIN_EMBEDDING_DIMENSIONS=1280

RUN mkdir -p /data

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["alphaclaw", "start"]
