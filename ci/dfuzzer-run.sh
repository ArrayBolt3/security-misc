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

## Inner script that runs INSIDE dbus-run-session's transient
## session bus. Manually starts fm-shim-backend in the background
## (auto-activation via XDG service files turned out to be
## flaky inside dbus-run-session) and fuzzes it.
##
## Written to a temp file rather than passed inline via 'bash -c'
## to avoid the multi-level shell quoting that was hiding bugs
## during initial debugging.
inner="${work}/dfuzzer-inner.sh"
cat > "${inner}" <<'INNER'
#!/bin/bash
set -o nounset
set -o pipefail
set -o errtrace

## Args (positional) from outer script:
##   $1 = backend binary path
##   $2 = dfuzzer seconds budget
backend_bin="$1"
seconds="$2"

printf 'DBUS_SESSION_BUS_ADDRESS=%s\n' "${DBUS_SESSION_BUS_ADDRESS}"

backend_log="$(dirname -- "${backend_bin}")/fm-shim-backend.log"

## Start fm-shim-backend in the background. Capture its stdout +
## stderr so we can surface them in the workflow log if dfuzzer
## fails to connect (without a tty the backend's output is
## block-buffered and would otherwise be lost on kill).
"${backend_bin}" >"${backend_log}" 2>&1 &
backend_pid=$!
trap 'kill "${backend_pid}" 2>/dev/null || true' EXIT

## Wait up to 5s for the backend to register the well-known name
## on the bus. dbus-run-session-internal name registration is
## usually < 100ms but allow a generous budget for slow runners.
for _i in 1 2 3 4 5; do
  sleep 1
  if ! kill -0 "${backend_pid}" 2>/dev/null; then
    printf '::error::%s\n' "fm-shim-backend exited during startup"
    cat -- "${backend_log}" || true
    wait "${backend_pid}" 2>/dev/null
    exit 1
  fi
  if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
       /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
       string:org.freedesktop.FileManager1 2>/dev/null \
       | grep -q 'boolean true'; then
    printf 'fm-shim-backend registered (after %ss)\n' "${_i}"
    break
  fi
done

## Sanity-check: confirm the name is actually owned and dump the
## backend's startup output to the workflow log. If anything
## subsequent fails, this gives a maintainer enough to triage.
printf '%s\n' "::group::backend startup log"
cat -- "${backend_log}" 2>/dev/null || printf '(no log lines flushed yet)\n'
printf '%s\n' "::endgroup::"

printf '%s\n' "::group::busctl introspect (verifies Introspectable wiring)"
busctl --user --no-pager introspect \
  org.freedesktop.FileManager1 /org/freedesktop/FileManager1 || true
printf '%s\n' "::endgroup::"

## Run the actual fuzzer. Iteration-bounded by default (-I 50
## per method gives enough coverage on the small FileManager1
## surface; bumpable per consumer). Total wall-clock bounded
## by the outer timeout wrapper.
rc=0
## -n  bus name (required)
## -o  object path - dfuzzer defaults to '/' if omitted, which is
##     empty for fm-shim-backend (its methods are at
##     /org/freedesktop/FileManager1). Without -o the previous
##     runs exited in milliseconds because there was nothing to
##     fuzz at the default path.
## -I  iterations per method.
## -v  verbose per-method progress.
timeout --preserve-status "${seconds}" \
  dfuzzer \
    -n org.freedesktop.FileManager1 \
    -o /org/freedesktop/FileManager1 \
    -I 50 \
    -v || rc=$?

printf '%s\n' "::group::backend log after fuzz"
cat -- "${backend_log}" 2>/dev/null || true
printf '%s\n' "::endgroup::"

printf 'dfuzzer raw exit code: %s\n' "${rc}"
exit "${rc}"
INNER
chmod +x "${inner}"

printf '%s\n' "::group::dfuzzer (org.freedesktop.FileManager1, ${dfuzzer_seconds}s)"
rc=0
dbus-run-session -- "${inner}" "${work}/fm-shim-backend" "${dfuzzer_seconds}" || rc=$?
printf '%s\n' "::endgroup::"
printf 'dfuzzer wrapper exit code: %s\n' "${rc}"

case "${rc}" in
  0)
    printf '%s\n' "dfuzzer: completed cleanly; no crashes / exceptions detected."
    ;;
  124)
    ## 'timeout --preserve-status' surfaces 124 when the wall-
    ## clock budget is reached. Treat as 'budget reached, no
    ## crash detected within window'.
    printf '%s\n' "dfuzzer: ${dfuzzer_seconds}s budget reached; no crash detected within window."
    rc=0
    ;;
  *)
    printf '::error::%s\n' "dfuzzer reported a finding (exit ${rc}). See log above for the failing method."
    ;;
esac

exit "${rc}"
