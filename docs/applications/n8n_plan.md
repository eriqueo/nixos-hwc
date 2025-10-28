Below is an implementation plan to migrate **n8n** from your **laptop Home Manager app** to a **server-side Podman container**, fronted by **Caddy** with **Tailscale TLS**, so you can access and modify it from laptop/phone without keeping your laptop awake.

Your repo currently defines n8n as a Home Manager app (package + env vars) under `domains/home/apps/n8n/` and toggles it via `hwc.home.apps.n8n.enable` (default `false`) in `profiles/home.nix`.

---

# Implementation Plan (server)

## 1) Server NixOS: run n8n via Podman

Create a server module (or add to your server host config) to run n8n as a container bound to localhost. Volumes persist data at `/var/lib/n8n`. Caddy will reverse proxy it.

```
{ config, pkgs, lib, ... }:

{
  virtualisation.oci-containers.backend = "podman";

  systemd.tmpfiles.rules = [
    "d /var/lib/n8n 0750 node node -"
  ];

  users.users.node = {
    isSystemUser = true;
    group = "node";
    home = "/var/lib/n8n";
    shell = pkgs.bashInteractive;
  };
  users.groups.node = {};

  virtualisation.oci-containers.containers.n8n = {
    image = "docker.io/n8nio/n8n:latest";
    autoStart = true;
    ports = [ "127.0.0.1:5678:5678" ];
    volumes = [
      "/var/lib/n8n:/home/node/.n8n"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      N8N_HOST = "n8n.${config.networking.hostName}.ts.net";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "https";
      N8N_EDITOR_BASE_URL = "https://n8n.${config.networking.hostName}.ts.net";
      WEBHOOK_URL = "https://n8n.${config.networking.hostName}.ts.net/";
      N8N_ENCRYPTION_KEY = "@n8n_encryption_key@";
      N8N_PERSONALIZATION_ENABLED = "false";
      N8N_DIAGNOSTICS_ENABLED = "false";
      N8N_TELEMETRY_ENABLED = "false";

      DB_TYPE = "postgresdb";
      DB_POSTGRESDB_HOST = "127.0.0.1";
      DB_POSTGRESDB_PORT = "5432";
      DB_POSTGRESDB_DATABASE = "n8n";
      DB_POSTGRESDB_USER = "n8n";
      DB_POSTGRESDB_PASSWORD = "@n8n_db_password@";
    };
  };
}
```

Notes:

* Secrets (`@…@`) should be replaced via your current secret system; long-term you plan to migrate to **agenix**.
* Binding to `127.0.0.1` ensures only Caddy can reach the container.

## 2) PostgreSQL on the server (managed by Nix)

Use Postgres (not SQLite) for reliability and backups:

```
{ config, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "n8n" ];
    ensureUsers = [{
      name = "n8n";
      ensureDBOwnership = true;
      # password will be set from a file or via psql on first deploy
    }];
    authentication = pkgs.writeText "pg_hba.conf" ''
      local   all             all                                     peer
      host    n8n             n8n             127.0.0.1/32            md5
    '';
  };
}
```

If you prefer a one-time manual set, after deploy:

```
psql -U postgres -c "ALTER USER n8n WITH PASSWORD '<REPLACE>'; GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;"
```

## 3) Caddy reverse proxy with Tailscale TLS

Expose `https://n8n.<your-hostname>.ts.net` without opening the LAN:

```
{
  services.caddy.enable = true;

  services.caddy.virtualHosts."n8n.${config.networking.hostName}.ts.net".extraConfig = ''
    tls {
      get_tailscale_cert n8n
    }
    reverse_proxy 127.0.0.1:5678
  '';
}
```

Subpath is also possible by setting `N8N_PATH` and rewriting paths; the above uses a subdomain for simplicity.

## 4) Secrets

Near-term (SOPS) or later (agenix). Example with agenix variables wired into the container env values:

```
{
  age.secrets.n8n_encryption_key.file = /etc/secrets/n8n_encryption_key.age;
  age.secrets.n8n_db_password.file    = /etc/secrets/n8n_db_password.age;

  systemd.services.podman-n8n.serviceConfig.EnvironmentFile = lib.mkForce "/run/agenix/n8n.env";
}
```

Where `/run/agenix/n8n.env` is generated from your age secrets into:

```
N8N_ENCRYPTION_KEY=...
DB_POSTGRESDB_PASSWORD=...
```

(Adopt this once you finish the agenix migration.)

## 5) Backups

Back up both the DB and app data:

```
{
  systemd.services."backup-n8n" = {
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      ts=$(date +%Y%m%d-%H%M%S)
      pg_dump -U postgres n8n > /var/backups/n8n/db-$ts.sql
      rsync -a --delete /var/lib/n8n/ /var/backups/n8n/data/
    '';
  };

  systemd.timers."backup-n8n" = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
    timerConfig.Persistent = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/backups/n8n 0750 root root -"
    "d /var/backups/n8n/data 0750 root root -"
  ];
}
```

## 6) Laptop: disable the Home Manager n8n

Keep your laptop free of the always-on n8n. Ensure `hwc.home.apps.n8n.enable = false` (it’s already defaulted to false in `profiles/home.nix`), and remove any local autostarting.
Your existing module shows the previous pattern used Home Manager to install the `n8n` package and set env vars—confirm it’s not enabled anywhere else.

## 7) Data migration from laptop

Option A — file copy (quickest if you used SQLite or just want creds/workflows):

```
rsync -avz <laptop>:/home/eric/.n8n/ <server>:/var/lib/n8n/
chown -R node:node /var/lib/n8n
```

Option B — export/import:

```
n8n export:workflow --all --output workflows.json
n8n export:credentials --all --decrypt --output creds.json
# copy to server, then:
n8n import:workflow --input workflows.json
n8n import:credentials --input creds.json
```

Verify environment-specific values (webhook URLs, API keys) after import.

## 8) Smoke tests and cutover

1. `nixos-rebuild switch` on the server.
2. Verify container: `sudo systemctl status podman-n8n.service` and `curl -I http://127.0.0.1:5678`.
3. Verify Caddy route: open `https://n8n.<host>.ts.net` from phone (on Tailscale).
4. In n8n, create a test workflow with a Webhook node. Ensure the URL matches `WEBHOOK_URL`.
5. Update any external integrations to the new Tailscale URL.
6. Keep your **laptop** n8n stopped; use it only for local dev experiments (different port/volume when needed).

## 9) Optional: enable queue mode later

If workflows queue up, add Redis and set:

```
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=127.0.0.1
QUEUE_BULL_REDIS_PORT=6379
```

as container env, and deploy `services.redis.enable = true;`.

---

# Result

* n8n runs 24/7 on the server (Podman), reachable at a stable Tailscale URL with TLS via Caddy.
* Data persisted under `/var/lib/n8n`; DB under PostgreSQL; nightly backups cover both.
* The laptop is free for dev-only containers, exporting/importing JSON when you promote flows.

This aligns with your existing pattern and cleanly replaces the Home Manager app approach you used before.
