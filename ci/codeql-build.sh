#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## CodeQL manual build for the C sources in this repo.
##
## The two C files use the genmkfile '#package-tag' filename convention
## (see ci/codeql-prepare.sh). gcc accepts those paths verbatim, so we
## hand them to the compiler unchanged - what matters for the C/C++
## extractor is that gcc sees and parses each translation unit.
##
## We compile to object files only ('-c'). No linking, no hardening
## flags - those live at runtime in the install-time build scripts
## (usr/libexec/security-misc/build-fm-shim-backend,
## usr/libexec/security-misc/emerg-shutdown). CodeQL just needs the
## front-end pass.

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

sudo --non-interactive apt-get update --error-on=any
sudo --non-interactive apt-get install --yes --no-install-recommends \
  build-essential pkg-config libdbus-1-dev libsystemd-dev linux-libc-dev

build_dir="$(mktemp -d)"
trap 'rm -rf -- "${build_dir}"' EXIT

## fm-shim-backend - dbus + systemd
gcc -c \
  -o "${build_dir}/fm-shim-backend.o" \
  $(pkg-config --cflags dbus-1) \
  $(pkg-config --cflags libsystemd) \
  'usr/src/security-misc/fm-shim-backend.c#security-misc-shared'

## emerg-shutdown - libc + linux uapi only
gcc -c \
  -o "${build_dir}/emerg-shutdown.o" \
  'usr/src/security-misc/emerg-shutdown.c#security-misc-shared'

ls -l -- "${build_dir}"
