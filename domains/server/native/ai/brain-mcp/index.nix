# domains/server/native/ai/brain-mcp/index.nix
#
# Brain MCP Server — native Deno systemd service
# Exposes the vault CRUD/refactor tools (read/write/list/search_notes, lint,
# inbox, delete/move/replace/frontmatter/commit) plus semantic retrieval
# (search_semantic, related_notes — brainvec index + llama-embed on :11502).
# Binds to 127.0.0.1:9876 (Tailscale tunnel added in Phase 12).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.brainMcp;
  paths = config.hwc.paths;
  deno = "${pkgs.deno}/bin/deno";
  server = "${paths.nixos}/domains/server/native/ai/brain-mcp/parts/server.ts";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.server.ai.brainMcp = {
    enable = lib.mkEnableOption "Brain MCP Server (Deno)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9876;
      description = "Internal port the Brain MCP server listens on (127.0.0.1 only)";
    };

    vaultPath = lib.mkOption {
      type = lib.types.path;
      # hwc.paths.brain.vault is laptop-only (null here); fall back to the
      # same vault path under the server's user home (Syncthing replica)
      default = if paths.brain.vault != null then paths.brain.vault
                else "${paths.user.home}/900_vaults/brain";
      description = "Path to the brain vault replica on the server";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/brain-mcp-api-key";
      description = "Path to file containing the MCP Bearer token (agenix-decrypted)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the Brain MCP service as";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 23443;
      description = "External Caddy HTTPS port for brain-mcp access via Tailscale (Phase 12)";
    };

    brainvecIndex = lib.mkOption {
      type = lib.types.str;
      default = "${paths.user.home}/.cache/brainvec/index.jsonl";
      description = "brainvec semantic index consumed by search_semantic/related_notes (built by hwc.server.ai.brainvec)";
    };

    embedBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11502/v1";
      description = "OpenAI-compatible embeddings endpoint for query-time embedding (llama-embed)";
    };

    embedModel = lib.mkOption {
      type = lib.types.str;
      default = "nomic-embed-text-v1.5";
      description = "Embedding model label — must match the index's embedId prefix";
    };
  };

  config = lib.mkIf cfg.enable {

    #==========================================================================
    # SYSTEM PACKAGES
    #==========================================================================
    environment.systemPackages = [ pkgs.deno pkgs.ripgrep pkgs.git pkgs.util-linux ];

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
        BRAINVEC_INDEX = cfg.brainvecIndex;
        BRAINVEC_EMBED_BASE_URL = cfg.embedBaseUrl;
        BRAINVEC_EMBED_MODEL = cfg.embedModel;
        BRAINVEC_EMBED_PREFIX_QUERY = "search_query: ";
        DENO_DIR = "/var/cache/brain-mcp/deno";
        HOME = "/home/${cfg.user}";
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
      };

      serviceConfig = {
        Type = "simple";
        # allow-net: the listen port + outbound to llama-embed for query-time
        # embedding (search_semantic).
        ExecStart = "${deno} run --allow-read --allow-write=${cfg.vaultPath} --allow-net=0.0.0.0:${toString cfg.port},127.0.0.1:11502 --allow-run=rg,git,flock --allow-env ${server}";
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

    #==========================================================================
    # CADDY REVERSE PROXY — port mode on :13443 (Phase 12)
    # Deviation: tailscale serve --https=8443 not viable (port 8443 owned by slskd/Caddy).
    # Creates https://hwc-server.ocelot-wahoo.ts.net:13443 via Caddy with Tailscale cert.
    #==========================================================================
    hwc.networking.shared.routes = [{
      name = "brain-mcp";
      mode = "port";
      port = cfg.reverseProxyPort;
      upstream = "http://127.0.0.1:${toString cfg.port}";
    }];

    #==========================================================================
    # FIREWALL — port 9876 for direct Tailscale IP access from laptop (Claude Code MCP).
    # Port 13443 opened automatically by reverseProxy.nix for port-mode routes.
    #==========================================================================
    networking.firewall.allowedTCPPorts = [ cfg.port ];

  };
}
