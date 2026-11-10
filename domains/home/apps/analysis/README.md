# analysis

## Purpose
Installs a single Python 3 environment for data analysis: Polars, JupyterLab, pandas, numpy, pyarrow, plus anything in `extraPackages`. Enable via `hwc.home.apps.analysis.enable`.

## Boundaries
- ✅ One `python3.withPackages` env in `home.packages`.
- ❌ Does not configure Jupyter server settings, kernels, or notebooks; no data paths or services.

## Structure
- `index.nix` — enable/extraPackages options and the Python environment.

## Changelog
- 2026-11-09: Remove the empty system-lane placeholder and unused assertion scaffolding; keep the Home Manager Python environment.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
