{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.aiBible;
  paths = config.hwc.paths;
  
  # Python environment for AI services
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi uvicorn pydantic
    torch transformers
    pandas numpy
    pyyaml
  ]);
in {
  options.hwc.services.aiBible = {
    enable = lib.mkEnableOption "AI Bible documentation system";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "API port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ai-bible";
    };
    
    features = {
      autoGeneration = lib.mkEnableOption "Auto documentation generation";
      
      llmIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable LLM integration";
      };
      
      categories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "system_architecture"
          "container_services"
          "hardware_gpu"
          "monitoring_observability"
          "storage_data"
        ];
        description = "Documentation categories";
      };
    };
    
    llm = {
      provider = lib.mkOption {
        type = lib.types.enum [ "ollama" "openai" "anthropic" ];
        default = "ollama";
      };
      
      model = lib.mkOption {
        type = lib.types.str;
        default = "llama2";
        description = "LLM model to use";
      };
      
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434";
        description = "LLM API endpoint";
      };
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Main AI Bible service
    systemd.services.ai-bible = {
      description = "AI Bible Documentation System";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ 
        lib.optional (cfg.llm.provider == "ollama") "ollama.service";
      
      environment = {
        BIBLE_PORT = toString cfg.port;
        BIBLE_DATA = cfg.dataDir;
        LLM_PROVIDER = cfg.llm.provider;
        LLM_MODEL = cfg.llm.model;
        LLM_ENDPOINT = cfg.llm.endpoint;
      };
      
      serviceConfig = {
        ExecStart = "${pythonEnv}/bin/python ${cfg.dataDir}/bible_system.py";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        User = "ai-bible";
        Group = "ai-bible";
        
        # Security
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };
    
    # Auto-generation timer
    systemd.timers.ai-bible-generate = lib.mkIf cfg.features.autoGeneration {
      description = "AI Bible auto-generation timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
    
    systemd.services.ai-bible-generate = lib.mkIf cfg.features.autoGeneration {
      description = "Generate AI Bible documentation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pythonEnv}/bin/python ${cfg.dataDir}/bible_rewriter.py";
        User = "ai-bible";
      };
    };
    
    # Provision Bible system files
    environment.etc = {
      "ai-bible/config.yaml".text = lib.generators.toYAML {} {
        categories = cfg.features.categories;
        llm = {
          provider = cfg.llm.provider;
          model = cfg.llm.model;
          endpoint = cfg.llm.endpoint;
        };
        features = {
          auto_generation = cfg.features.autoGeneration;
          llm_integration = cfg.features.llmIntegration;
        };
      };
      
      "ai-bible/prompts".source = ./modules/ai-bible/prompts;
    };
    
    # User and permissions
    users.users.ai-bible = {
      isSystemUser = true;
      group = "ai-bible";
      home = cfg.dataDir;
    };
    users.groups.ai-bible = {};
    
    # Setup directories and copy Python scripts
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ai-bible ai-bible -"
      "d ${cfg.dataDir}/bibles 0750 ai-bible ai-bible -"
      "d ${cfg.dataDir}/prompts 0750 ai-bible ai-bible -"
      "d ${cfg.dataDir}/output 0750 ai-bible ai-bible -"
    ];
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
