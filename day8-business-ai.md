# Day 8: Business Services & AI Infrastructure (5-6 hours)

## Morning Session (3 hours)
### 9:00 AM - Business Services Migration ✅

```bash
cd /etc/nixos-next

# Step 1: Create business API module
cat > modules/services/business-api.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.businessApi;
  paths = config.hwc.paths;
in {
  options.hwc.services.businessApi = {
    enable = lib.mkEnableOption "Business API services";
    
    apis = {
      invoicing = {
        enable = lib.mkEnableOption "Invoicing API";
        port = lib.mkOption {
          type = lib.types.port;
          default = 3001;
        };
        database = lib.mkOption {
          type = lib.types.str;
          default = "postgresql://localhost/invoicing";
        };
      };
      
      crm = {
        enable = lib.mkEnableOption "CRM API";
        port = lib.mkOption {
          type = lib.types.port;
          default = 3002;
        };
      };
      
      analytics = {
        enable = lib.mkEnableOption "Analytics API";
        port = lib.mkOption {
          type = lib.types.port;
          default = 3003;
        };
      };
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/business";
    };
  };
  
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.apis.invoicing.enable {
      virtualisation.oci-containers.containers.invoicing-api = {
        image = "business/invoicing:latest";
        ports = [ "${toString cfg.apis.invoicing.port}:3000" ];
        volumes = [
          "${cfg.dataDir}/invoicing:/data"
        ];
        environment = {
          DATABASE_URL = cfg.apis.invoicing.database;
          NODE_ENV = "production";
        };
      };
    })
    
    (lib.mkIf cfg.apis.crm.enable {
      virtualisation.oci-containers.containers.crm-api = {
        image = "business/crm:latest";
        ports = [ "${toString cfg.apis.crm.port}:3000" ];
        volumes = [
          "${cfg.dataDir}/crm:/data"
        ];
      };
    })
    
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root -"
        "d ${cfg.dataDir}/invoicing 0750 root root -"
        "d ${cfg.dataDir}/crm 0750 root root -"
      ];
      
      networking.firewall.allowedTCPPorts = lib.flatten [
        (lib.optional cfg.apis.invoicing.enable cfg.apis.invoicing.port)
        (lib.optional cfg.apis.crm.enable cfg.apis.crm.port)
      ];
    }
  ]);
}
EOF

# Step 2: Create comprehensive AI/Bible system module
cat > modules/services/ai-bible.nix << 'EOF'
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
EOF

# Step 3: Create Ollama module for local LLM
cat > modules/services/ollama.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ollama;
  paths = config.hwc.paths;
in {
  options.hwc.services.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port";
    };
    
    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "llama2" "codellama" ];
      description = "Models to download";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/ollama";
      description = "Model storage directory";
    };
    
    enableGpu = lib.mkEnableOption "GPU acceleration";
    
    memoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "16G";
      description = "Memory limit";
    };
  };
  
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.ollama = {
      image = "ollama/ollama:latest";
      
      ports = [ "${toString cfg.port}:11434" ];
      
      volumes = [
        "${cfg.dataDir}:/root/.ollama"
      ];
      
      environment = {
        OLLAMA_HOST = "0.0.0.0";
        OLLAMA_MODELS = cfg.dataDir;
      };
      
      extraOptions = lib.optionals cfg.enableGpu [
        "--gpus=all"
        "--device=/dev/nvidia0"
        "--device=/dev/nvidiactl"
        "--device=/dev/nvidia-uvm"
      ];
    };
    
    # Model download service
    systemd.services.ollama-models = {
      description = "Download Ollama models";
      after = [ "ollama.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        ${lib.concatMapStrings (model: ''
          ${pkgs.curl}/bin/curl -X POST http://localhost:${toString cfg.port}/api/pull \
            -d '{"name": "${model}"}'
        '') cfg.models}
      '';
    };
    
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
EOF
```

### 10:30 AM - Database Infrastructure ✅

```bash
# Step 4: Create database module
cat > modules/services/databases.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.databases;
  paths = config.hwc.paths;
in {
  options.hwc.services.databases = {
    postgresql = {
      enable = lib.mkEnableOption "PostgreSQL database";
      
      version = lib.mkOption {
        type = lib.types.str;
        default = "15";
        description = "PostgreSQL version";
      };
      
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state}/postgresql";
      };
      
      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Databases to create";
      };
      
      backup = {
        enable = lib.mkEnableOption "Automatic backups";
        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
        };
      };
    };
    
    redis = {
      enable = lib.mkEnableOption "Redis cache";
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
      };
      
      maxMemory = lib.mkOption {
        type = lib.types.str;
        default = "2gb";
        description = "Maximum memory";
      };
    };
    
    influxdb = {
      enable = lib.mkEnableOption "InfluxDB time-series database";
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 8086;
      };
    };
  };
  
  config = lib.mkMerge [
    (lib.mkIf cfg.postgresql.enable {
      services.postgresql = {
        enable = true;
        package = pkgs."postgresql_${cfg.postgresql.version}";
        dataDir = cfg.postgresql.dataDir;
        
        ensureDatabases = cfg.postgresql.databases;
        
        authentication = ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
        '';
      };
      
      # Backup service
      systemd.services.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        description = "PostgreSQL backup";
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = "${pkgs.postgresql}/bin/pg_dumpall -f ${paths.backup}/postgresql-$(date +%Y%m%d).sql";
        };
      };
      
      systemd.timers.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.postgresql.backup.schedule;
          Persistent = true;
        };
      };
    })
    
    (lib.mkIf cfg.redis.enable {
      services.redis.servers.main = {
        enable = true;
        port = cfg.redis.port;
        settings = {
          maxmemory = cfg.redis.maxMemory;
          maxmemory-policy = "allkeys-lru";
        };
      };
    })
    
    (lib.mkIf cfg.influxdb.enable {
      services.influxdb2 = {
        enable = true;
        settings = {
          http-bind-address = ":${toString cfg.influxdb.port}";
        };
      };
      
      networking.firewall.allowedTCPPorts = [ cfg.influxdb.port ];
    })
  ];
}
EOF
```

