# overlays/pandas-stubs.nix
#
# TEMPORARY (tracked) — upstream nixpkgs breakage, NOT an HWC config issue.
#
# On nixos-unstable rev 624af665 (2026-07-25) python3.14-pandas-stubs fails to build
# in TWO independent phases, both upstream packaging bugs:
#   1. test phase — pytest 9.1.1 promotes `PytestRemovedIn10Warning: Passing a
#      non-Collection iterable to parametrize` to a hard error (exit 2).
#   2. pythonImportsCheck — upstream sets it to ["pandas"], so the build tries to
#      import pandas, which isn't in a stub package's closure → ModuleNotFoundError.
# Either one fails the whole HM user-environment (and thus the system toplevel).
# pandas-stubs is pure type stubs (.pyi files, no runtime code), so skipping both
# checks is safe. It reaches our closure via `python3.withPackages [ pandas … ]`
# in the home apps `analysis` and `scraper` (and the server `home-scout` module),
# and transitively through pdfplumber.
#
# REMOVE WHEN: nixpkgs' pandas-stubs builds again. Check with:
#   nix build 'nixpkgs#python3Packages.pandas-stubs'
# If that succeeds on the pinned nixpkgs, delete this file and its two wire-ins
# in flake.nix (mkPkgs + mkPkgsWithOverlays).
#
# Uses pythonPackagesExtensions so the override applies to every
# `pythonXY.withPackages` env and rebuilds ONLY pandas-stubs, not the package set.
final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pyfinal: pyprev: {
      pandas-stubs = pyprev.pandas-stubs.overridePythonAttrs (_: {
        doCheck = false;            # test phase: pytest-9.1.1 turns a deprecation into a hard error
        pythonImportsCheck = [ ];   # imports check: upstream sets this to ["pandas"], not a dep of pure stubs
      });
    })
  ];
}
