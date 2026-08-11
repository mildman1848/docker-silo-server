# syntax=docker/dockerfile:1.7

ARG UPSTREAM_REPO=https://github.com/Silo-Server/silo-server.git
ARG UPSTREAM_REF=881c96864bafec423f91438059b21b84a6f68686
ARG LSIO_BASE_VERSION=bookworm
ARG APP_VERSION=git-881c968
ARG IMAGE_REVISION=mldm1
ARG VERSION=git-881c968-mldm1

FROM alpine/git:2.49.1 AS source
ARG UPSTREAM_REPO
ARG UPSTREAM_REF
WORKDIR /src
RUN git clone --filter=blob:none "${UPSTREAM_REPO}" . \
    && git fetch --depth=1 origin "${UPSTREAM_REF}" \
    && git checkout --detach "${UPSTREAM_REF}"

FROM node:22-slim AS frontend
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
WORKDIR /src/web
COPY --from=source /src/web/package.json /src/web/pnpm-lock.yaml ./
COPY --from=source /src/web/vendor/foliate-js ./vendor/foliate-js
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
COPY --from=source /src/web/ ./
RUN pnpm run build

FROM scratch AS frontend_dist
COPY --from=frontend /src/web/dist/. /

FROM golang:1.26 AS build
ARG UPSTREAM_REF
ENV CGO_ENABLED=1 \
    GOPROXY=https://proxy.golang.org,direct \
    GOPRIVATE=github.com/Silo-Server/* \
    GONOSUMDB=github.com/Silo-Server/*
RUN apt-get update \
    && apt-get install -y --no-install-recommends libvips-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY --from=source /src/go.mod /src/go.sum ./
COPY --from=source /src/internal/compat/zishang520-webtransport-go/ internal/compat/zishang520-webtransport-go/
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY --from=source /src/web/embed.go web/embed.go
COPY --from=frontend_dist / web/dist
COPY --from=source /src/cmd/ cmd/
COPY --from=source /src/internal/ internal/
COPY --from=source /src/migrations/ migrations/
COPY --from=source /src/contracts/ contracts/
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build \
      -ldflags "-X github.com/Silo-Server/silo-server/internal/buildinfo.revisionOverride=${UPSTREAM_REF} -X github.com/Silo-Server/silo-server/internal/buildinfo.dirtyOverride=false" \
      -o /silo ./cmd/silo/

FROM ghcr.io/linuxserver/baseimage-debian:${LSIO_BASE_VERSION}
ARG TARGETARCH
ARG LSIO_BASE_VERSION
ARG UPSTREAM_REPO
ARG UPSTREAM_REF
ARG APP_VERSION
ARG IMAGE_REVISION
ARG VERSION

ENV APP_VERSION="${APP_VERSION}" \
    IMAGE_REVISION="${IMAGE_REVISION}" \
    VERSION="${VERSION}" \
    PORT="8080" \
    MODE="integrated" \
    SILO_PLUGIN_CACHE_DIR="/config/plugins"

LABEL maintainer="Mildman1848" \
      org.opencontainers.image.authors="Mildman1848" \
      org.opencontainers.image.vendor="Mildman1848" \
      org.opencontainers.image.title="Unofficial Docker image for Silo Server" \
      org.opencontainers.image.description="LinuxServer.io-style s6-overlay packaging for Silo Server" \
      org.opencontainers.image.source="https://github.com/mildman1848/docker-silo-server" \
      org.opencontainers.image.url="https://github.com/Silo-Server/silo-server" \
      org.opencontainers.image.documentation="https://github.com/mildman1848/docker-silo-server" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${UPSTREAM_REF}" \
      org.opencontainers.image.base.name="ghcr.io/linuxserver/baseimage-debian:${LSIO_BASE_VERSION}" \
      build_version="Mildman1848 unofficial Silo Server image version:- ${VERSION} Upstream:- ${APP_VERSION} Revision:- ${IMAGE_REVISION}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/jellyfin.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/jellyfin.gpg arch=${TARGETARCH}] https://repo.jellyfin.org/debian bookworm main" \
      > /etc/apt/sources.list.d/jellyfin.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends jellyfin-ffmpeg7 git libvips42 fonts-noto-core fonts-noto-cjk; \
    apt-get purge -y gnupg; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

COPY --from=frontend /usr/local/bin/node /usr/local/bin/node
COPY --from=frontend /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
COPY --from=build /silo /usr/local/bin/silo
COPY root/ /

VOLUME ["/config", "/media", "/transcode"]
EXPOSE 8080 8096 13378
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/api/v1/health" || exit 1
ENTRYPOINT ["/init"]
