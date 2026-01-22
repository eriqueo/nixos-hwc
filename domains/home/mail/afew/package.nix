{ lib, pkgs, cfg }:
let
  base = if cfg.package != null then cfg.package else pkgs.afew;
in
base.overrideAttrs (old: {
  # Rewrite FilterRegistry to use importlib.metadata entry_points (pkg_resources is deprecated)
  postPatch = (old.postPatch or "") + ''
    python - <<'PY'
from pathlib import Path
path = Path("afew/FilterRegistry.py")
txt = path.read_text()
txt = txt.replace(
    "import pkg_resources\n\nRAISEIT = object()\n",
    "try:\n    from importlib.metadata import entry_points\nexcept ImportError:  # pragma: no cover\n    from importlib_metadata import entry_points  # type: ignore\n\n\ndef _iter_entry_points(group):\n    eps = entry_points()\n    if hasattr(eps, 'select'):\n        return eps.select(group=group)\n    return eps.get(group, [])\n\nRAISEIT = object()\n",
    1,
)
txt = txt.replace("pkg_resources.iter_entry_points('afew.filter')", "_iter_entry_points('afew.filter')", 1)
path.write_text(txt)
PY
  '';
})
