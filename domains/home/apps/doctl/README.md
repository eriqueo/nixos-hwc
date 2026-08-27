# doctl

## Purpose
Ships `doctl`, the DigitalOcean CLI, pre-authenticated from agenix. A Nix wrapper reads the personal access token from `/run/agenix/digitalocean-access-token`, exports `DIGITALOCEAN_ACCESS_TOKEN`, and execs the real `doctl`. The token never reaches `~/.config/doctl/config.yaml`, the shell environment, or shell history. Enable via `hwc.home.apps.doctl.enable`.

## Boundaries
- ✅ The `doctl` wrapper and the `pkgs.doctl` binary behind it.
- ❌ Does not declare the `digitalocean-access-token` secret (`domains/secrets/`) and requires eric in the `secrets` group; does not manage DigitalOcean resources declaratively.

## Structure
- `index.nix` — enable option, secret-reading wrapper, package install.

## Changelog
- 2026-08-26: Module added. `doctl auth init` returned 401 against `cloud.digitalocean.com/v1/oauth/token/info` for a token that same endpoint accepted over curl (doctl 1.160.1), so the config-file auth path was abandoned for an agenix-backed env var. The bare `doctl` package moved here from `domains/home/core/development/` and from `domains/home/apps/dxlog/` to avoid a `bin/doctl` collision.
