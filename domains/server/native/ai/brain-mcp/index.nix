# domains/server/native/ai/brain-mcp/index.nix
#
# Brain MCP Server — native Deno systemd service
# Exposes 6 MCP tools: read_note, write_note, list_notes, search_notes, lint_wiki, append_to_inbox
# Binds to 127.0.0.1:9876 (Tailscale tunnel added in Phase 12).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.brainMcp;
  deno = "${pkgs.deno}/bin/deno";
  server = "/home/eric/.nixos/domains/server/native/ai/brain-mcp/parts/server.ts";
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #==========================================================================
    # SYSTEM PACKAGES
    #==========================================================================
    environment.systemPackages = [ pkgs.deno pkgs.ripgrep ];

    #==========================================================================
    # SYSTEMD SERVICE
    #==========================================================================
    systemd.services.brain-mcp = {
      description = "Brain MCP Server (Deno) — vault filesystem tools";
      after = [ "network-online.target" "syncthing.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        BRAIN_VAULT_ROOT = cfg.vaultPath;
        BRAIN_MCP_PORT = toString cfg.port;
        BRAIN_MCP_KEY_FILE = cfg.apiKeyFile;
        DENO_DIR = "/var/cache/brain-mcp/deno";
        HOME = "/home/${cfg.user}";
        PATH = "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${deno} run --allow-read --allow-write=${cfg.vaultPath} --allow-net=127.0.0.1:${toString cfg.port} --allow-run=rg --allow-env ${server}";
        WorkingDirectory = cfg.vaultPath;
        User = lib.mkForce cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";

        # Deno needs write access to its cache dir
        CacheDirectory = "brain-mcp";
        StateDirectory = "brain-mcp";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "true";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [ cfg.vaultPath "/var/cache/brain-mcp" ];
      };
    };

  };
}
