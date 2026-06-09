FROM node:22-slim

RUN apt-get update && apt-get install -y git curl procps python3 make g++ cron tini && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --prefer-online && npm cache clean --force

# Bake the openclaw binary into the image. alphaclaw 0.9.18 fatally requires it, and
# the transitive install via `npm ci` has proven non-reproducible (binary/curl going
# missing at runtime). Install it explicitly, version-matched to alphaclaw's dep, and
# fail the build loudly if it is not on PATH afterward (lands in /usr/local/bin).
RUN npm install -g openclaw@2026.5.28 && command -v openclaw

ENV PATH="/app/node_modules/.bin:$PATH"
ENV ALPHACLAW_ROOT_DIR=/data

RUN mkdir -p /data

# Persist GBrain wiring without altering the runtime command: bake a (dangling at
# build time) symlink onto PATH. The gbrain binary lives on the persistent /data
# volume (/data/.bun/bin/gbrain); the volume is mounted at runtime, so this resolves
# then. /usr/local/bin is already on PATH, so `gbrain` works on every fresh container
# with no startup script. (GBRAIN_HOME=/data and embedding vars are set as Railway
# service variables.)
RUN ln -sf /data/.bun/bin/gbrain /usr/local/bin/gbrain

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["alphaclaw", "start"]
