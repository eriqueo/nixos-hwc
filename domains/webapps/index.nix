# domains/webapps/index.nix
#
# Web Apps Hosting Domain
# NAMESPACE: hwc.webapps.*
#
# Manages a reserved port range (14000–14099) on the Tailscale interface for
# quickly publishing static web apps (HTML, React, etc.) without NixOS rebuilds.
#
# Architecture:
#   - Caddy picks up per-app config via:  import /opt/webapps/*/Caddyfile
#   - Each app gets its own subdirectory:  /opt/webapps/<name>/
#   - `hwc-publish` script handles deploy/list/remove + `systemctl reload caddy`
#   - Port assignments are tracked by the Caddyfiles themselves (no manifest needed)
#
# Workflow:
#   hwc-publish my-tool ./dist/           # auto-assigns next free port, copies files
#   hwc-publish my-tool index.html        # single-file deploy
#   hwc-publish --list                    # show all running apps + URLs
#   hwc-publish --remove my-tool          # undeploy + reload
#   hwc-publish --port 14005 my-tool ./   # explicit port
#
# One rebuild to set up. Every deploy after that is instant.
#

{ config, lib, pkgs, ... }:

let
  cfg  = config.hwc.webapps;
  root = config.hwc.networking.shared.rootHost or "localhost";

  # hwc-publish: deploy/manage static web apps on the reserved port range
  hwcPublish = pkgs.writeShellApplication {
    name = "hwc-publish";

    runtimeInputs = with pkgs; [
      coreutils   # mkdir, cp, rm, cat, basename, dirname, seq
      rsync       # directory sync
      gnugrep     # grep -oP
      gnused      # sed (unused but handy)
    ];

    text = ''
      WEBAPPS_DIR="${cfg.baseDir}"
      PORT_START="${toString cfg.portRange.start}"
      PORT_END="${toString cfg.portRange.end}"
      CADDY_DOMAIN="${root}"

      usage() {
        cat <<'EOF'
      hwc-publish — deploy a static web app to Tailscale HTTPS

      Usage:
        hwc-publish <name> <source>             Deploy app (auto-assign port)
        hwc-publish <name> <source> --port N    Deploy on specific port
        hwc-publish --list                      Show all deployed apps + URLs
        hwc-publish --remove <name>             Remove an app and reload Caddy

      Examples:
        hwc-publish tile-calc ./dist/
        hwc-publish scratch   index.html
        hwc-publish my-tool   ./build/ --port 14007
        hwc-publish --list
        hwc-publish --remove tile-calc
      EOF
        exit 1
      }

      list_apps() {
        local found=0
        printf "\n%-6s  %-24s  %s\n" "PORT" "NAME" "URL"
        printf "%-6s  %-24s  %s\n" "------" "------------------------" "---"
        for caddyfile in "$WEBAPPS_DIR"/*/Caddyfile; do
          [ -f "$caddyfile" ] || continue
          found=1
          port=$(grep -oP ":\K[0-9]+" "$caddyfile" | head -1)
          name=$(basename "$(dirname "$caddyfile")")
          printf "%-6s  %-24s  https://%s:%s\n" "$port" "$name" "$CADDY_DOMAIN" "$port"
        done
        [ "$found" -eq 1 ] || echo "(no apps deployed)"
        echo ""
      }

      next_free_port() {
        local used
        used=$(grep -rh "$CADDY_DOMAIN:" "$WEBAPPS_DIR"/*/Caddyfile 2>/dev/null \
               | grep -oP ':\K[0-9]+' | sort -n || true)
        local port
        for port in $(seq "$PORT_START" "$PORT_END"); do
          if ! echo "$used" | grep -qx "$port"; then
            echo "$port"
            return
          fi
        done
        echo "ERROR: No free ports in range $PORT_START–$PORT_END" >&2
        exit 1
      }

      deploy_app() {
        local name="$1"
        local source="$2"
        local port="$3"
        local app_dir="$WEBAPPS_DIR/$name"

        # Validate name (safe filesystem identifier)
        if [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
          echo "ERROR: Name must only contain letters, numbers, hyphens, underscores" >&2
          exit 1
        fi

        # Source must exist
        if [ ! -e "$source" ]; then
          echo "ERROR: Source '$source' not found" >&2
          exit 1
        fi

        # Auto-assign port if not specified
        if [ -z "$port" ]; then
          port=$(next_free_port)
        fi

        echo "→ Deploying '$name' on port $port..."

        # Create app directory
        mkdir -p "$app_dir"

        # Copy source (directory or single file)
        if [ -d "$source" ]; then
          rsync -a --delete --exclude="Caddyfile" "$source"/ "$app_dir/"
        else
          cp "$source" "$app_dir/"
        fi

        # Write per-app Caddyfile
        cat > "$app_dir/Caddyfile" <<CADDYEOF
      $CADDY_DOMAIN:$port {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
        }
        encode zstd gzip

        root * $app_dir
        file_server

        # SPA fallback
        try_files {path} /index.html

        # Cache: immutable hashed assets
        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"
      }
      CADDYEOF

        # Hot-reload Caddy (no restart needed)
        echo "→ Reloading Caddy..."
        sudo systemctl reload caddy

        echo ""
        echo "✓  https://$CADDY_DOMAIN:$port"
      }

      remove_app() {
        local name="$1"
        local app_dir="$WEBAPPS_DIR/$name"

        if [ ! -d "$app_dir" ]; then
          echo "ERROR: App '$name' not found in $WEBAPPS_DIR" >&2
          exit 1
        fi

        echo "→ Removing '$name'..."
        rm -rf "$app_dir"
        echo "→ Reloading Caddy..."
        sudo systemctl reload caddy
        echo "✓  '$name' removed"
      }

      # ── Argument dispatch ──────────────────────────────────────────────────
      case "''${1:-}" in
        --list|-l)
          list_apps
          ;;
        --remove|-r)
          [ -n "''${2:-}" ] || usage
          remove_app "$2"
          ;;
        --help|-h|"")
          usage
          ;;
        *)
          name="$1"
          source="''${2:-}"
          [ -n "$source" ] || usage
          port=""
          if [ "''${3:-}" = "--port" ]; then
            port="''${4:-}"
            [ -n "$port" ] || { echo "ERROR: --port requires a value" >&2; usage; }
          fi
          deploy_app "$name" "$source" "$port"
          ;;
      esac
    '';
  };

