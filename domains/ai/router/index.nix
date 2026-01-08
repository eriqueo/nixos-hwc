{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.router;
  cloudCfg = config.hwc.ai.cloud;

  # Python environment with FastAPI and dependencies
  routerPython = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    httpx
  ]);

  # Router service script
  routerService = pkgs.writeScriptBin "ai-router-service" ''
    #!${routerPython}/bin/python3
    ${builtins.readFile ./parts/router-service.py}
  '';

  # Environment variables for the router
  routerEnv = {
    ROUTER_HOST = cfg.host;
    ROUTER_PORT = toString cfg.port;
    OLLAMA_ENDPOINT = cfg.ollamaEndpoint;
    ROUTING_STRATEGY = cfg.routing.strategy;
    LOCAL_TIMEOUT = toString cfg.routing.localTimeout;
    CLOUD_TIMEOUT = toString cfg.routing.cloudTimeout;
    LOG_LEVEL = cfg.logging.level;
    LOG_REQUESTS = if cfg.logging.logRequests then "true" else "false";
  } // lib.optionalAttrs (cloudCfg.enable && cloudCfg.openai.enable) {
    OPENAI_API_ENDPOINT = cloudCfg.openai.endpoint;
  } // lib.optionalAttrs (cloudCfg.enable && cloudCfg.anthropic.enable) {
    ANTHROPIC_API_ENDPOINT = cloudCfg.anthropic.endpoint;
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
  config = lib.mkIf cfg.enable {

    # System packages
    environment.systemPackages = [ routerService ];

    # Systemd service for the router
    systemd.services.ai-model-router = {
      description = "AI Model Router - Local/Cloud intelligent routing";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = routerEnv;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${routerService}/bin/ai-router-service";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        DynamicUser = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;

        # Resource limits
        MemoryMax = "1G";
        CPUQuota = "100%";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ai-router";
      };

      # Load cloud API keys from files if configured
      # This uses systemd's LoadCredential for secure secret handling
    };

    # Firewall configuration (if router should be accessible beyond localhost)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.host != "127.0.0.1" && cfg.host != "localhost") [
      cfg.port
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.port != config.hwc.ai.ollama.port;
        message = "Router port (${toString cfg.port}) conflicts with Ollama port (${toString config.hwc.ai.ollama.port})";
      }
      {
        assertion = !cfg.enable || config.hwc.ai.ollama.enable;
        message = "AI router requires Ollama to be enabled (hwc.ai.ollama.enable = true)";
      }
    ];

    warnings = lib.optionals cfg.enable [
      ''
        AI Model Router enabled on ${cfg.host}:${toString cfg.port}
        - Strategy: ${cfg.routing.strategy}
        - Local endpoint: ${cfg.ollamaEndpoint}
        - This is a basic implementation. Cloud routing requires further integration.
        - Use model names like "openai:gpt-4o" or "anthropic:claude-sonnet" for explicit cloud routing.
      ''
    ];
  };
}
