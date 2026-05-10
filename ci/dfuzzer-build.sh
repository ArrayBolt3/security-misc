#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Install build dependencies and build dfuzzer from upstream source.
## Run from .github/workflows/dfuzzer.yml (R-100; no inline scripts in
## the YAML).
##
## Two phases:
##   1. apt-get install:
##      - dfuzzer build deps (meson, ninja, glib, xsltproc, docbook)
##      - dfuzzer runtime deps (dbus, dbus-x11)
##      - fm-shim-backend build deps (libdbus-1-dev, libsystemd-dev,
##        pkg-config, gcc)
##   2. clone dfuzzer at pinned tag, meson setup + ninja, install to
##      /usr/local/bin/dfuzzer
##
## dfuzzer is NOT packaged in Ubuntu 24.04 noble (verified via
## packages.ubuntu.com - 'No such package'); hence the from-source
## build. Pinned to upstream tag v2.6 (latest release as of
## 2026-05-08). Bump when a new release lands.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI. Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

DFUZZER_TAG="${DFUZZER_TAG:-v2.6}"

## Phase 1: apt install. Caller workflow's actions/cache step
## populates /var/cache/apt/archives ahead of this; apt-get install
## then reuses the cached .debs.
sudo --non-interactive apt-get update --error-on=any
sudo --non-interactive apt-get install --yes --no-install-recommends \
  meson ninja-build \
  xsltproc docbook-xsl \
  libglib2.0-dev \
  dbus dbus-x11 \
  libdbus-1-dev libsystemd-dev pkg-config gcc

## Phase 2: dfuzzer build.
git clone --depth 1 --branch "${DFUZZER_TAG}" \
  https://github.com/dbus-fuzzer/dfuzzer /tmp/dfuzzer
meson setup --buildtype=release /tmp/dfuzzer/build /tmp/dfuzzer
ninja -C /tmp/dfuzzer/build -v
sudo install -m 0755 /tmp/dfuzzer/build/dfuzzer /usr/local/bin/dfuzzer
dfuzzer --version || dfuzzer -V || true
