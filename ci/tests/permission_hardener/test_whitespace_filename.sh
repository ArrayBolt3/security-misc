#!/bin/bash
## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## WARNING: Not human-reviewed, MUST be moved to dist-ai.

## Regression test: permission-hardener must parse a config filename that
## contains spaces.
##
## load_state() recovers the filename by reading the option fields from the
## right (a trailing whitelist keyword, or the mode/owner/group[/capability]
## tail anchored by the octal mode). A space in the filename must NOT split it
## into the wrong fields -- that drops the entry silently, leaving a SUID
## binary un-hardened.
##
## Drives the REAL script via 'print-policy' with a mode-form entry
## (<filename> <mode> <owner> <group>) whose filename contains a space, and
## asserts the recovered filename appears in the printed policy.
##
## Requires root: writes a temporary config under /etc/permission-hardener.d/
## and needs helper-scripts installed (sourced by permission-hardener).

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
export LC_ALL=C

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
ph_bin="${PERMISSION_HARDENER_BIN:-${repo_root}/usr/bin/permission-hardener#security-misc-shared}"

if [ ! -f "${ph_bin}" ]; then
  printf '%s\n' "FAIL: permission-hardener not found at '${ph_bin}'." >&2
  exit 1
fi

test_dir="$(mktemp -d -t ph-ws-test.XXXXXX)"
## The space in the directory name is the property under test.
spaced_file="${test_dir}/some space/binary"
mkdir -p -- "${test_dir}/some space"
touch -- "${spaced_file}"

## A filename whose space-split yields a BARE octal chunk ('744'). The mode
## must be anchored from the RIGHT: a left-to-right scan anchors on that chunk
## instead of the real mode at the end, fails the field-count check, and aborts
## the whole hardener (exit 200) rather than parsing the entry.
octal_chunk_file="${test_dir}/a 744 name"
touch -- "${octal_chunk_file}"

## A SPACED filename whose second component (field index 1) is a bare octal, with
## a 3-field tail. Field 1 is NOT the mode, so recovery must happen: the spaced
## name exists, its no-recovery prefix does not.
octal_second_file="${test_dir}/a 744"
touch -- "${octal_second_file}"

config_dir="/etc/permission-hardener.d"
config_file="${config_dir}/zz-ai-whitespace-regression-test.conf"
mkdir -p -- "${config_dir}"

## print-policy captures each file's current mode into this DB (must match
## store_dir in the script under test); remove the entries so a test run does
## not leave stale root-owned overrides pointing at deleted temp files.
existing_mode_admindir='/var/lib/permission-hardener-v2/existing_mode'

## invoked indirectly via 'trap ... EXIT'
# shellcheck disable=SC2317
cleanup() {
  local leaked_file
  for leaked_file in "${spaced_file}" "${octal_chunk_file}" \
    "${octal_second_file}"; do
    dpkg-statoverride --admindir "${existing_mode_admindir}" --remove \
      "${leaked_file}" >/dev/null 2>&1 || true
  done
  safe-rm -f -- "${config_file}"
  safe-rm -rf -- "${test_dir}"
}
trap cleanup EXIT

## mode-form entries: <filename> <mode> <owner> <group> [capability]
{
  printf '%s\n' "${spaced_file} 0744 root root"
  printf '%s\n' "${octal_chunk_file} 0744 root root"
  printf '%s\n' "${octal_second_file} 0644 root root"
} > "${config_file}"

## A parse failure on any line aborts the whole run with exit 200; capture the
## status via an 'if' condition (errexit stays enabled) so the failure is
## reported cleanly rather than aborting the test.
if policy_output="$( "${ph_bin}" print-policy 2>/dev/null )"; then
  ph_rc=0
else
  ph_rc=$?
fi

test_status=0
if [ "${ph_rc}" -ne 0 ]; then
  printf '%s\n' "FAIL: print-policy exited ${ph_rc} (parse aborted the whole run)." >&2
  test_status=1
fi
## print-policy prints tab-separated columns (File<TAB>User<TAB>...), so match
## each filename as the whole first field (trailing TAB). A bare substring match
## would let '/a 744' spuriously match the '/a 744 name' entry.
for expected_file in "${spaced_file}" "${octal_chunk_file}" "${octal_second_file}"; do
  if grep --quiet --fixed-strings -- "${expected_file}"$'\t' <<< "${policy_output}"; then
    printf '%s\n' "PASS: filename '${expected_file}' parsed and present in policy."
  else
    printf '%s\n' "FAIL: filename '${expected_file}' missing from print-policy output." >&2
    test_status=1
  fi
done

if [ "${test_status}" -ne 0 ]; then
  printf '%s\n' "----- print-policy output -----" >&2
  printf '%s\n' "${policy_output}" >&2
fi
exit "${test_status}"
