.PHONY: install container-build container-smoke container-start container-shell container-stop container-rm container-rebuild sandbox push

SHELL := /bin/bash

# Azure Container Registry (ACR) configuration.
# Required env vars for `make push`:
#   - ACR_LOGIN_SERVER (e.g. myregistry.azurecr.io)
#   - ACR_USERNAME
#   - ACR_PASSWORD
ACR_LOGIN_SERVER ?=
ACR_USERNAME ?=
ACR_PASSWORD ?=

# Default pushed tag.
ACR_TAG ?= latest

# Local image and workspace container naming.
IMAGE ?= workspace:local
WORKSPACE_CONTAINER ?= workspace

# Single Makefile source of truth for the local host username.
HOST_USERNAME ?= $(if $(USER),$(USER),$(if $(USERNAME),$(USERNAME),workspace))

PODMAN ?= podman

install:
	bash scripts/install/linux.sh

container-build:
	@if ! $(PODMAN) --version >/dev/null 2>&1; then \
		echo "Podman not found; attempting auto-install..."; \
		if command -v powershell >/dev/null 2>&1; then \
			powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install/install-podman.ps1; \
		elif command -v bash >/dev/null 2>&1; then \
			bash scripts/install/install-podman.sh; \
		else \
			echo "No supported shell found for auto-install. Install Podman manually." >&2; \
			exit 1; \
		fi; \
	fi
	$(PODMAN) build -t $(IMAGE) \
	  -f container/Containerfile \
	  --build-arg USERNAME="$(HOST_USERNAME)" \
	  --build-arg USER_UID=1000 \
	  --build-arg USER_GID=1000 \
	  .

container-smoke:
	$(PODMAN) run --rm \
	  -e TERM=xterm-256color \
	  -e EXPECTED_USER="$(HOST_USERNAME)" \
	  -v "$(CURDIR):/repo" \
	  $(IMAGE) \
	  bash -lc "cd /repo && bash scripts/container/smoke-check.sh"

container-start: container-build
	@if command -v powershell >/dev/null 2>&1; then \
		powershell -NoProfile -ExecutionPolicy Bypass -File scripts/container/workspace.ps1 \
		  -Action Start \
		  -Image "$(IMAGE)" \
		  -WorkspaceContainer "$(WORKSPACE_CONTAINER)" \
		  -HostUsername "$(HOST_USERNAME)"; \
	else \
		IMAGE="$(IMAGE)" \
		WORKSPACE_CONTAINER="$(WORKSPACE_CONTAINER)" \
		HOST_USERNAME="$(HOST_USERNAME)" \
		WORKSPACE_ROOT="$${WORKSPACE_ROOT:-$$HOME}" \
			bash scripts/container/workspace.sh start; \
	fi

container-shell:
	$(PODMAN) exec -it $(WORKSPACE_CONTAINER) bash

container-stop:
	@if $(PODMAN) container exists $(WORKSPACE_CONTAINER) >/dev/null 2>&1; then \
		$(PODMAN) stop $(WORKSPACE_CONTAINER) >/dev/null; \
	fi

container-rm:
	@if $(PODMAN) container exists $(WORKSPACE_CONTAINER) >/dev/null 2>&1; then \
		$(PODMAN) rm -f $(WORKSPACE_CONTAINER) >/dev/null; \
	fi

container-rebuild:
	$(MAKE) container-rm
	$(MAKE) container-build
	$(MAKE) container-start

sandbox:
	@if command -v powershell >/dev/null 2>&1; then \
		powershell -NoProfile -ExecutionPolicy Bypass -File scripts/container/workspace.ps1 \
		  -Action Sandbox \
		  -Image "$(IMAGE)" \
		  -WorkspaceContainer "$(WORKSPACE_CONTAINER)" \
		  -HostUsername "$(HOST_USERNAME)" \
		  -SourceDir "$(CURDIR)"; \
	else \
		IMAGE="$(IMAGE)" \
		WORKSPACE_CONTAINER="$(WORKSPACE_CONTAINER)" \
		HOST_USERNAME="$(HOST_USERNAME)" \
		WORKSPACE_ROOT="$${WORKSPACE_ROOT:-$$HOME}" \
		SOURCE_DIR="$(CURDIR)" \
			bash scripts/container/workspace.sh sandbox; \
	fi

push:
	@if ! $(PODMAN) image exists $(IMAGE) >/dev/null 2>&1; then \
		echo "Image '$(IMAGE)' not found. Run make container-build first." >&2; \
		exit 1; \
	fi
	@if [ -z "$(ACR_LOGIN_SERVER)" ]; then echo "Missing ACR_LOGIN_SERVER. Set it (e.g. myregistry.azurecr.io) and try again."; exit 1; fi
	@if [ -z "$(ACR_USERNAME)" ]; then echo "Missing ACR_USERNAME. Set it and try again."; exit 1; fi
	@if [ -z "$(ACR_PASSWORD)" ]; then echo "Missing ACR_PASSWORD. Set it and try again."; exit 1; fi
	@echo "Logging in to ACR: $(ACR_LOGIN_SERVER)"
	@echo "$(ACR_PASSWORD)" | $(PODMAN) login "$(ACR_LOGIN_SERVER)" --username "$(ACR_USERNAME)" --password-stdin >/dev/null
	@echo "Tagging local image '$(IMAGE)' as '$(ACR_LOGIN_SERVER)/workspace:$(ACR_TAG)'"
	@$(PODMAN) tag "$(IMAGE)" "$(ACR_LOGIN_SERVER)/workspace:$(ACR_TAG)"
	@echo "Pushing '$(ACR_LOGIN_SERVER)/workspace:$(ACR_TAG)'"
	@$(PODMAN) push "$(ACR_LOGIN_SERVER)/workspace:$(ACR_TAG)"

