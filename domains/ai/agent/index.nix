{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.ai.agent;

  # Python environment with FastAPI and dependencies
  agentPython = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
  ]);

  # Create the agent script as a package with dynamic path substitution
  agentScript = pkgs.writeScriptBin "hwc-ai-agent" ''
    #!${agentPython}/bin/python3
    ${builtins.replaceStrings
      ["/home/eric/.nixos" "/home/eric/.nixos-mcp-drafts"]
      [config.hwc.paths.nixos "${config.hwc.paths.user.home}/.nixos-mcp-drafts"]
      (builtins.readFile ./hwc-ai-agent.py)
    }
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install agent script (dependencies bundled in shebang)
    environment.systemPackages = [ agentScript ];

    # Create log directory
    systemd.tmpfiles.rules = [
      "d /var/log/hwc-ai 0755 root root -"
      "f ${cfg.auditLog} 0640 root adm -"
    ];

    # Systemd service
    systemd.services.hwc-ai-agent = {
      description = "HWC AI Agent - limited tool API";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Environment for system command access
      path = with pkgs; [ podman systemd ];

      serviceConfig = {
        ExecStart = "${agentScript}/bin/hwc-ai-agent --host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";

        # Security hardening (relaxed for podman access)
        # Note: Podman requires namespace and storage access
        NoNewPrivileges = false;  # Podman needs privilege escalation
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = "read-only";  # Allow read access to root's podman config
        ReadWritePaths = [
          "/var/log/hwc-ai"
          "/run/containers"
          "/var/lib/containers/storage"
        ];

        # System call filtering
        SystemCallArchitectures = "native";
        RestrictRealtime = true;
        LockPersonality = true;
        
        # Kernel restrictions
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
    };

    # Validation
    assertions = [
      {
        assertion = cfg.enable -> (cfg.port > 0 && cfg.port < 65536);
        message = "AI Agent port must be between 1 and 65535";
      }
    ];
  };

}
