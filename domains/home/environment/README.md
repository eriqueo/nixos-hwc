# Home Environment

## Purpose
Shell environment, aliases, development tooling, and user scripts.

## Boundaries
- Manages: Shell config (zsh, starship), environment variables, dev tools, shell aliases, user scripts
- Does NOT manage: System shell, app-specific configs (those live in `domains/home/apps/`)

## Structure
```
environment/
├── index.nix     # Environment aggregator
├── README.md     # This file
├── shell/        # Shell configuration (zsh, aliases, functions)
│   └── index.nix # Shell aliases, functions (add-app, graph, photo-dedup)
├── parts/        # Environment components
│   └── development.nix  # Dev tools, PROJECTS/WORKSPACE env vars
└── scripts/      # User-facing script modules
    └── transcript-formatter.nix  # Obsidian transcript formatter
```

### Workspace References

Shell aliases and functions reference these workspace paths:
- `workspace/nixos-dev/add-home-app.sh` — `add-app` shell function
- `workspace/nixos-dev/graph/hwc_graph.py` — `graph` shell function
- `workspace/home/photo-dedup/photo-dedup.sh` — `photo-dedup` alias
- `workspace/media/youtube-services/transcript-formatter/` — transcript-formatter script

Environment variables set in `parts/development.nix`:
- `PROJECTS` → `$HOME/.nixos/workspace`
- `SCRIPTS` → `$HOME/.nixos/workspace`
- `WORKSPACE` → `$HOME/.nixos/workspace`

## Changelog
- 2026-03-26: Updated workspace path references after domain-aligned restructure (nixos/ → nixos-dev/, utilities/photo-dedup → home/photo-dedup, youtube-services/ → media/youtube-services/)
- 2026-02-28: Added README for Charter Law 12 compliance
