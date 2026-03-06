# domains/ai/router/index.nix
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
  options.hwc.ai.router = {
    enable = lib.mkEnableOption "AI model router for local/cloud fallback";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11435;
      description = "Router port (Ollama uses 11434, router uses 11435)";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the router service";
    };

    ollamaEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434";
      description = "Local Ollama endpoint";
    };

    routing = {
      strategy = lib.mkOption {
        type = lib.types.enum ["local-first" "cloud-first" "cost-optimized" "latency-optimized"];
        default = "local-first";
        description = ''
          Routing strategy:
          - local-first: Always try local, fallback to cloud on failure
          - cloud-first: Prefer cloud for large models, local for small
          - cost-optimized: Minimize cloud API costs
          - latency-optimized: Choose fastest option based on history
        '';
      };

      localTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Timeout in seconds for local model requests before fallback";
      };

      cloudTimeout = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Timeout in seconds for cloud API requests";
      };
    };

    modelMappings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          local = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Local Ollama model name";
          };
          cloud = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Cloud model name (provider:model format, e.g., openai:gpt-4o)";
          };
          preferLocal = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Prefer local model if available";
          };
        };
      });
      default = {};
      example = {
        "gpt-4" = {
          local = "llama3:70b";
          cloud = "openai:gpt-4o";
          preferLocal = true;
        };
        "claude" = {
          local = "llama3.2:3b";
          cloud = "anthropic:claude-sonnet-4-5-20250929";
          preferLocal = true;
        };
      };
      description = "Model mappings between local and cloud providers";
    };

    logging = {
      level = lib.mkOption {
        type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = "Logging level for the router service";
      };

      logRequests = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Log all routing decisions and requests";
      };
    };
  };

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
