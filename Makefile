.PHONY: build install run smoke workspace-image workspace sandbox clean deps push
SHELL := /bin/bash

# Azure Container Registry (ACR) configuration.
# Required env vars for `make push`:
#   - ACR_LOGIN_SERVER   (e.g. myregistry.azurecr.io)
#   - ACR_USERNAME
#   - ACR_PASSWORD
ACR_LOGIN_SERVER ?=
ACR_USERNAME ?=
ACR_PASSWORD ?=

# Tag to push to ACR (override via `make push ACR_TAG=...`).
ACR_TAG ?= latest

# Derive image name (repo) from IMAGE, which is expected to include a tag.
IMAGE_NAME ?= $(word 1,$(subst :, ,$(IMAGE)))

# Full ACR destination (repo + tag).
ACR_IMAGE ?= $(ACR_LOGIN_SERVER)/$(IMAGE_NAME):$(ACR_TAG)

# Push the locally built image to Azure Container Registry.
push:
	@if ! $(PODMAN) image exists $(IMAGE) >/dev/null 2>&1; then \
		echo "Image '$(IMAGE)' not found. Run make install first."; \
		exit 1; \
	fi
	@if [ -z "$(ACR_LOGIN_SERVER)" ]; then echo "Missing ACR_LOGIN_SERVER. Set it (e.g. myregistry.azurecr.io) and try again."; exit 1; fi
	@if [ -z "$(ACR_USERNAME)" ]; then echo "Missing ACR_USERNAME. Set it and try again."; exit 1; fi
	@if [ -z "$(ACR_PASSWORD)" ]; then echo "Missing ACR_PASSWORD. Set it and try again."; exit 1; fi
	@echo "Logging in to ACR: $(ACR_LOGIN_SERVER)"
	@echo "$(ACR_PASSWORD)" | $(PODMAN) login "$(ACR_LOGIN_SERVER)" --username "$(ACR_USERNAME)" --password-stdin >/dev/null
	@echo "Tagging local image '$(IMAGE)' as '$(ACR_IMAGE)'"
	@$(PODMAN) tag "$(IMAGE)" "$(ACR_IMAGE)"
	@echo "Pushing '$(ACR_IMAGE)'"
	@$(PODMAN) push "$(ACR_IMAGE)"

# Image name/tag used for local development.
IMAGE ?= devcontainer-base-fedora:local

# Workspace image/container naming.
WORKSPACE_IMAGE ?= fedora-workspace:latest
WORKSPACE_CONTAINER ?= fedora-workspace

# Optional build args for dotfiles import.
# Example:
#   make build DOTFILES_REPO=https://github.com/you/dotfiles.git DOTFILES_REV=master
DOTFILES_REPO ?=
DOTFILES_REV ?= master
# Use podman by default.
PODMAN ?= podman

deps:
	@command -v podman >/dev/null 2>&1 || ( \
		 echo "Podman not found. Attempting to install Podman..."; \
		 if command -v powershell >/dev/null 2>&1; then \
			 powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-podman.ps1; \
		 elif command -v bash >/dev/null 2>&1; then \
			 bash scripts/install-podman.sh; \
		 else \
			 echo "No podman and no supported shell found for auto-install. Install Podman manually."; \
			 exit 1; \
		 fi \
	)

build:
	$(PODMAN) build -t $(IMAGE) \
	  --build-arg USERNAME=developer \
	  --build-arg USER_UID=1000 \
	  --build-arg USER_GID=1000 \
	  --build-arg DOTFILES_REPO="$(DOTFILES_REPO)" \
	  --build-arg DOTFILES_REV="$(DOTFILES_REV)" \
	  .

# Alias requested by you: "make install" creates the image.
install: deps build

run:
	$(PODMAN) run --rm -it $(IMAGE) bash

# Runs the in-repo smoke-check script via a bind-mount (so the image filesystem stays smoke-free).
smoke:
	$(PODMAN) run --rm -v "$(CURDIR):/workspaces" $(IMAGE) bash -lc "bash scripts/smoke-check.sh"

# Retag the base image as a stable, long-lived workspace image.
workspace-image: install
	@echo "Tagging local image '$(IMAGE)' as '$(WORKSPACE_IMAGE)'"
	@$(PODMAN) tag "$(IMAGE)" "$(WORKSPACE_IMAGE)"

# Create/recreate the long-lived workspace container, honoring .devcontainer/devcontainer.json forwardPorts, then run the repo-owned smoke script inside it.
workspace: workspace-image
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/workspace.ps1 -Action Workspace -WorkspaceImage "$(WORKSPACE_IMAGE)" -WorkspaceContainer "$(WORKSPACE_CONTAINER)"

# Convenience: create/enter a sandbox for the current directory.
# Note: this is not the general anywhere workflow; inside the workspace, the in-container `sandbox` command is the general workflow.
sandbox:
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/workspace.ps1 -Action Sandbox -WorkspaceContainer "$(WORKSPACE_CONTAINER)" -SourceDir "$(CURDIR)"

clean:
	-$(PODMAN) rmi $(IMAGE) || true
