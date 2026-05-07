#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## CodeQL pre-init source-tree prep.
##
## This repo names installable files with a '#<package-tag>' suffix
## (Kicksecure/genmkfile convention - the suffix routes the file to the
## correct Debian binary package at build time). CodeQL's Python
## extractor discovers source files by the '.py' extension, so a file
## literally named 'foo.py#security-misc-shared' is invisible to it.
##
## Walk the tracked file list and create same-directory symlinks
## without the '#tag' suffix so the extractor sees the source under
## its conventional name. C source files are NOT touched here - the
## C extractor traces compiler invocations rather than scanning by
## extension, and ci/codeql-build.sh references the original tagged
## paths directly.

set -o errexit
set -o nounset
set -o pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd -- "${repo_root}"

linked=0
skipped=0
while IFS= read -r tagged; do
  ## Only files whose extension portion contains the tag suffix.
  case "${tagged}" in
    *'.py#'*) ;;
    *) continue ;;
  esac

  clean="${tagged%#*}"

  ## Do not clobber a real (untagged) file.
  if [ -e "${clean}" ] && [ ! -L "${clean}" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  ## Symlink target must be relative to the link's directory.
  target="$(basename -- "${tagged}")"
  ln -snf -- "${target}" "${clean}"
  linked=$((linked + 1))
done < <(git ls-files -- '*.py#*')

printf 'codeql-prepare: linked=%d skipped=%d\n' "${linked}" "${skipped}"
