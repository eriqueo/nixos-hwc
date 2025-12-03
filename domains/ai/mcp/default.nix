{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.ai.mcp;
  inherit (lib) mkIf mkMerge concatStringsSep;

  # Get username from system configuration
  userName = config.hwc.system.users.user.name;
  userHome = config.users.users.${userName}.home;

  #==========================================================================
  # REUSABLE MCP SERVICE TEMPLATE
  #==========================================================================

  # Template function to create standardized MCP systemd services
  # Parameters:
  #   name: Service name (e.g., "mcp-filesystem-nixos")
  #   description: Human-readable service description
  #   command: Command to execute (list of strings for ExecStart)
  #   user: User to run the service as
  #   workingDirectory: Working directory for the service (optional)
  #   environment: Environment variables (attrset, optional)
  #   allowedPaths: Paths the service can read (list, optional)
  #   writablePaths: Paths the service can write (list, optional)
  #   extraServiceConfig: Additional systemd service configuration (attrset, optional)
  mkMcpService = {
    name,
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
        ProtectHome = mkIf (user != userName) true;  # Don't protect if running as primary user

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

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkMerge [
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
    # DYNAMIC DEFAULTS - Set user-specific paths
    #--------------------------------------------------------------------------
    hwc.ai.mcp.filesystem.nixos = mkMerge [
      (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.user == "") {
        user = lib.mkDefault userName;
      })
      (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.allowedDirs == []) {
        allowedDirs = lib.mkDefault [
          "${userHome}/.nixos"
          "${userHome}/.nixos-mcp-drafts"
        ];
      })
      (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.draftsDir == "/tmp/.nixos-mcp-drafts") {
        draftsDir = lib.mkDefault "${userHome}/.nixos-mcp-drafts";
      })
    ];

    #--------------------------------------------------------------------------
    # FILESYSTEM MCP SERVER (nixos)
    #--------------------------------------------------------------------------
    systemd.tmpfiles.rules = mkIf cfg.filesystem.nixos.enable [
      "d ${cfg.filesystem.nixos.draftsDir} 0755 ${cfg.filesystem.nixos.user} users -"
    ];

    systemd.services.mcp-filesystem-nixos = mkIf cfg.filesystem.nixos.enable (mkMcpService {
      name = "mcp-filesystem-nixos";
      description = "MCP Filesystem Server for ~/.nixos directory";
      command =
        let
          baseCmd = [
            "${pkgs.nodejs_22}/bin/npx"
            "-y"
            "@modelcontextprotocol/server-filesystem"
          ];
        in
          baseCmd ++ cfg.filesystem.nixos.allowedDirs;  # Each directory as separate argument
      user = cfg.filesystem.nixos.user;
      workingDirectory = "/home/${cfg.filesystem.nixos.user}";

      # npx needs PATH set to find sh and other utilities
      environment = {
        PATH = "/run/current-system/sw/bin:${pkgs.nodejs_22}/bin:${pkgs.bash}/bin";
      };

      # Read-only paths for system dependencies (npx needs Nix store)
      allowedPaths = [
        "/nix/store"
        "/run/current-system"
      ];

      # Write paths for allowed directories and NPM cache
      writablePaths = cfg.filesystem.nixos.allowedDirs ++ [
        "/home/${cfg.filesystem.nixos.user}/.npm"
      ];
    });

    #--------------------------------------------------------------------------
    # MCP PROXY (stdio ↔ HTTP bridge)
    #--------------------------------------------------------------------------
    systemd.services.mcp-proxy = mkIf cfg.proxy.enable (mkMcpService {
      name = "mcp-proxy";
      description = "MCP Proxy - stdio to HTTP bridge";
      command =
        let
          proxyCmd = [
            "${pkgs.mcp-proxy}/bin/mcp-proxy"
            "--host" cfg.proxy.host
            "--port" (toString cfg.proxy.port)
            "--"
            "${pkgs.nodejs_22}/bin/npx"
            "-y"
            "@modelcontextprotocol/server-filesystem"
          ];
        in
          proxyCmd ++ cfg.filesystem.nixos.allowedDirs;  # Each directory as separate argument
      user = cfg.filesystem.nixos.user;
      workingDirectory = "/home/${cfg.filesystem.nixos.user}";

      # npx needs PATH set to find sh and other utilities
      environment = {
        PATH = "/run/current-system/sw/bin:${pkgs.nodejs_22}/bin:${pkgs.bash}/bin";
      };

      # Read-only paths for system dependencies (npx needs Nix store)
      allowedPaths = [
        "/nix/store"
        "/run/current-system"
      ];

      # Write paths for allowed directories and NPM cache
      writablePaths = cfg.filesystem.nixos.allowedDirs ++ [
        "/home/${cfg.filesystem.nixos.user}/.npm"
      ];

      # Override network restrictions (proxy needs to listen on localhost)
      extraServiceConfig = {
        # Network access required for HTTP server - security exception documented
        # Proxy listens on 127.0.0.1 only (configured in options)
      };
    });

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

    # TODO: Re-enable reverse proxy route configuration with proper machine detection
    # The reverse proxy route should only be configured on server machines.
    # Current implementation causes circular dependency issues.
    # Consider using networking.hostName or a machine-specific flag instead of
    # attempting to detect hwc.services.shared existence within config evaluation.
  ];
}
