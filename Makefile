# Include docker-compose environment variables.
include .env

# Display help by default.
.DEFAULT_GOAL := help

# Require bash to use foreach loops.
SHELL := bash

# Check if running in an interactive shell and not on a dumb terminal
HAS_INTERACTIVE_SHELL := $(shell [ -t 0 ] && [ "$$TERM" != "dumb" ] && echo "true")

# Define color codes using tput if tty is available, otherwise set to empty strings
ifeq ($(HAS_INTERACTIVE_SHELL),true)
	RESET := $(shell tput sgr0)
	RED := $(shell tput setaf 1)
	BLUE := $(shell tput setaf 4)
	GREEN := $(shell tput setaf 6)
else
	RESET :=
	RED :=
	BLUE :=
	GREEN :=
endif
TARGET_MAX_CHAR_NUM := 30

# When pruning the amount of storage to keep.
# Set to 0 to remove all.
BUILDER_KEEP_STORAGE := 10G

# Display text for requirements.
README_MESSAGE = ${BLUE}Consult the README.md for how to install requirements.${RESET}\n

# For some commands we must invoke a Windows executable if in the context of WSL.
IS_WSL := $(shell grep -q WSL /proc/version 2>/dev/null && echo "true")

# Use the host mkcert.exe if executing make from WSL context.
MKCERT := $(if $(filter true,$(IS_WSL)),mkcert.exe,mkcert)

# The location of root certificates.
MKCERT_EXISTS := $(shell command -v $(MKCERT) &>/dev/null && echo "true")
ifeq ($(MKCERT_EXISTS),true)
	CAROOT := $(if $(filter true,$(IS_WSL)),$(shell $(MKCERT) -CAROOT | xargs -0 wslpath -u),$(shell $(MKCERT) -CAROOT))
else
	CAROOT :=
endif

# Checks for mkcert/mkcert.exe depending on platform.
.PHONY: $(MKCERT)
$(MKCERT): MISSING_MKCERT_MESSAGE = ${RED}$(MKCERT) is not installed${RESET}\n${README_MESSAGE}
$(MKCERT):
	@if ! command -v $(MKCERT) >/dev/null; \
	then \
		printf "$(MISSING_MKCERT_MESSAGE)"; \
		exit 1; \
	fi

# Checks for docker compose plugin.
.PHONY: docker
docker: MISSING_DOCKER_MESSAGE = ${RED}docker is not installed${RESET}\n${README_MESSAGE}
docker:
  # Check for `docker compose` as compose version 2+ is used is assumed.
	@if ! docker version &>/dev/null; \
	then \
		printf "$(MISSING_DOCKER_MESSAGE)"; \
		exit 1; \
	fi

# Checks for docker compose plugin.
.PHONY: docker-compose
docker-compose: MISSING_DOCKER_PLUGIN_MESSAGE = ${RED}docker compose plugin is not installed${RESET}\n${README_MESSAGE}
docker-compose: | docker
  # Check for `docker compose` as compose version 2+ is used is assumed.
	@if ! docker compose version &>/dev/null; \
	then \
		printf "$(MISSING_DOCKER_PLUGIN_MESSAGE)"; \
		exit 1; \
	fi

# Checks for docker buildx plugin.
.PHONY: docker-buildx
docker-buildx: MISSING_DOCKER_BUILDX_PLUGIN_MESSAGE = ${RED}docker buildx plugin is not installed${RESET}\n${README_MESSAGE}
docker-buildx: | docker
  # Check for `docker buildx` as we do not support building without it.
	@if ! docker buildx version &>/dev/null; \
	then \
		printf "$(MISSING_DOCKER_BUILDX_PLUGIN_MESSAGE)"; \
		exit 1; \
	fi

$(CAROOT)/rootCA-key.pem $(CAROOT)/rootCA.pem &: | $(MKCERT)
  # Requires mkcert to be installed first (It may fail on some systems due to how Java is configured, but this can be ignored).
	-$(MKCERT) -install

certs:
	mkdir -p certs

certs/rootCA.pem: certs $(CAROOT)/rootCA-key.pem
	cp "$(CAROOT)/rootCA.pem" certs/rootCA.pem

# Using mkcert to generate local certificates rather than traefik certs
# as they often get revoked.
certs/cert.pem certs/privkey.pem &: certs $(CAROOT)/rootCA-key.pem $(CAROOT)/rootCA.pem
	$(MKCERT) -cert-file certs/cert.pem -key-file certs/privkey.pem \
		"*.islandora.dev" \
		"islandora.dev" \
		"*.islandora.io" \
		"islandora.io" \
		"*.islandora.info" \
		"islandora.info" \
		"localhost" \
		"127.0.0.1" \
		"::1"

