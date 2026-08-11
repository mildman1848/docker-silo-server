# Unofficial Docker image for Silo Server

LinuxServer.io-style Docker packaging for [Silo Server](https://github.com/Silo-Server/silo-server) using s6-overlay.

> **Status:** experimental, pre-1.0 upstream, commit-pinned. Humans have invented several ways to make media servers complicated; this repository tries not to add another one unnecessarily.

## Upstream status

At the time this packaging was created:

- Official website: <https://siloserver.org/> reports **pre-1.0**.
- GitHub releases: none.
- Git tags: none.
- Upstream commit pinned here: `881c96864bafec423f91438059b21b84a6f68686`.
- Upstream license: `AGPL-3.0-or-later`.

Because upstream has no versioned releases yet, image versions use this format:

```text
git-<upstream-short-sha>-mldm<N>
```

Current packaging version:

```text
git-881c968-mldm1
```

## Important license and trademark notes

Silo Server is licensed under the **GNU Affero General Public License v3.0 or later** (`AGPL-3.0-or-later`). This repository's packaging files are MIT-licensed, but built images include Silo Server and must comply with the upstream AGPL terms.

This project is **unofficial** and is not affiliated with Silo Media L.L.C. or the Silo Server project. The Silo name is used only to identify the upstream project. Do not use upstream logos, icons, wordmarks, or confusingly official branding for modified distributions.

## Image design

- Runtime base: `ghcr.io/linuxserver/baseimage-debian:bookworm`
- Default PostgreSQL image: `ghcr.io/mildman1848/postgresql:18.4-mldm4`
- Default Redis-protocol cache image: `ghcr.io/mildman1848/valkey:9.0.4-mldm1`
- s6-overlay v3 supervision
- LinuxServer.io-style `PUID`, `PGID`, `TZ`
- `FILE__` secret-file expansion for Docker secrets
- Upstream source built from a pinned Git commit
- Debian runtime with `jellyfin-ffmpeg7`, `libvips42`, and Noto fonts
- Supports `linux/amd64` and `linux/arm64`

## Ports

| Port | Purpose |
|---:|---|
| `8080` | Silo Web/API |
| `8096` | Jellyfin-compatible API, when enabled |
| `13378` | Audiobookshelf-compatible API, when enabled |

## Volumes

| Host path | Container path | Purpose |
|---|---|---|
| `./config` | `/config` | Persistent Silo app state: plugins, compatibility assets, covers, SQLite userdb if used |
| `./transcode` | `/transcode` | Transient transcode output; mapped internally to `/tmp/silo-transcode` |
| `/path/to/media` | `/media` | Read-only media library |

The container prepares these internal paths as symlinks into `/config`:

```text
/var/lib/silo/plugins          -> /config/plugins
/var/lib/silo/compat           -> /config/compat
/var/lib/silo/audiobook-covers -> /config/audiobook-covers
/var/lib/silo/userdb           -> /config/userdb
/tmp/silo-transcode            -> /transcode
```

## Quick start

```bash
cp .env.example .env
make secrets
# edit MEDIA_ROOT in .env
docker compose up -d
```

The app should be available at:

```text
http://localhost:8090
```

## Required settings

| Variable | Required | Description |
|---|---:|---|
| `POSTGRES_IMAGE` | `ghcr.io/mildman1848/postgresql:18.4-mldm4` | PostgreSQL image for the bundled compose example. |
| `CACHE_IMAGE` | `ghcr.io/mildman1848/valkey:9.0.4-mldm1` | Redis-protocol cache image for the bundled compose example. Service name remains `redis` for app compatibility. |
| `SECRET_KEY` / `FILE__SECRET_KEY` | yes | Master key for at-rest credential encryption. Back this up separately from DB dumps. Losing it makes encrypted secrets unrecoverable. |
| `DATABASE_URL` | yes | PostgreSQL connection string. |
| `REDIS_URL` | recommended | Redis connection string. |
| `MEDIA_ROOT` | compose only | Host path to media library. |

## Database and cache images

The bundled Compose file prefers this homelab image set:

```text
POSTGRES_IMAGE=ghcr.io/mildman1848/postgresql:18.4-mldm4
CACHE_IMAGE=ghcr.io/mildman1848/valkey:9.0.4-mldm1
```

The cache service is still named `redis` and Silo receives `REDIS_URL=redis://redis:6379`, because Valkey is Redis-protocol compatible and many applications use `redis` as the expected DNS name.

Upstream Silo currently documents PostgreSQL 18 + pgvector. This packaging keeps the image selectable through `POSTGRES_IMAGE` so operators can switch back to `pgvector/pgvector:pg18` if upstream introduces a hard PostgreSQL 18 or pgvector requirement that the custom PostgreSQL 18 image cannot satisfy.

## Docker secrets / `FILE__` variables

The image supports LSIO-style secret-file variables:

```yaml
environment:
  FILE__SECRET_KEY: /run/secrets/silo_secret_key
  FILE__POSTGRES_PASSWORD: /run/secrets/postgres_password
```

The helper never logs secret values.

## Hardware acceleration

For Intel/AMD VAAPI/QSV, pass `/dev/dri`:

```yaml
devices:
  - /dev/dri:/dev/dri
```

For NVIDIA/NVENC, use the optional compose override:

```bash
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d
```

## Make targets

| Target | Purpose |
|---|---|
| `make info` | Print image/version metadata |
| `make secrets` | Generate local `.env` and secret files without printing secret values |
| `make lint` | Syntax-check shell scripts and Compose files |
| `make build` | Build local image for the current platform |
| `make smoke` | Start Postgres, Redis, and Silo, then call the health endpoint |
| `make clean-smoke` | Remove smoke-test containers and temporary files |

## Update policy

Best practice once upstream publishes tags:

1. Set `UPSTREAM_REF` to a version tag.
2. Set `APP_VERSION` to that upstream version.
3. Reset `IMAGE_REVISION` to `mldm1`.
4. Run `make lint build smoke`.
5. Publish only after the smoke test passes.

Until then, update by commit SHA only and document the audited upstream commit.
