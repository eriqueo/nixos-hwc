# Recyclarr Sync Workflow

Declarative wiring for Recyclarr now lives in `domains/server/containers/recyclarr/`. The module renders configuration on demand, runs the container with `podman`, and keeps secrets in Agenix so the service can rotate cleanly.

## What the Module Does
- Regenerates `/opt/downloads/recyclarr/config/{recyclarr.yml,secrets.yml}` on every `recyclarr-sync.service` run via a `writeShellScript` ExecStartPre.
- Targets Sonarr `http://localhost:8989/sonarr`, Radarr `http://localhost:7878/radarr`, and Lidarr `http://localhost:8686/lidarr`, matching the URL bases set in each container.
- Aligns with Recyclarr ≥ 8 by using `assign_scores_to` for custom formats and pruning the deprecated Dolby Vision/EVO IDs that no longer ship in the TRaSH HD‑1080p guides.
- Pulls API keys from `/run/agenix/{sonarr,radarr,lidarr}-api-key` and writes them into `secrets.yml` with `640` permissions.
- Executes `podman run --network=host ghcr.io/recyclarr/recyclarr:latest sync` so Recyclarr sees the same `localhost` bindings as the *arr apps.

## Prerequisites
- Agenix secrets:
  - `domains/secrets/parts/server/sonarr-api-key.age`
  - `domains/secrets/parts/server/radarr-api-key.age`
  - `domains/secrets/parts/server/lidarr-api-key.age` (optional)
- Sonarr/Radarr/Lidarr containers exported on localhost with URL base set to `/sonarr`, `/radarr`, `/lidarr`.
- `hwc.server.containers.recyclarr.enable = true` in the server profile.

## Rotating API Keys
1. Fetch the new API key from the *arr UI.
2. Re-encrypt the secret (`nix run github:ryantm/agenix -- -e domains/secrets/parts/server/sonarr-api-key.age`, etc.).
3. `sudo nixos-rebuild switch --flake .#hwc-server`.
4. `sudo systemctl start recyclarr-sync.service` to confirm the updated key works.

## Manual Sync & Logs
- Run once: `sudo systemctl start recyclarr-sync.service`.
- Follow output: `journalctl -fu recyclarr-sync.service`.
- Generated config lives in `/opt/downloads/recyclarr/config/`. Remove it if you need a clean slate; the ExecStartPre script will recreate it on the next run.

## Troubleshooting Tips
- `curl -H "X-Api-Key:$(sudo cat /run/agenix/sonarr-api-key)" http://localhost:8989/sonarr/api/v3/system/status` should return HTTP 200. Repeat for Radarr/Lidarr.
- If the service fails immediately, check for stale config (`cat /opt/downloads/recyclarr/config/recyclarr.yml`) to verify the rendered base URLs and keys.
- Ensure `podman ps` shows the *arr containers exposing `127.0.0.1` ports; Recyclarr relies on host networking rather than the media podman network.
