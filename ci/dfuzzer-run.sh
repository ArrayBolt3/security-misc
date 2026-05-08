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
## dfuzzer reads that env var to talk to the session bus, then
## activates the service via name resolution against our
## XDG-local .service file.
##
## dfuzzer flag conventions (verified against v2.6 src/dfuzzer.c
## getopt table):
##   -n / --bus          bus name to fuzz (e.g. org.freedesktop.X)
##                       NB: misnamed long flag - 'bus' here means
##                       the service-bus-NAME, not the bus type.
##   -v / --verbose      per-method progress output.
## Note: dfuzzer has NO time-bounded flag. Iteration-bounded only
## (-I / --iterations). To enforce a per-job time budget we wrap
## with shell 'timeout' instead. Exit code 124 from timeout means
## "we hit the time budget" - treated as success here because the
## point was to fuzz for N seconds, not to assert dfuzzer
## terminated naturally.
##
## DBUS_SESSION_BUS_ADDRESS export inside dbus-run-session: the
## inner bash shell needs to see it; printf-debug it for log
## traceability.
rc=0
dbus-run-session -- bash -c '
  set -o nounset
  set -o pipefail
  printf "DBUS_SESSION_BUS_ADDRESS=%s\n" "${DBUS_SESSION_BUS_ADDRESS}"
  timeout --preserve-status "'"${dfuzzer_seconds}"'" \
    dfuzzer \
      -n org.freedesktop.FileManager1 \
      -v
' || rc=$?
printf '%s\n' "::endgroup::"
printf 'dfuzzer wrapper exit code: %s\n' "${rc}"

case "${rc}" in
  0)
    printf '%s\n' "dfuzzer: completed naturally; no crashes / exceptions detected."
    ;;
  124)
    ## 'timeout --preserve-status' would propagate the underlying
    ## program's exit code on a clean exit, but on timeout itself
    ## it sends SIGTERM and surfaces 124. Treat as 'budget reached,
    ## no crash detected within window'.
    printf '%s\n' "dfuzzer: ${dfuzzer_seconds}s budget reached; no crash detected within window."
    rc=0
    ;;
  *)
    printf '::error::%s\n' "dfuzzer reported a finding (exit ${rc}). See log above for the failing method."
    ;;
esac

exit "${rc}"
