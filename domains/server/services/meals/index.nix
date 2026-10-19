# Independent meal application; wall-display owns only its calendar projection.
# The sibling wall-display/index.nix cannot own this CRITICAL application store.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.server.services.meals;
  state = "${config.hwc.paths.state}/meals";
  app = inputs.meals.packages.${pkgs.system}.default;
  domain = config.hwc.networking.shared.vhostDomain;
  settings = pkgs.writeText "meals.json" (builtins.toJSON {
    inherit (cfg) port writesEnabled;
    timeZone = config.time.timeZone;
    database = "${state}/meals.db";
    baseUrl = cfg.url;
    groceriesUrl = "https://todo.${domain}/groceries";
    areas = config.hwc.business.workbench.registry;
    converter = { inherit (config.hwc.server.ai.dx2) baseUrl model apiKeyFile; modelIdentity = cfg.cookingModelIdentity; };
    cookingPromotion = cfg.cookingPromotion;
    gatewayUrl = "http://127.0.0.1:${toString config.hwc.system.mcp.port}/mcp";
  });
  command = "${app}/bin/hwc-meals --config ${settings}";
  # Provision only the new Meals collection. Existing Groceries is never created
  # or renamed here; the scoped gateway verifies both display names on every call.
  provision = pkgs.writeShellScript "meals-collection" ''
    set -eu
    url=http://127.0.0.1:${toString config.hwc.server.services.radicale.port}${cfg.collections.meals.href}
    code=$(${pkgs.curl}/bin/curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -X PROPFIND -H 'Depth: 0' "$url")
    if [ "$code" = 404 ]; then
      ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 10 -X MKCALENDAR \
        -H 'Content-Type: application/xml' --data '${builtins.replaceStrings [ "'" ] [ "&apos;" ] ''<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:set><D:prop><D:displayname>${lib.escapeXML cfg.collections.meals.name}</D:displayname><C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set></D:prop></D:set></C:mkcalendar>''}' "$url"
    elif [ "$code" != 207 ]; then
      echo "Meals collection is unavailable (HTTP $code)" >&2
      exit 1
    fi
  '';
in {
  # OPTIONS
  options.hwc.server.services.meals = {
    enable = lib.mkEnableOption "reviewed recipes, dinners and shared groceries";
    port = lib.mkOption { type = lib.types.port; default = 8425; description = "Loopback Meals HTTP port."; };
    writesEnabled = lib.mkOption { type = lib.types.bool; default = false; description = "Allow reviewed effects; keep false during restore and initial acceptance."; };
    cookingModelIdentity = lib.mkOption { type = lib.types.str; default = "unverified"; description = "Immutable provider model identity for recipe evaluation. A generic alias cannot enable schema-3 saving."; };
    cookingPromotion = lib.mkOption { type = lib.types.nullOr (lib.types.attrsOf lib.types.anything); default = null; description = "Operator-owned evaluation receipt bound to the exact shipped engine, prompt and model. Null keeps the new cooking engine in preview."; };
    url = lib.mkOption { type = lib.types.str; readOnly = true; default = "https://meals.${domain}"; description = "Canonical planner URL."; };
    collections = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { options = {
        href = lib.mkOption { type = lib.types.strMatching "/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/"; description = "Exact collection path."; };
        name = lib.mkOption { type = lib.types.str; description = "Expected display name; mismatch refuses writes."; };
      }; });
      default = { groceries = { href = "/eric/groceries/"; name = "Groceries"; }; meals = { href = "/eric/meals/"; name = "Meals"; }; };
      description = "Exact meal effect targets; no display-name fallback.";
    };
  };
  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    hwc.system.mcp.mealCollections = cfg.collections;
    hwc.networking.shared.routes = [{ name = "meals"; mode = "vhost"; upstream = "http://127.0.0.1:${toString cfg.port}";
      # Meals validates IP addresses; the common proxy default includes a port.
      headers."X-Forwarded-For" = "{remote_host}"; }];
    systemd.services.meals = {
      description = "Household recipes and reviewed meal planning";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "radicale.service" "hwc-sys-mcp.service" ];
      wants = [ "network-online.target" ];
      requires = [ "radicale.service" "hwc-sys-mcp.service" ];
      preStart = "${provision}\n${command} --check";
      serviceConfig = {
        ExecStart = command;
        User = lib.mkForce "eric"; Group = "users";
        # CRITICAL: recipes, revisions and receipts retained indefinitely, 1 GiB
        # admission cap. SQLite backup below joins Borg; never delete user records.
        StateDirectory = "hwc/meals"; StateDirectoryMode = "0700";
        Restart = "on-failure"; RestartSec = 10; TimeoutStopSec = 50;
        ProtectSystem = "strict"; ProtectHome = true; PrivateTmp = true;
        NoNewPrivileges = true; MemoryMax = "512M"; TasksMax = 64;
      };
    };
    # AUTO-MANAGED previews expire after seven days. The same application policy
    # runs independently of request traffic; no second retention implementation.
    systemd.services.meals-cleanup = {
      serviceConfig = { Type = "oneshot"; User = lib.mkForce "eric"; Group = "users"; ExecStart = "${command} --cleanup"; };
    };
    systemd.timers.meals-cleanup = { wantedBy = [ "timers.target" ]; timerConfig = { OnCalendar = "daily"; Persistent = true; }; };
    # One compressed consistent snapshot, replaced atomically before each Borg
    # archive. Historical retention belongs only to Borg's existing policy.
    hwc.data.borg.preBackupScript = lib.mkAfter ''
      ${pkgs.util-linux}/bin/runuser -u eric -- ${command} --backup ${state}/snapshot.next
      ${pkgs.gzip}/bin/gzip -c ${state}/snapshot.next > /var/lib/backups/meals.db.next.gz
      mv /var/lib/backups/meals.db.next.gz /var/lib/backups/meals.db.gz
      rm ${state}/snapshot.next
    '';
    # SQLite opens its WAL during online backup; this narrow exception lets the
    # existing root backup service use SQLite's consistent snapshot API.
    services.borgbackup.jobs.hwc-backup.readWritePaths = [ state ];
    # VALIDATION
    assertions = [
      { assertion = config.hwc.server.services.radicale.enable && config.hwc.system.mcp.enable; message = "Meals needs local Radicale and the scoped MCP gateway."; }
      { assertion = config.hwc.data.borg.enable; message = "Meals CRITICAL state requires Borg backup."; }
      { assertion = cfg.collections ? groceries && cfg.collections ? meals; message = "Meals needs exact groceries and meals collections."; }
    ];
  };
}