.PHONY: start
## Starts the Docker image registry and creates the builder if it does not exist.
start: certs/cert.pem certs/privkey.pem certs/rootCA.pem | docker-buildx docker-compose
  # Start the registry if not already started.
	@if ! docker inspect $(REGISTRY_NAME) &>/dev/null; then \
		docker compose up -d registry; \
	fi
  # Get auto assigned port for registry or explicit one and start the ui as well.
	@REGISTRY_PORT=$$(docker inspect --format='{{(index (index .NetworkSettings.Ports "443/tcp") 0).HostPort}}' $(REGISTRY_NAME)) docker compose up -d ui
  # Create the builder if not already created.
	@if ! docker buildx inspect --bootstrap $(BUILDER_NAME) &>/dev/null; \
	then \
		docker buildx create \
			--append \
			--bootstrap \
			--config buildkitd.toml \
			--driver-opt "image=moby/buildkit:${BUILDKIT_TAG},network=${NETWORK_NAME}" \
			--name "$(BUILDER_NAME)" \
			--node "$(BUILDER_NAME)"; \
	fi

.PHONY: use
## Switches the default builder to use the one created by the 'start' target.
use: | start
	docker buildx use $(BUILDER_NAME)

.PHONY: port
## Displays the port the Docker image registry is running on.
port: REGISTRY_PORT=$$(docker inspect --format='{{(index (index .NetworkSettings.Ports "443/tcp") 0).HostPort}}' $(REGISTRY_NAME))
port: UI_PORT=$$(docker inspect --format='{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' $(REGISTRY_NAME)-ui)
port: PORT_MESSAGE = "  ${RED}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n"
port:
	@printf $(PORT_MESSAGE) "Registry" "https://islandora.io:$(REGISTRY_PORT)"
	@printf $(PORT_MESSAGE) "UI" "http://islandora.io:$(UI_PORT)"

.PHONY: stop
## Stops the stops the builder and Docker image registry.
stop: | docker-buildx docker-compose
  # Stop the builder.
	@if docker buildx inspect $(BUILDER_NAME) &>/dev/null; \
	then \
		docker buildx stop $(BUILDER_NAME); \
	fi
  # Stop the registry.
	@docker compose stop

.PHONY: prune
## Frees up disk space by pruning the builder cache.
prune:
  # Stop the builder.
	@if docker buildx inspect $(BUILDER_NAME) &>/dev/null; \
	then \
		docker buildx prune --builder $(BUILDER_NAME) --keep-storage $(BUILDER_KEEP_STORAGE) --force; \
	fi

.PHONY: destroy
## Destroys the builder and Docker image registry.
destroy: | docker-buildx docker-compose
  # Destroy the builder.
	@if docker buildx inspect $(BUILDER_NAME) &>/dev/null; \
	then \
		docker buildx rm $(BUILDER_NAME); \
	fi
  # Stop the registry.
	@docker compose down -v
  # Delete the certs.
	@rm -rf certs/*.pem

.PHONY: help
.SILENT: help
## Displays this help message.
help: ARG_MESSAGE = "  ${RED}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET} ${RED}(e.g. %s)${RESET} %s\n"
help:
	@echo ''
	@echo 'USAGE:'
	@echo '  ${RED}make${RESET} ${GREEN}[TARGET]...${RESET} ${GREEN}[ARG=VALUE]...${RESET}'
	@echo ''
	@echo 'ARGS:'
	printf $(ARG_MESSAGE) BUILDER_NAME  "The name of the builder." $(BUILDER_NAME)
	printf $(ARG_MESSAGE) NETWORK_NAME  "The name of the network." $(NETWORK_NAME)
	printf $(ARG_MESSAGE) REGISTRY_NAME "The name of the registry container." $(REGISTRY_NAME)
	printf $(ARG_MESSAGE) REGISTRY_PORT "The port to expose for registry access. Access via HTTPS." "$(REGISTRY_PORT), which will randomly assigned an open port"
	printf $(ARG_MESSAGE) BUILDER_KEEP_STORAGE "When pruning the amount of storage to keep. Set to '0' to remove all." $(BUILDER_KEEP_STORAGE)

	@echo ''
	@echo 'TARGETS:'
	@awk '/^[a-zA-Z\-_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; sub(/:$$/, "", helpCommand); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${RED}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{lastLine = $$0}' $(MAKEFILE_LIST)
	@echo ''
