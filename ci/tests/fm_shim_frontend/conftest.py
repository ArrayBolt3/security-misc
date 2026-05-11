## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pytest auto-loaded fixture file. Stubs out the heavy module-
## level imports of fm_shim_frontend.fm_shim_frontend so the
## URI-validation function under test (get_path_list_from_uris)
## can be imported and exercised without bringing up Qt or
## installing the helper-scripts Debian package.
##
## Two stubs:
##   * 'stdisplay' (helper-scripts Debian package, not on PyPI):
##     identity stub - the real stdisplay sanitizes terminal-control
##     sequences, but the property tests don't assert on the exact
##     sanitized strings, only on output invariants of the URI list.
##   * 'PyQt5' submodules (heavy optional GUI dep): replaced by a
##     fake-module class whose attribute access returns a fresh
##     'type()'. fm_shim_frontend defines THREE module-level classes
##     that inherit from QObject / QDialog at import time, so a
##     plain MagicMock-backed module would fail because MagicMock
##     instances can't be used as base classes in 'class X(Mock):'.
##     Real type() works.

## TODO: Try to get rid of this file. We can install helper-scripts before
## running the tests to get stdisplay, and as long as the test code paths don't
## call QApplication(), the crash during test issue should be avoidable. Using
## the real modules instead of stubs will make the tests more reliable and
## prevent possible future complications.

import sys
import types


def _stdisplay(text: str, sgr: int = -1) -> str:
    _ = sgr  # unused in stub
    return text


_inner = types.ModuleType("stdisplay.stdisplay")
_inner.stdisplay = _stdisplay
_pkg = types.ModuleType("stdisplay")
_pkg.stdisplay = _stdisplay  ## also exposed on the package for ergonomics

sys.modules.setdefault("stdisplay", _pkg)
sys.modules.setdefault("stdisplay.stdisplay", _inner)


class _FakeQtModule(types.ModuleType):
    """Module whose every attribute access returns a fresh class.

    Lets 'from PyQt5.QtWidgets import QDialog' and
    'class FmShimWindow(QDialog): pass' both succeed at import
    time without a real PyQt5 install.
    """

    def __getattr__(self, name: str) -> type:
        ## Cache the synthesized class so attribute identity is
        ## stable across repeated lookups (PyQt5.QtCore.Qt is the
        ## same object every time, etc.).
        ##
        ## FIXME: This does cache the generated class, but it regenerates it
        ## and clobbers the cache every time it is called thereafter.
        cls = type(name, (object,), {})
        setattr(self, name, cls)
        return cls


for _modname in (
    "PyQt5",
    "PyQt5.QtCore",
    "PyQt5.QtGui",
    "PyQt5.QtWidgets",
    "PyQt5.sip",
):
    sys.modules.setdefault(_modname, _FakeQtModule(_modname))

