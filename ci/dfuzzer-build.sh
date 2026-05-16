#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Build dfuzzer from upstream source. Run from
## .github/workflows/local-dbus-fuzz.yml (R-100; no inline scripts
## in the YAML).
##
## Build / runtime deps are installed by the caller workflow via
## developer-meta-files/.github/actions/apt-install-with-cache (a
## composite action that bundles cache + install with a
## runner-owned .deb sidecar). The package list lives in the
## caller workflow alongside the cache key.
##
## Required apt deps for this script:
##   - meson ninja-build              # build system
##   - xsltproc docbook-xsl           # man-page generation
##   - libglib2.0-dev                 # dfuzzer dep
##   - dbus dbus-x11                  # dfuzzer runtime
##   - libdbus-1-dev libsystemd-dev pkg-config gcc   # for the
##                                                   # fm-shim-backend
##                                                   # build below
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

## TODO: Better to clone the whole repository, then check out a commit hash?
git clone --depth 1 --branch "${DFUZZER_TAG}" \
  https://github.com/dbus-fuzzer/dfuzzer /tmp/dfuzzer
meson setup --buildtype=release /tmp/dfuzzer/build /tmp/dfuzzer
ninja -C /tmp/dfuzzer/build -v
sudo install -m 0755 /tmp/dfuzzer/build/dfuzzer /usr/local/bin/dfuzzer
dfuzzer --version || dfuzzer -V || true
