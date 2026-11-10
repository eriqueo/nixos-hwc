# domains/ai/mcp/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.ai.mcp;
  inherit (lib) mkIf mkMerge concatStringsSep;

  #==========================================================================
  # REUSABLE MCP SERVICE TEMPLATE
  #==========================================================================

  mkMcpService = {
    description,
    command,
    user,
    workingDirectory ? null,
    environment ? {},
    allowedPaths ? [],
    writablePaths ? [],
    extraServiceConfig ? {}
  }: {
    inherit description;
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = mkMerge [
      # Base configuration
      {
        Type = "simple";
        ExecStart = if builtins.isList command
                    then concatStringsSep " " command
                    else command;
        Restart = "on-failure";
        RestartSec = "5s";
        User = user;
      }

      # Working directory (if specified)
      (mkIf (workingDirectory != null) {
        WorkingDirectory = workingDirectory;
      })

      # Environment variables
      (mkIf (environment != {}) {
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
      })

      # Security hardening
      {
        # Process isolation
        NoNewPrivileges = true;
        PrivateTmp = true;

        # Resource limits (MCP servers are lightweight)
        MemoryMax = "512M";
        CPUQuota = "50%";

        # Filesystem protection (relaxed for npx compatibility)
        # npx needs access to /bin/sh and other system binaries
        ProtectSystem = "true";  # Changed from "strict" to allow /bin, /sbin access
        ProtectHome = false;  # MCP services need access to user home directories

        # Network restrictions (MCP servers typically don't need network)
        # If your MCP server needs network access, override this
        # PrivateNetwork = true;  # Commented out - mcp-proxy needs to listen

        # Kernel restrictions
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;

        # System call filtering
        SystemCallArchitectures = "native";

        # Restrict namespaces
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # Lock down personalities
        LockPersonality = true;
      }

      # Path permissions
      (mkIf (allowedPaths != []) {
        ReadOnlyPaths = allowedPaths;
      })

      (mkIf (writablePaths != []) {
        ReadWritePaths = writablePaths;
      })

      # User-provided overrides
      extraServiceConfig
    ];
  };

  filesystemCommand = [
    "${pkgs.nodejs_22}/bin/npx" "-y" "@modelcontextprotocol/server-filesystem"
  ] ++ cfg.filesystem.nixos.allowedDirs;
  filesystemService = {
    user = cfg.filesystem.nixos.user;
    workingDirectory = "/home/${cfg.filesystem.nixos.user}";
    environment.PATH = "/run/current-system/sw/bin:${pkgs.nodejs_22}/bin:${pkgs.bash}/bin";
    allowedPaths = [ "/nix/store" "/run/current-system" ];
    writablePaths = cfg.filesystem.nixos.allowedDirs ++ [
      "/home/${cfg.filesystem.nixos.user}/.npm"
    ];
  };

in
{
  #==========================================================================
  # IMPORTS
  #==========================================================================
  imports = [
    # Heartwood MCP moved to domains/business/mcp/ (hwc.business.mcp.*)
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.mcp = {
    enable = lib.mkEnableOption "MCP (Model Context Protocol) server infrastructure";

    # Proxy configuration
    proxy = {
      enable = lib.mkEnableOption "MCP proxy for stdio ↔ HTTP bridging" // { default = true; };
      active = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        default = cfg.enable && cfg.proxy.enable;
        description = "Whether this host runs the MCP HTTP proxy";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6001;
        description = "Port for mcp-proxy HTTP listener (localhost only)";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address for mcp-proxy (should remain localhost)";
      };
    };

    # Filesystem MCP server
    filesystem = {
      nixos = {
        enable = lib.mkEnableOption "Filesystem MCP server for ~/.nixos directory";

        allowedDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Directories accessible to the filesystem MCP server (defaults set dynamically in index.nix)";
        };

        draftsDir = lib.mkOption {
          type = lib.types.path;
          default = "/tmp/.nixos-mcp-drafts";
          description = "Directory for LLM-proposed changes (read/write) (default set dynamically in index.nix)";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "eric";
          description = "User to run the filesystem MCP server as";
        };
      };
    };

    # Reverse proxy configuration
    reverseProxy = {
      enable = lib.mkEnableOption "Expose MCP servers via Caddy reverse proxy" // { default = false; };
      active = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        default = cfg.proxy.active && cfg.reverseProxy.enable;
        description = "Whether the running MCP proxy is published through Caddy";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/mcp";
        description = "URL path for MCP proxy endpoint";
      };

      authType = lib.mkOption {
        type = lib.types.enum [ "none" "basic" "apikey" ];
        default = "none";
        description = ''
          Legacy compatibility input; this module does not configure authentication.
          Authentication type for MCP reverse proxy:
          - none: No authentication (local network only)
          - basic: HTTP Basic authentication
          - apikey: API key in header (X-API-Key)
        '';
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkMerge [
    # Set dynamic defaults for filesystem MCP server paths (mkDefault allows machine overrides)
    (mkIf cfg.filesystem.nixos.enable {
      hwc.ai.mcp.filesystem.nixos = {
        allowedDirs = lib.mkDefault [
          config.hwc.paths.nixos
          "${config.hwc.paths.user.home}/.nixos-mcp-drafts"
        ];
        draftsDir = lib.mkDefault "${config.hwc.paths.user.home}/.nixos-mcp-drafts";
      };
    })

    # Main MCP configuration
    (mkIf cfg.enable {

    #--------------------------------------------------------------------------
    # PACKAGES
    #--------------------------------------------------------------------------
    environment.systemPackages = with pkgs; [
      nodejs_22      # Required for @modelcontextprotocol/server-filesystem
      mcp-proxy      # stdio ↔ HTTP bridge
    ];

    #--------------------------------------------------------------------------
    # FILESYSTEM MCP SERVER (nixos)
    #--------------------------------------------------------------------------
    systemd.tmpfiles.rules = mkIf cfg.filesystem.nixos.enable [
      "d ${cfg.filesystem.nixos.draftsDir} 0755 ${cfg.filesystem.nixos.user} users -"
    ];

    systemd.services.mcp-filesystem-nixos = mkIf cfg.filesystem.nixos.enable
      (mkMcpService (filesystemService // {
        description = "MCP Filesystem Server for ~/.nixos directory";
        command = filesystemCommand;
      }));

    systemd.services.mcp-proxy = mkIf cfg.proxy.active
      (mkMcpService (filesystemService // {
        description = "MCP Proxy - stdio to HTTP bridge";
        command = [
          "${pkgs.mcp-proxy}/bin/mcp-proxy"
          "--host" cfg.proxy.host "--port" (toString cfg.proxy.port) "--"
        ] ++ filesystemCommand;
      }));

      #--------------------------------------------------------------------------
      # VALIDATION
      #--------------------------------------------------------------------------
      assertions = [
        {
          assertion = cfg.filesystem.nixos.enable || cfg.proxy.enable;
          message = "MCP module enabled but no services configured. Enable at least one MCP server.";
        }
        {
          assertion = !cfg.reverseProxy.enable || cfg.proxy.enable;
          message = "MCP reverse proxy requires mcp-proxy to be enabled.";
        }
      ];
    })
  ];

  #==========================================================================
  # REVERSE PROXY ROUTE
  #==========================================================================
  # Note: The reverse proxy route is configured in domains/server/routes.nix
  # to avoid circular dependency issues. The server routes module checks
  # hwc.ai.mcp.reverseProxy.enable and adds the route accordingly.
  # This ensures clean domain separation and prevents config evaluation issues.
}
