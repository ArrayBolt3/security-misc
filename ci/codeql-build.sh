#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CodeQL manual build for the C sources in this repo.
##
## Delegates the actual gcc invocations to the upstream compile
## helpers under usr/libexec/security-misc/. Those helpers also run
## at install-time / first-run (out of build-fm-shim-backend and
## emerg-shutdown). Single source of truth means CI cannot drift on
## hardening flags vs runtime.
##
## Source-tree prep:
##
## ci/codeql-prepare.sh has already symlinked '*.c#<tag>' to clean
## '*.c' names by the time we run (the workflow runs prepare via
## the reusable's pre-init hook). gcc selects its driver behavior
## by file extension - a '.c#tag' source gets misclassified as a
## linker script - so the symlink is required even though gcc
## tolerates the tagged name in error messages.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
set -o xtrace

sudo --non-interactive apt-get update --error-on=any
sudo --non-interactive apt-get install --yes --no-install-recommends \
  pkg-config libdbus-1-dev libsystemd-dev libc6-dev linux-libc-dev

build_dir="$(mktemp -d)"
trap 'rm -rf -- "${build_dir}"' EXIT

bash 'usr/libexec/security-misc/compile-fm-shim-backend#security-misc-shared' \
  usr/src/security-misc/fm-shim-backend.c \
  "${build_dir}/fm-shim-backend"

bash 'usr/libexec/security-misc/compile-emerg-shutdown#security-misc-shared' \
  usr/src/security-misc/emerg-shutdown.c \
  "${build_dir}/emerg-shutdown"

ls -l -- "${build_dir}"
