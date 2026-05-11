<!--
Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
See the file COPYING for copying conditions.

AI-Assisted
-->

# Fuzzing

## Hypothesis property tests

Property tests live at `ci/tests/<pkg>/test_property.py` (mirroring
the helper-scripts layout). **Outside** the Python package tree on
purpose: `debian/security-misc-shared.install` ships
`usr/lib/python3/dist-packages/fm_shim_frontend/...`, so keeping the
property tests under `ci/tests/` means they don't end up in the
installed `.deb`.

Currently covered:

- `ci/tests/fm_shim_frontend/test_property.py` - Hypothesis
  property tests over `get_path_list_from_uris`, the URI-validation
  chokepoint between the FileManager1 D-Bus surface and the user-
  facing dialog. Six properties (`never_raises`,
  `output_paths_absolute`, `output_no_dangerous_chars`,
  `output_unique_and_sorted`, `idempotent`, plus a deterministic
  regression-suite of nine adversarial inputs).

  At introduction this suite found an exploitable bug: an attacker
  who can deliver a URI with a single path component longer than
  NAME_MAX (255 bytes on Linux) crashed the process via an
  uncaught `OSError(ENAMETOOLONG)` from `Path.exists()`. Fixed in
  the same commit that added the suite.

Test runner: `.github/workflows/lint-python.yml` runs flake8
followed by `python3 -m pytest` against `ci/tests/<pkg>/`. apt-
installs `python3-pytest`, `python3-hypothesis`, plus PyQt5
runtime deps required for the source under test to import.

`ci/tests/<pkg>/conftest.py` stubs out `stdisplay` (helper-scripts
package, not on PyPI / not in apt for the runner) with an identity
function, and stubs PyQt5.QtCore/Gui/Widgets so that the Qt class
inheritance at module level (`class FmShimWindow(QDialog)`) works
without a real display.

Local run (single package):

```
PYTHONPATH=usr/lib/python3/dist-packages python3 -m pytest \
  --import-mode=importlib -q \
  ci/tests/fm_shim_frontend/test_property.py
```

When adding a new package, mirror the same structure:
`ci/tests/<pkg>/{test_property.py,conftest.py}`. Keep at least
two properties: `test_never_raises` and one domain-specific
invariant.

## ClusterFuzzLite (Atheris / libFuzzer)

Not yet wired up. Helper-scripts has the full
`.clusterfuzzlite/{Dockerfile,build.sh,project.yaml}` +
`fuzz/fuzz_<pkg>.py` setup; mirror that here when the property-
test suite has been running long enough to catch the easy wins
and the harder, coverage-guided layer is justified.

## Trust footprint

- Hypothesis: Debian apt (`python3-hypothesis`).
- pytest: Debian apt (`python3-pytest`).
- PyQt5 + sip: Debian apt (`python3-pyqt5` + `python3-pyqt5.sip`).
- ClusterFuzzLite + Atheris (when added): Google. Per-pin
  provenance will live in the future
  `.clusterfuzzlite/Dockerfile`.
