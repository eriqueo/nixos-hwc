# aider

## Purpose
Installs the aider AI pair-programming CLI and generates `~/.aider.conf.yml` with `cloud:`/`local:` model aliases (defaults: `openai/gpt-4o-mini` cloud, `ollama/llama3.2:3b` local via Ollama). Enable via `hwc.home.apps.aider.enable`.

## Boundaries
- ✅ Aider package (auto-detects `aider-chat-full`/`aider-chat`/`aider`, overridable via `package`), `.aider.conf.yml`, `OLLAMA_API_BASE` session var, zsh init that exports `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` from agenix secret files when present on a NixOS host.
- ❌ Does not run Ollama itself (server/AI domain) and does not declare the API-key secrets (`domains/secrets/declarations/`).

## Structure
- `index.nix` — options (`enable`, `package`, `cloudModel`, `localModel`, `ollamaApiBase`, `extraAliases`), package install, YAML config, zsh secret sourcing.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
