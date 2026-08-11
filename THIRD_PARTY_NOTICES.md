# Third-Party Notices

## Silo Server

- Upstream: <https://github.com/Silo-Server/silo-server>
- License: GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`)
- Current pinned commit: `881c96864bafec423f91438059b21b84a6f68686`

The built image compiles Silo Server from the pinned upstream commit. If local
patches are added in the future, they must be published in this repository and
documented here.

## LinuxServer.io baseimage

Runtime base image:

```text
ghcr.io/linuxserver/baseimage-debian:bookworm
```

The base image provides s6-overlay and LinuxServer.io-compatible `PUID`/`PGID`
runtime user handling.

## Jellyfin FFmpeg

The runtime installs `jellyfin-ffmpeg7` from the Jellyfin Debian repository, as
used by upstream Silo Server's Dockerfile.

## Node.js / npm

The runtime copies `node` and `npm` from the official `node:22-slim` build stage,
mirroring the upstream Dockerfile behavior.
