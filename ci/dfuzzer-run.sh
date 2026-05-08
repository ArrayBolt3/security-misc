#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Run dfuzzer against fm-shim-backend's D-Bus surface.
##
## fm-shim-backend implements org.freedesktop.FileManager1 on the
## session bus. dfuzzer is the standard D-Bus service fuzzer
## (Debian-archive-shipped); given a bus name it iterates every
## method and signal on every interface the service exposes, sends
## type-correct adversarial payloads (overflow, mangled UTF-8,
## empty / max-length strings, weird container nesting), and
## flags any case where the service crashes, hangs, or returns
## an unexpected error.
##
## This is process-level fuzzing - we boot the actual binary
## under a transient D-Bus session bus rather than driving the
## function dispatcher in-process. Catches the integration
## surface (D-Bus marshaling glue, sd_notify, signal handlers,
## leaks across method calls) that an in-process libFuzzer
## harness on the parser alone would miss.
##
## Cwd contract: caller workflow runs this with the
## security-misc repo checkout as cwd. ci/codeql-prepare.sh
## must have run first to create the .c symlink the upstream
## compile script expects.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## CI guard.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

dfuzzer_seconds="${DFUZZER_SECONDS:-60}"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

printf '%s\n' "::group::Build fm-shim-backend"
bash 'usr/libexec/security-misc/compile-fm-shim-backend#security-misc-shared' \
  usr/src/security-misc/fm-shim-backend.c \
  "${work}/fm-shim-backend"
chmod 0755 -- "${work}/fm-shim-backend"
ls -l -- "${work}/fm-shim-backend"
printf '%s\n' "::endgroup::"

## Register the service file under XDG_DATA_HOME so the transient
## dbus-run-session below can auto-activate fm-shim-backend on
## first method call. NB: 'Exec=' must be an absolute path; the
## tmpdir path is generated above.
service_dir="${HOME}/.local/share/dbus-1/services"
mkdir -p -- "${service_dir}"
cat > "${service_dir}/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=${work}/fm-shim-backend
EOF
printf 'Wrote service file: %s\n' "${service_dir}/org.freedesktop.FileManager1.service"
cat -- "${service_dir}/org.freedesktop.FileManager1.service"

printf '%s\n' "::group::dfuzzer (org.freedesktop.FileManager1, ${dfuzzer_seconds}s)"
## dbus-run-session boots a transient session bus and runs the
## inner shell with DBUS_SESSION_BUS_ADDRESS pointing at it.
## dfuzzer activates the service via name resolution.
##
## --max-time bounds the per-method fuzz duration so the workflow
## doesn't run unbounded. -v emits per-method progress so a CI
## maintainer reading the log can see which interface / method
## was being exercised when a crash occurred.
dbus-run-session -- bash -c '
  set -o errexit
  set -o nounset
  set -o pipefail
  printf "DBUS_SESSION_BUS_ADDRESS=%s\n" "${DBUS_SESSION_BUS_ADDRESS}"
  dfuzzer \
    --bus session \
    --name org.freedesktop.FileManager1 \
    --max-time "'"${dfuzzer_seconds}"'" \
    --verbose
'
printf '%s\n' "::endgroup::"

printf '%s\n' "dfuzzer: no crashes / exceptions detected on the fuzzed surface."
