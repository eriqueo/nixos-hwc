{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.ai.agent;

  # Python environment with FastAPI and dependencies
  agentPython = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
  ]);

  # Create the agent script as a package
  agentScript = pkgs.writeScriptBin "hwc-ai-agent" ''
    #!${agentPython}/bin/python3
    ${builtins.readFile ./hwc-ai-agent.py}
  '';
in
{
  imports = [ ./options.nix ];

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
      
      serviceConfig = {
        ExecStart = "${agentScript}/bin/hwc-ai-agent --host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/log/hwc-ai" ];
        
        # Restrict capabilities
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        
        # System call filtering
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
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
