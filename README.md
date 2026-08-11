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
| `${MEDIA_MOVIES_PATH}` | `/media/movies` | Read-only movies library |
| `${MEDIA_TV_PATH}` | `/media/tv` | Read-only TV/shows library |
| `${MEDIA_MUSIC_PATH}` | `/media/music` | Read-only music library |
| `${MEDIA_AUDIOBOOKS_PATH}` | `/media/audiobooks` | Read-only audiobook library |
| `${MEDIA_EBOOKS_PATH}` | `/media/ebooks` | Read-only ebook library |
| `${MEDIA_MANGA_PATH}` | `/media/manga` | Read-only manga/comics library |

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
# edit MEDIA_*_PATH in .env if your media paths differ
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
| `MEDIA_MOVIES_PATH` | compose only | Host path mounted as `/media/movies`. |
| `MEDIA_TV_PATH` | compose only | Host path mounted as `/media/tv`. |
| `MEDIA_MUSIC_PATH` | compose only | Host path mounted as `/media/music`. |
| `MEDIA_AUDIOBOOKS_PATH` | compose only | Host path mounted as `/media/audiobooks`. |
| `MEDIA_EBOOKS_PATH` | compose only | Host path mounted as `/media/ebooks`. |
| `MEDIA_MANGA_PATH` | compose only | Host path mounted as `/media/manga`. |

## Database and cache images

The bundled Compose file prefers this homelab image set:

```text
POSTGRES_IMAGE=ghcr.io/mildman1848/postgresql:18.4-mldm4
CACHE_IMAGE=ghcr.io/mildman1848/valkey:9.0.4-mldm1
```

The cache service is still named `redis` and Silo receives `REDIS_URL=redis://redis:6379`, because Valkey is Redis-protocol compatible and many applications use `redis` as the expected DNS name.

Upstream Silo currently documents PostgreSQL 18 + pgvector. This packaging keeps the image selectable through `POSTGRES_IMAGE` so operators can switch back to `pgvector/pgvector:pg18` if upstream introduces a hard PostgreSQL 18 or pgvector requirement that the custom PostgreSQL 18 image cannot satisfy.

## Meilisearch catalog search

The bundled Compose stack includes Meilisearch as an optional search backend service:

```text
MEILISEARCH_IMAGE=getmeili/meilisearch:v1.52.3
MEILI_MASTER_KEY_FILE=./secrets/meili_master_key
```

`make secrets` creates `secrets/meili_master_key` with mode `0600` and without printing the value. The service is internal-only by default; no host port is published. Silo must still be switched from the default PostgreSQL search provider to Meilisearch in the Admin UI or API. In the Silo Admin settings use:

| Setting key | Recommended value | Notes |
|---|---|---|
| `catalog.search.provider` | `meilisearch` | Default is `postgres`. |
| `catalog.search.meilisearch.url` | `http://meilisearch:7700` | Compose service DNS name. |
| `catalog.search.meilisearch.api_key` | value from `secrets/meili_master_key` | Store as Silo encrypted setting; do not commit it. |
| `catalog.search.meilisearch.index` | `silo_media_items` | Upstream default. |
| `catalog.search.meilisearch.matching_strategy` | `last` | Upstream default; use `all` only if stricter matching is desired. |

After enabling Meilisearch, trigger the Silo catalog/search index rebuild from the Admin UI/tasks area if the UI exposes it for this upstream commit. Until the index is built, Silo intentionally falls back to PostgreSQL search.

**Risk:** Meilisearch improves search quality and latency, but it is another persistent service to back up (`./data/meilisearch`) and monitor. PostgreSQL remains the source of truth; Meilisearch is rebuildable index data, not the canonical catalog database.

## Trakt setup

Silo has built-in Trakt watch-sync support in this upstream commit. The provider supports watched/progress import, watched/progress export, favorites, watchlist, and playback scrobbling.

Setup flow:

1. Create a Trakt API application at <https://trakt.tv/oauth/applications>.
2. Store the generated Client ID and Client Secret in Silo Admin settings:

   ```text
   watchsync.trakt.client_id
   watchsync.trakt.client_secret
   ```

3. Restart Silo after setting the Trakt Client ID. Upstream marks `watchsync.trakt.client_id` as restart-sensitive for collection browser wiring.
4. For each Silo profile/user that should sync, start the Trakt connection in the Silo UI. Silo uses Trakt device OAuth: it requests a device code and the user authorizes it at Trakt.
5. Run or schedule the Silo task `sync_watch_providers` if it is not already scheduled by the UI. The Admin Dashboard exposes Trakt activity metrics when configured.

Keep Client Secret and OAuth tokens out of Compose files. Silo encrypts sensitive third-party credentials at rest using `SECRET_KEY`, so losing `SECRET_KEY` can make those credentials unrecoverable.

## Plugins, SSO and LDAP/OIDC

Upstream has a plugin runtime and official first-party plugin repositories for metadata, markers, and arr-autoscan. The public Silo org currently exposes these relevant repositories:

- `silo-plugins` — official plugin catalog metadata
- `silo-plugin-sdk` — public Go SDK / protobuf contracts
- `silo-plugin-metadata-tmdb`
- `silo-plugin-metadata-tvdb`
- `silo-plugin-metadata-audiobook`
- `silo-plugin-metadata-ebook`
- `silo-plugin-metadata-manga`
- `silo-plugin-markers-theintrodb`
- `silo-plugin-autoscan-arr`

The server code already supports `auth_provider.v1` plugin capabilities, including credential-style auth and OAuth-style `Sign in with X` flows with optional auto-provisioning. However, no official or obvious public Silo LDAP/OIDC/SSO plugin was found for this upstream commit.

Recommendation for homelab SSO today:

- **Pragmatic:** run Silo behind SWAG/Authelia for network-level access control, but keep Silo's own login as the application identity. This is not true SSO, but it reduces public exposure.
- **Best practice later:** use or build a Silo auth-provider plugin for OIDC against Authelia/Authentik/Keycloak once the plugin contract and catalog stabilize. LDAP direct bind is less attractive than OIDC because it spreads directory credentials and makes MFA/session policy harder.
- **Avoid for now:** patching Silo core for LDAP unless upstream SSO stalls. That creates a source fork we then have to nurse like a sickly demon hamster.


## Media library paths

The bundled Compose file mounts media categories separately and read-only. In the Silo admin UI, add libraries using the container paths, not the host paths:

```text
Movies:      /media/movies
TV/Shows:    /media/tv
Music:       /media/music
Audiobooks:  /media/audiobooks
Ebooks:      /media/ebooks
Manga/Comics:/media/manga
```

For NAS-backed media, point the local `.env` variables at the mounted host paths, for example `/mnt/media/movies`. Ensure the NAS path is actually mounted on the Docker host before starting Compose.

## Docker secrets / `FILE__` variables

The image supports LSIO-style secret-file variables:

```yaml
environment:
  FILE__SECRET_KEY: /run/secrets/silo_secret_key
  FILE__POSTGRES_PASSWORD: /run/secrets/postgres_password
```

The helper never logs secret values.

## Hardware acceleration

For Intel/AMD VAAPI/QSV, use the optional compose override on hosts that actually provide `/dev/dri`:

```bash
docker compose -f docker-compose.yml -f docker-compose.vaapi.yml up -d
```

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
