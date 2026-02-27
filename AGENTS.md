# AGENTS.md — Minimal Steering for nixos-hwc

## Meta-Rule
If surprised/confused/stuck, flag the issue clearly and suggest a code fix first.
Propose editing this file only as last resort to prevent future agents from the same mistake.

## Active Rules (Proven Error Prevention)

### Tool Usage
- Never use grep, always use rg
- Never use sed - use Edit tool instead
- Always verify machine before nixos-rebuild (`hostname`)

### NixOS-Specific Gotchas
- PGID=100 (NOT 1000) - this is `users` group, not eric's personal group
- Paths are in `domains/paths/paths.nix`, NOT `domains/system/core/paths.nix`
- osConfig access: use `osConfig.hwc or {}` or `attrByPath`, NEVER `osConfig.hwc.x or null`
- Native services need `User = lib.mkForce "eric"` (mkForce is critical)
- Secrets: `group = "secrets"; mode = "0440"` always
- Assertions go INSIDE `config = lib.mkIf ...` block, not as separate `config.assertions`

### Before Any Change
- Read CHARTER.md if touching architecture
- Run `nix flake check` before and after changes
- Namespace must exactly match folder path: `domains/home/apps/X/` → `hwc.home.apps.X.*`

### On Commit (Law 12)
When committing changes to a domain, update that domain's README.md:
- Update `## Structure` if files/folders added/removed/renamed
- Append to `## Changelog`: `- YYYY-MM-DD: [brief description]`
- If README.md missing, create with required sections (Purpose, Boundaries, Structure, Changelog)
