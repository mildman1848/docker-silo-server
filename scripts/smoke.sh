#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-silo-smoke}"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/mildman1848/silo-server}"
IMAGE_TAG="${IMAGE_TAG:-git-881c968-mldm1}"
SMOKE_DIR="${SMOKE_DIR:-.tmp/smoke}"
PORT="${SMOKE_PORT:-18090}"
DOCKER_BIN="${DOCKER:-docker}"

if [ "${1:-}" = "clean" ]; then
    ${DOCKER_BIN} compose -p "${PROJECT_NAME}" -f "${SMOKE_DIR}/compose.yml" down -v --remove-orphans 2>/dev/null || true
    rm -rf "${SMOKE_DIR}" 2>/dev/null || {
        if command -v sudo >/dev/null 2>&1; then
            sudo rm -rf "${SMOKE_DIR}"
        else
            echo "failed to remove ${SMOKE_DIR}; remove it manually with elevated privileges" >&2
            exit 1
        fi
    }
    exit 0
fi

mkdir -p "${SMOKE_DIR}/media" "${SMOKE_DIR}/config" "${SMOKE_DIR}/transcode" "${SMOKE_DIR}/secrets"
printf 'smoke media placeholder\n' > "${SMOKE_DIR}/media/README.txt"

python3 - <<'PY'
import pathlib, secrets, string, os
alphabet = string.ascii_letters + string.digits
for name, length in [('silo_secret_key', 96), ('postgres_password', 48)]:
    p = pathlib.Path('.tmp/smoke/secrets') / name
    if not p.exists():
        p.write_text(''.join(secrets.choice(alphabet) for _ in range(length)), encoding='utf-8')
        os.chmod(p, 0o600)
PY

cat > "${SMOKE_DIR}/compose.yml" <<YAML
services:
  postgres:
    image: pgvector/pgvector:pg18
    environment:
      POSTGRES_USER: silo
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      POSTGRES_DB: silo
    secrets:
      - postgres_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U silo"]
      interval: 5s
      timeout: 3s
      retries: 20
  redis:
    image: redis:alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 20
  silo:
    image: ${IMAGE_NAME}:${IMAGE_TAG}
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Europe/Berlin
      MODE: integrated
      FILE__SECRET_KEY: /run/secrets/silo_secret_key
      FILE__POSTGRES_PASSWORD: /run/secrets/postgres_password
      SILO_DB_HOST: postgres
      SILO_DB_PORT: "5432"
      SILO_DB_NAME: silo
      SILO_DB_USER: silo
      SILO_DB_SSLMODE: disable
      REDIS_URL: redis://redis:6379
      SILO_PLUGIN_CACHE_DIR: /config/plugins
      POSTGRES_TUNE: off
    ports:
      - "127.0.0.1:${PORT}:8080"
    volumes:
      - ./config:/config
      - ./transcode:/transcode
      - ./media:/media:ro
    secrets:
      - silo_secret_key
      - postgres_password
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
secrets:
  silo_secret_key:
    file: ./secrets/silo_secret_key
  postgres_password:
    file: ./secrets/postgres_password
YAML

${DOCKER_BIN} compose -p "${PROJECT_NAME}" -f "${SMOKE_DIR}/compose.yml" up -d

for _ in {1..80}; do
    if curl -fsS "http://127.0.0.1:${PORT}/api/v1/health" >/tmp/silo-smoke-health.json; then
        echo "health endpoint responded"
        cat /tmp/silo-smoke-health.json
        echo
        ${DOCKER_BIN} compose -p "${PROJECT_NAME}" -f "${SMOKE_DIR}/compose.yml" ps
        exit 0
    fi
    sleep 3
done

echo "Silo did not become healthy in time" >&2
${DOCKER_BIN} compose -p "${PROJECT_NAME}" -f "${SMOKE_DIR}/compose.yml" logs --no-color --tail=200 >&2
exit 1