## Afternoon Session (3 hours)

### 2:00 PM - Create Business/AI Profile ✅

```bash
# Step 5: Create business profile
cat > profiles/business.nix << 'EOF'
{ ... }:
{
  imports = [
    ../modules/services/business-api.nix
    ../modules/services/databases.nix
  ];
  
  hwc.services.businessApi = {
    enable = true;
    apis = {
      invoicing.enable = true;
      crm.enable = true;
      analytics.enable = true;
    };
  };
  
  hwc.services.databases = {
    postgresql = {
      enable = true;
      databases = [ "invoicing" "crm" "analytics" ];
      backup.enable = true;
    };
    redis.enable = true;
  };
}
EOF

# Step 6: Create AI profile
cat > profiles/ai.nix << 'EOF'
{ ... }:
{
  imports = [
    ../modules/services/ai-bible.nix
    ../modules/services/ollama.nix
  ];
  
  hwc.services.aiBible = {
    enable = true;
    features = {
      autoGeneration = true;
      llmIntegration = true;
    };
    llm = {
      provider = "ollama";
      model = "llama2";
    };
  };
  
  hwc.services.ollama = {
    enable = true;
    enableGpu = true;
    models = [ "llama2" "codellama" "mistral" ];
  };
}
EOF

# Step 7: Create migration script for AI Bible files
cat > operations/migration/migrate-ai-bible.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== Migrating AI Bible System ==="

OLD_BASE="/etc/nixos"
NEW_BASE="/etc/nixos-next"

# Copy Python scripts
echo "Copying Python scripts..."
mkdir -p "$NEW_BASE/modules/ai-bible/scripts"
cp "$OLD_BASE/scripts/bible_"*.py "$NEW_BASE/modules/ai-bible/scripts/"

# Copy prompts
echo "Copying prompts..."
mkdir -p "$NEW_BASE/modules/ai-bible/prompts"
cp -r "$OLD_BASE/prompts/bible_prompts/" "$NEW_BASE/modules/ai-bible/prompts/"

# Copy config files
echo "Copying configuration..."
cp "$OLD_BASE/config/bible_"*.yaml "$NEW_BASE/modules/ai-bible/data/"

echo "✅ AI Bible system files migrated"
echo "📝 Remember to update paths in the Python scripts"
EOF
chmod +x operations/migration/migrate-ai-bible.sh

# Step 8: Test combined profile
cat > machines/business-ai-test.nix << 'EOF'
{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/business.nix
    ../profiles/ai.nix
    ../profiles/monitoring.nix
  ];
  
  networking.hostName = "business-ai-test";
  
  # GPU for AI workloads
  hwc.gpu.nvidia = {
    enable = true;
    containerRuntime = true;
  };
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
  
  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "24.05";
}
EOF

sudo nixos-rebuild build --flake .#business-ai-test
```

### 4:00 PM - Document Complex Service Patterns ✅

```bash
# Step 9: Create patterns documentation
cat > docs/MIGRATION_PATTERNS.md << 'EOF'
# Migration Patterns

## Pattern 1: Simple Containerized Service
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.myservice;
in {
  options = { ... };
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.myservice = { ... };
  };
}
```

## Pattern 2: Service with GPU Support

```nix
extraOptions = lib.optionals cfg.enableGpu [
  "--gpus=all"
  "--runtime=nvidia"
];
```

## Pattern 3: Service with State Management

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
];
```

## Pattern 4: Service with Dependencies

```nix
after = [ "network.target" ] ++ 
  lib.optional cfg.needsDatabase "postgresql.service";
```

## Pattern 5: Service with Scheduled Tasks

```nix
systemd.timers.myservice-task = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnCalendar = "daily";
};
```

EOF

# Step 10: Update migration log

cat >> MIGRATION_LOG.md << 'EOF'

## Day 8: $(date +%Y-%m-%d)

- [x] Business API services
- [x] AI Bible system
- [x] Ollama local LLM
- [x] Database infrastructure
- [x] Business profile
- [x] AI profile

Services migrated: 15+ total
Complex services now included:

- AI Bible with auto-generation
- Ollama with GPU support
- PostgreSQL with backups
- Redis cache
- Business APIs
EOF

git add -A
git commit -m "Day 8: Business services and AI infrastructure"
```

## End of Day 8 Checklist
- [ ] Business services migrated
- [ ] AI Bible system complete
- [ ] Database layer established
- [ ] Profiles for business/AI created
- [ ] 15+ services migrated total
