#!/bin/bash
## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Compile and run the build_input_path regression test under
## AddressSanitizer + UndefinedBehaviorSanitizer.
##
## See ci/tests/emerg_shutdown/test_input_path.c for what it asserts.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${test_dir}/../../.." && pwd)"
src="${repo_root}/usr/src/security-misc/emerg-shutdown.c#security-misc-shared"

if [ ! -f "${src}" ]; then
  printf '%s\n' "FAIL: source not found at '${src}'" >&2
  exit 1
fi

## style-ok: no-safe-rm
## Runs on a bare GitHub runner without helper-scripts, so safe-rm is absent;
## the target is always our own mktemp -d dir, never a blocklisted path.
build_dir="$(mktemp -d -t emerg-shutdown-test.XXXXXX)"
# shellcheck disable=SC2317
cleanup() {
  rm -rf -- "${build_dir}"
}
trap cleanup EXIT

## The genmkfile '#security-misc-shared' suffix makes gcc misclassify the file
## by extension, so expose it under a clean '.c' name on the include path. The
## test includes the whole translation unit (-DEMERG_SHUTDOWN_NO_MAIN drops
## main()), so it exercises the real daemon code, not a copy. Absolute symlink
## target resolves regardless of cwd.
ln -s -- "${src}" "${build_dir}/emerg-shutdown.c"

bin="${build_dir}/test_input_path"
## No -std: match the production compile (compile-emerg-shutdown sets none, so
## gcc's default gnu dialect enables the POSIX/GNU symbols the daemon uses).
gcc \
  -g -O1 \
  -Wall -Wextra \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I "${build_dir}" \
  -o "${bin}" \
  "${test_dir}/test_input_path.c"

## detect_leaks=0: this test guards buffer bounds, not leaks, and LeakSanitizer
## cannot initialize under a ptrace-restricted sandbox. The out-of-bounds write
## detection (the actual regression guard) is unaffected.
ASAN_OPTIONS='abort_on_error=1:detect_leaks=0' \
UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
  "${bin}"
