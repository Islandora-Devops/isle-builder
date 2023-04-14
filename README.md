# Isle Builder <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)
[![pre-commit](https://github.com/Islandora-Devops/isle-builder/actions/workflows/pre-commit.yaml/badge.svg?event=push)](https://github.com/Islandora-Devops/isle-builder/actions/workflows/pre-commit.yaml)

## Table of Contents <!-- omit in toc -->
- [Introduction](#introduction)
- [Requirements](#requirements)
- [Usage](#usage)

## Introduction

The repository is for local testing purposes, it makes it easier to setup a
[buildkit] builder for use with [buildx], capable of multi-platform builds.

The repository can be used by [isle-buildkit], [isle-site-template], [sandbox],
and others.

If you are looking to use Islandora, please read the [official documentation].

## Requirements

- [Docker 20.10+](https://docs.docker.com/get-docker/)
- [GNU Make 4.3+](https://www.gnu.org/software/make/)
- [mkcert 1.4+](https://github.com/FiloSottile/mkcert)
- [pre-commit 2.19+](https://pre-commit.com/) (Optional)

> Note: The version of `make` that comes with OSX is too old. Please update
> using `brew` or another package manager.

## Usage

```bash
$ make
USAGE:
  make [TARGET]... [ARG=VALUE]...

ARGS:
  BUILDER_NAME                   The name of the builder. (e.g. isle-builder)
  NETWORK_NAME                   The name of the network. (e.g. isle-builder)
  REGISTRY_NAME                  The name of the registry container. (e.g. isle-builder-registry)
  REGISTRY_PORT                  The port to expose for registry access. Access via HTTPS. (e.g. 0, which will randomly assigned an open port)
  BUILDER_KEEP_STORAGE           When pruning the amount of storage to keep. Set to '0' to remove all. (e.g. 10G)

TARGETS:
  start                          Starts the Docker image registry and creates the builder if it does not exist.
  use                            Switches the default builder to use the one created by the 'start' target.
  stop                           Stops the stops the builder and Docker image registry.
  prune                          Frees up disk space by pruning the builder cache.
  destroy                        Destroys the builder and Docker image registry.
  help                           Displays this help message.
```

[buildkit]: https://docs.docker.com/build/buildkit
[buildx]: https://docs.docker.com/engine/reference/commandline/buildx
[docker compose]: https://docs.docker.com/compose/reference
[isle-buildkit]: https://github.com/Islandora-Devops/isle-buildkit
[isle-site-template]: https://github.com/Islandora-Devops/isle-site-template
[official documentation]: https://islandora.github.io/documentation
[sandbox]: https://github.com/Islandora-Devops/sandbox
