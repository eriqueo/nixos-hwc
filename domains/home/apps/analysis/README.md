# analysis

## Purpose
Installs a single Python 3 environment for data analysis: Polars, JupyterLab, pandas, numpy, pyarrow, plus anything in `extraPackages`. Enable via `hwc.home.apps.analysis.enable`.

## Boundaries
- ✅ One `python3.withPackages` env in `home.packages`; a placeholder system lane (`hwc.system.apps.analysis.enable` in `sys.nix`, currently installs nothing).
- ❌ Does not configure Jupyter server settings, kernels, or notebooks; no data paths or services.

## Structure
- `index.nix` — options (`enable`, `extraPackages`) and the Python env install.
- `sys.nix` — system-lane stub option (`hwc.system.apps.analysis.enable`); empty `environment.systemPackages`.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
