# domains/paths — Universal Filesystem Abstraction

## Purpose
`domains/paths/paths.nix` is the canonical source of truth for filesystem paths used across HWC.
It is a **primitive module** (Charter v10.1 Law 10 Primitive Module Exception) intentionally
co-locating options and implementation for simplicity and stability.

## Responsibilities
- Declare `hwc.paths.*` options (storage tiers, PARA structure, app roots).
- Expose environment/session variables (HWC_*).
- Provide minimal bootstrap tmpfiles in system/core/filesystem.nix.
- Validate path absoluteness and invariants.
- Support per-machine recursive overrides via `hwc.paths.overrides`.

## Boundaries
- **Do not** manage dotfiles, templates, or payload. If needed, split into `options.nix` + `index.nix` + `parts/`.
- Tmpfiles: small bootstrap only in `domains/system/core/filesystem.nix`; if tmpfiles grows beyond ~5–10 lines, move fully to filesystem.

## Overrides (preferred)
Use `hwc.paths.overrides` for per-machine customizations. Example:

```nix
{
  hwc.paths.overrides = {
    hot.root = "/mnt/fast-storage";
    media.root = "/mnt/media";
  };
}
```

This is preferred over copy-pasting the whole file on each machine.