in {

  imports = [
    ./estimator/index.nix
  ];

  # ── OPTIONS ───────────────────────────────────────────────────────────────
  options.hwc.webapps = {
    enable = lib.mkEnableOption "Web app hosting system (hwc-publish + port range)";

    baseDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/opt/webapps";
      description = "Base directory for deployed web apps. Each app gets a subdirectory.";
    };

    portRange = {
      start = lib.mkOption {
        type        = lib.types.port;
        default     = 14000;
        description = "First port in the reserved web app range.";
      };
      end = lib.mkOption {
        type        = lib.types.port;
        default     = 14099;
        description = "Last port in the reserved web app range (inclusive).";
      };
    };
  };

  # ── IMPLEMENTATION ────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {

    # Deploy hwc-publish to system PATH
    environment.systemPackages = [ hwcPublish ];

    # Create base directory (eric-owned so hwc-publish can write without sudo)
    systemd.tmpfiles.rules = [
      "d ${cfg.baseDir} 0755 eric users -"
    ];

    # Tell Caddy to pick up all per-app Caddyfiles automatically
    # systemctl reload caddy is all that's needed to activate a new app
    services.caddy.extraConfig = lib.mkAfter ''

      # hwc-publish managed apps — dynamically loaded, no rebuild needed
      import ${cfg.baseDir}/*/Caddyfile
    '';

    # Reserve the full port range on the Tailscale interface
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.range cfg.portRange.start cfg.portRange.end;
  };
}
