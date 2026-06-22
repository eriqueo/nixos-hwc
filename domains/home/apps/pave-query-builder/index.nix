# domains/home/apps/pave-query-builder/index.nix
#
# pave-query-builder — trap-safe Pave (JobTread API) query builder (its own repo
# at ~/600_apps/pave-query-builder, consumed as the `pave-query-builder` flake
# input). This module is a THIN TRANSLATOR: it imports the app's reusable Home
# Manager module and feeds it HWC-specific values, then adds the HWC-only "app"
# wiring — a one-click GraphiQL web shell. The app itself knows nothing about HWC
# (hexagonal: inbound adapter).
#
# Two front-ends, two launcher entries:
#   * "Pave Explorer"      → the GraphiQL web shell (pave-web), read-only. A
#                            systemd user service serves it on localhost; the
#                            launcher starts it on demand and opens the browser.
#   * "Pave Query Builder" → the Textual TUI (pave-query), where mutations live
#                            behind the org guardrail. Hosted in kitty.
#
# NAMESPACE: hwc.home.apps.pave-query-builder.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.pave-query-builder.enable = true;   (set in profiles/desktop)

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.home.apps.pave-query-builder;

  # Hand the app the jt-mcp schema for the introspection fallback + enum
  # validation. Set unconditionally (not pathExists-guarded — that returns false
  # under pure flake eval); the app's schema loader degrades gracefully if the
  # file is absent, so baking the HWC path is safe even on a checkout-less host.
  schemaPath = "${config.home.homeDirectory}/700_datax/jt-mcp/schema_pretty.json";

  # The raw app package (the HM module installs wrapped binaries for PATH use;
  # the systemd service needs an explicit store path + its own env, so reference
  # the package directly rather than the wrapper).
  pavePkg = inputs.pave-query-builder.packages.${pkgs.system}.default;

  # HWC org (same id the MCP server defaults to). The web shell is READ-ONLY by
  # construction, so pointing it at the live org is safe — reads are never gated.
  orgId        = "22Nm3uFevXMb";
  port         = "8787";
  grantKeyPath = "/run/agenix/jobtread-grant-key";  # agenix mount (root:secrets 0440)

  # Service entrypoint: read the grant key at start (never in the nix store),
  # then exec the read-only GraphiQL sidecar bound to localhost.
  pave-web-start = pkgs.writeShellScript "pave-web-start" ''
    set -eu
    if [ ! -r ${grantKeyPath} ]; then
      echo "pave-web: grant key not readable at ${grantKeyPath} (in 'secrets' group?)" >&2
      exit 1
    fi
    export JOBTREAD_GRANT_KEY="$(cat ${grantKeyPath})"
    export JOBTREAD_ORGANIZATION_ID="${orgId}"
    export PAVE_SCHEMA="${schemaPath}"
    exec ${pavePkg}/bin/pave-web --host 127.0.0.1 --port ${port}
  '';

  # Launcher: start the service (idempotent — systemd dedupes), wait for the
  # port to answer, then open the browser. This is what the desktop entry runs.
  pave-web-open = pkgs.writeShellScript "pave-web-open" ''
    set -eu
    ${pkgs.systemd}/bin/systemctl --user start pave-web.service
    for _ in $(seq 1 100); do
      if ${pkgs.curl}/bin/curl -fsS -o /dev/null "http://127.0.0.1:${port}/"; then
        break
      fi
      sleep 0.1
    done
    exec ${pkgs.xdg-utils}/bin/xdg-open "http://127.0.0.1:${port}/"
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ inputs.pave-query-builder.homeManagerModules.pave-query-builder ];

  options.hwc.home.apps.pave-query-builder = {
    enable = lib.mkEnableOption "pave-query-builder — trap-safe Pave query builder (TUI + web shell)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.pave-query-builder = {
      enable = true;
      inherit schemaPath;
      # Mutation guardrail: leave at the app's built-in default (HWC test org
      # only). Widen deliberately here if a real org ever needs writes.
      # mutationOrgs = [ "22Nm3uFevXMb" ];
    };

    # The GraphiQL web shell as a managed, on-demand background service. Not
    # WantedBy any target — the launcher starts it on first click; it stays up
    # after for instant reopen. Read-only + localhost-bound, so the grant key
    # never leaves the machine.
    systemd.user.services.pave-web = {
      Unit = {
        Description = "Pave Explorer — read-only GraphiQL web shell over the JobTread API";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${pave-web-start}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # Launcher entries — appear in wofi/rofi like any other app.
    xdg.desktopEntries.pave-explorer = {
      name = "Pave Explorer";
      genericName = "JobTread API explorer";
      comment = "Searchable GraphiQL explorer over the Pave (JobTread) API — read-only";
      exec = "${pave-web-open}";
      terminal = false;
      categories = [ "Utility" "Development" ];
      settings.Keywords = "jobtread;pave;api;graphql;graphiql;explorer;query;";
    };

    # The TUI front-end (mutations live here, behind the org guardrail).
    xdg.desktopEntries.pave-query-builder = {
      name = "Pave Query Builder (TUI)";
      genericName = "JobTread API query builder";
      comment = "Trap-safe Pave (JobTread) query TUI — reads + guarded mutations";
      exec = "kitty -e pave-query";
      terminal = false;
      categories = [ "Utility" "Development" ];
      settings.Keywords = "jobtread;pave;api;query;tui;";
    };
  };
}
