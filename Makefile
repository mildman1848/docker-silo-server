SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

IMAGE_NAME ?= ghcr.io/mildman1848/silo-server
POSTGRES_IMAGE ?= ghcr.io/mildman1848/postgresql:18.4-mldm4
CACHE_IMAGE ?= ghcr.io/mildman1848/valkey:9.0.4-mldm1
UPSTREAM_REPO ?= https://github.com/Silo-Server/silo-server.git
UPSTREAM_REF ?= 881c96864bafec423f91438059b21b84a6f68686
APP_VERSION ?= git-881c968
IMAGE_REVISION ?= mldm1
VERSION ?= $(APP_VERSION)-$(IMAGE_REVISION)
POSTGRES_USER ?= silo
POSTGRES_DB ?= silo
LSIO_BASE_VERSION ?= bookworm
DOCKER ?= docker
PLATFORM ?= linux/amd64

.PHONY: info version labels secrets lint build smoke clean-smoke compose-config

info: version labels
	@printf 'Upstream: %s\n' '$(UPSTREAM_REPO)'
	@printf 'Upstream ref: %s\n' '$(UPSTREAM_REF)'
	@printf 'Image: %s:%s\n' '$(IMAGE_NAME)' '$(VERSION)'
	@printf 'PostgreSQL user: %s\n' '$(POSTGRES_USER)'
	@printf 'PostgreSQL database: %s\n' '$(POSTGRES_DB)'
	@printf 'PostgreSQL image: %s\n' '$(POSTGRES_IMAGE)'
	@printf 'Cache image: %s\n' '$(CACHE_IMAGE)'

version:
	@printf '%s\n' '$(VERSION)'

labels:
	@printf 'org.opencontainers.image.licenses=AGPL-3.0-or-later\n'
	@printf 'org.opencontainers.image.revision=%s\n' '$(UPSTREAM_REF)'
	@printf 'org.opencontainers.image.source=https://github.com/mildman1848/docker-silo-server\n'
	@printf 'org.opencontainers.image.url=https://github.com/Silo-Server/silo-server\n'

secrets:
	@mkdir -p secrets
	@if [ ! -f .env ]; then cp .env.example .env; fi
	@python3 scripts/generate-secrets.py

lint: compose-config
	@while IFS= read -r script; do \
		printf 'bash -n %s\n' "$$script"; \
		bash -n "$$script"; \
	done < <(find root scripts -type f \( -name '*.sh' -o -path '*/run' -o -path '*/up' -o -name 'file-env' -o -name 'start-silo' \) | sort)
	@python3 -m py_compile scripts/generate-secrets.py
	@if command -v hadolint >/dev/null 2>&1; then hadolint -c .hadolint.yaml Dockerfile; else echo 'hadolint not installed; skipping'; fi

compose-config:
	@tmp_env="$$(mktemp)"; \
	printf '%s\n' \
		'MEDIA_MOVIES_PATH=/tmp/silo-media/movies' \
		'MEDIA_TV_PATH=/tmp/silo-media/tv' \
		'MEDIA_MUSIC_PATH=/tmp/silo-media/music' \
		'MEDIA_AUDIOBOOKS_PATH=/tmp/silo-media/audiobooks' \
		'MEDIA_EBOOKS_PATH=/tmp/silo-media/ebooks' \
		'MEDIA_MANGA_PATH=/tmp/silo-media/manga' \
		'POSTGRES_PASSWORD_FILE=./secrets/postgres_password' \
		'SECRET_KEY_FILE=./secrets/silo_secret_key' > "$$tmp_env"; \
	$(DOCKER) compose --env-file "$$tmp_env" config >/dev/null; \
	rm -f "$$tmp_env"

build:
	$(DOCKER) build \
		--platform '$(PLATFORM)' \
		--build-arg UPSTREAM_REPO='$(UPSTREAM_REPO)' \
		--build-arg UPSTREAM_REF='$(UPSTREAM_REF)' \
		--build-arg APP_VERSION='$(APP_VERSION)' \
		--build-arg IMAGE_REVISION='$(IMAGE_REVISION)' \
		--build-arg VERSION='$(VERSION)' \
		--build-arg LSIO_BASE_VERSION='$(LSIO_BASE_VERSION)' \
		-t '$(IMAGE_NAME):$(VERSION)' \
		.

smoke: secrets
	IMAGE_NAME='$(IMAGE_NAME)' IMAGE_TAG='$(VERSION)' POSTGRES_IMAGE='$(POSTGRES_IMAGE)' CACHE_IMAGE='$(CACHE_IMAGE)' POSTGRES_USER='$(POSTGRES_USER)' POSTGRES_DB='$(POSTGRES_DB)' DOCKER='$(DOCKER)' ./scripts/smoke.sh

clean-smoke:
	DOCKER='$(DOCKER)' ./scripts/smoke.sh clean
