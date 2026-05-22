# domains/server/native/ai/lead-scout/index.nix
#
# Lead Scout — native systemd service
# Serves a Facebook group lead scraper and classifier as an HTTP + MCP server
# on port 8420, proxied externally via Cloudflare Tunnel at leads.heartwoodcraft.me.
{ config, lib, ... }:
let
  cfg = config.hwc.server.ai.leadScout;
  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.projectDir}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #==========================================================================
    # SYSTEMD SERVICE
    #==========================================================================
    systemd.services.lead-scout = {
      description = "Lead Scout MCP + HTTP Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DATABASE_URL  = cfg.databaseUrl;
        LOG_LEVEL     = "info";
        NODE_ENV      = "production";
      };

      serviceConfig = {
        Type             = "simple";
        ExecStart        = "${node} ${tsx} ${cli} serve --port ${toString cfg.port}";
        WorkingDirectory = cfg.projectDir;
        User             = cfg.user;
        Restart          = "on-failure";
        RestartSec       = "5s";

        # Security hardening
        NoNewPrivileges      = true;
        PrivateTmp           = true;
        ProtectSystem        = "strict";
        ProtectHome          = "read-only";
        ProtectKernelTunables  = true;
        ProtectKernelModules   = true;
        ProtectControlGroups   = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces     = true;
        RestrictRealtime       = true;
        RestrictSUIDSGID       = true;
        LockPersonality        = true;

        # Read/write access needed for browser profile and data
        ReadWritePaths = [
          "${cfg.projectDir}/data"
          "/tmp"
        ];
      };
    };

  };
}
