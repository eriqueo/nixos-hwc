# domains/business/estimator/index.nix
#
# Heartwood Estimate Assembler — Static React PWA
# NAMESPACE: hwc.business.estimator.*
#
# Build service reads source from the Nix store, injects secrets at build time,
# and deploys to a versioned directory with atomic symlink swap.
#
# Rebuild:   estimator-build   (shell alias for systemctl start)
# Rollback:  ls /var/lib/estimator/builds/  then  ln -sfn <dir> /var/lib/estimator/dist
#
# Access: https://hwc.ocelot-wahoo.ts.net:13443
#
{ config, lib, pkgs, ... }:
let
  cfg  = config.hwc.business.estimator;
  root = config.hwc.networking.shared.rootHost;

  # ── Source as Nix store input ──────────────────────────────────────────────
  # Filtered copy: excludes node_modules, dist, .env files.
  # Store path changes only when actual source content changes.
  appSource = lib.cleanSourceWith {
    src = ./app;
    name = "estimator-app-source";
    filter = path: _type:
      let name = builtins.baseNameOf path; in
      name != "node_modules"
      && name != "dist"
      && !(lib.hasPrefix ".env" name);
  };

  # ── Build script ───────────────────────────────────────────────────────────
  buildScript = pkgs.writeShellApplication {
    name = "estimator-build";
    runtimeInputs = with pkgs; [ nodejs_20 rsync coreutils findutils ];
    text = ''
      source_dir="${appSource}"
      webhook_url="${cfg.webhookUrl}"
      api_key_file="${cfg.apiKeyFile}"
      workdir="/var/lib/estimator-build/app"
      servedir="/var/lib/estimator"
      builds_dir="$servedir/builds"
      hashfile="/var/lib/estimator-build/.last-build-hash"
      current_link="$servedir/dist"

      # ── 1. Compute input hash ─────────────────────────────────────────
      # Store path encodes source content; webhook URL is the only other input
      input_hash="$(echo "${appSource}|$webhook_url" | sha256sum | cut -d' ' -f1)"

      # ── 2. Early exit if unchanged ────────────────────────────────────
      if [ -f "$hashfile" ] && [ -L "$current_link" ] \
         && [ "$(cat "$hashfile")" = "$input_hash" ]; then
        echo "estimator-build: inputs unchanged, skipping"
        exit 0
      fi

      # ── 3. Sync source from Nix store to writable workdir ─────────────
      mkdir -p "$workdir"
      rsync -a --delete \
        --exclude='node_modules' --exclude='dist' --exclude='.env*' \
        "$source_dir/" "$workdir/"

      # ── 4. Write ephemeral .env.production ────────────────────────────
      api_key="$(cat "$api_key_file")"
      {
        printf 'VITE_WEBHOOK_URL=%s\n' "$webhook_url"
        printf 'VITE_API_KEY=%s\n' "$api_key"
      } > "$workdir/.env.production"

      # ── 5. Install deps (only if lockfile changed) ────────────────────
      lock_hash="$(sha256sum "$workdir/package-lock.json" | cut -d' ' -f1)"
      stored_lock="/var/lib/estimator-build/.lock-hash"
      if [ ! -f "$stored_lock" ] || [ "$(cat "$stored_lock")" != "$lock_hash" ]; then
        echo "estimator-build: lockfile changed, running npm ci"
        HOME="/var/lib/estimator-build" npm ci --prefix "$workdir" --prefer-offline
        echo "$lock_hash" > "$stored_lock"
      else
        echo "estimator-build: deps unchanged, skipping npm ci"
      fi

      # ── 6. Build ──────────────────────────────────────────────────────
      npm run build --prefix "$workdir"

      # ── 7. Versioned deploy with atomic symlink swap ──────────────────
      timestamp="$(date +%Y%m%d-%H%M%S)"
      build_dest="$builds_dir/dist-$timestamp"
      mkdir -p "$builds_dir"
      mv "$workdir/dist" "$build_dest"

      # Bootstrap: if dist exists as a real directory (not symlink), remove it
      if [ -d "$current_link" ] && [ ! -L "$current_link" ]; then
        rm -rf "$current_link"
      fi

      # Atomic symlink: create new link, then rename over old one
      ln -sfn "$build_dest" "$servedir/dist.new"
      mv -T "$servedir/dist.new" "$current_link"

      # Prune: keep last 3 builds
      # shellcheck disable=SC2012
      ls -dt "$builds_dir"/dist-* | tail -n +4 | xargs -r rm -rf

      # ── 8. Clean up secrets ───────────────────────────────────────────
      rm -f "$workdir/.env.production"

      # ── 9. Record hash ───────────────────────────────────────────────
      echo "$input_hash" > "$hashfile"

      echo "estimator-build: deployed $build_dest"
    '';
  };

in {
  # ── OPTIONS ───────────────────────────────────────────────────────────────
  options.hwc.business.estimator = {
    enable = lib.mkEnableOption "Heartwood Estimate Assembler PWA";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 13443;
      description = "Tailscale HTTPS port to expose the app on.";
    };

    webhookUrl = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = "n8n webhook URL injected as VITE_WEBHOOK_URL at build time.";
    };

    apiKeyFile = lib.mkOption {
      type        = lib.types.path;
      description = "Path to file containing the API key (read at build time, baked into bundle).";
      example     = "/run/agenix/estimator-api-key";
    };
  };

  # ── IMPLEMENTATION ────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {
    # Caddy virtual host: serve static files via symlink
    services.caddy.extraConfig = lib.mkAfter ''

      # Heartwood Estimate Assembler — PWA
      ${root}:${toString cfg.port} {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
        }
        encode zstd gzip

        root * /var/lib/estimator/dist
        file_server

        # SPA fallback — all unknown paths serve index.html
        try_files {path} /index.html

        # PWA / cache headers
        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @sw path /sw.js
        header @sw Cache-Control "no-cache"

        header / Cache-Control "no-cache"
      }
    '';

    # Open the port in the firewall (Tailscale interface only)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

    # Build service — manual trigger only
    systemd.services.estimator-build = {
      description = "Build Heartwood Estimator PWA with baked-in secrets";
      after = [ "agenix.service" "network-online.target" ];
      wants = [ "agenix.service" "network-online.target" ];
      # No wantedBy — manual trigger via: systemctl start estimator-build
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${buildScript}/bin/estimator-build";
        Environment = "HOME=/var/lib/estimator-build";
      };
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d /var/lib/estimator 0755 root root -"
      "d /var/lib/estimator/builds 0755 root root -"
      "d /var/lib/estimator-build 0755 root root -"
    ];
  };
}
