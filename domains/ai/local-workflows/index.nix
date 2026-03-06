# domains/ai/local-workflows/index.nix
#
# Local AI workflows and automation implementation
# Charter v6.0 compliant

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.local-workflows;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.local-workflows = {
    enable = lib.mkEnableOption "Local AI automation workflows";

    # Shared settings
    ollamaEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434";
      description = "Ollama API endpoint for workflows";
    };

    logDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/hwc-ai";
      description = "Directory for AI workflow logs";
    };

    #==========================================================================
    # FILE CLEANUP AGENT
    #==========================================================================
    fileCleanup = {
      enable = lib.mkEnableOption "AI-powered file cleanup and organization agent";

      watchDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = if paths.hot.root != null then [ "${paths.hot.root}/inbox" ] else [];
        description = "Directories to monitor and organize";
      };

      rulesDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.user.home}/.config/ai-cleanup/rules";
        description = "Directory containing organization rules";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*:0/30";  # Every 30 minutes
        description = "Systemd timer schedule (OnCalendar format)";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5-coder:3b";
        description = "Model to use for file categorization";
      };

      dryRun = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Only log actions without moving files";
      };
    };

    #==========================================================================
    # AUTOMATIC JOURNALING
    #==========================================================================
    journaling = {
      enable = lib.mkEnableOption "Automatic system event journaling with AI summaries";

      outputDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.user.home}/Documents/HWC-AI-Journal";
        description = "Directory for journal entries";
      };

      sources = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "systemd-journal"
          "container-logs"
          "nixos-rebuilds"
          "backup-reports"
        ]);
        default = [ "systemd-journal" "container-logs" "nixos-rebuilds" ];
        description = "Event sources to include in journal";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Journal frequency: daily, weekly, or OnCalendar format";
      };

      timeOfDay = lib.mkOption {
        type = lib.types.str;
        default = "02:00";
        description = "Time of day to generate journal (HH:MM format)";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "llama3.2:3b";
        description = "Model to use for summarization";
      };

      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Days to retain journal entries (0 = keep forever)";
      };
    };

    #==========================================================================
    # AUTO-DOCUMENTATION GENERATOR
    #==========================================================================
    autoDoc = {
      enable = lib.mkEnableOption "AI-powered code documentation generator (CLI tool)";

      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5-coder:3b";
        description = "Model to use for documentation generation";
      };

      templates = lib.mkOption {
        type = lib.types.path;
        default = "${paths.user.home}/.config/ai-doc/templates";
        description = "Directory containing documentation templates";
      };
    };

    #==========================================================================
    # LOCAL CHAT CLI
    #==========================================================================
    chatCli = {
      enable = lib.mkEnableOption "Interactive CLI chat interface for local models";

      model = lib.mkOption {
        type = lib.types.str;
        default = "phi3.5:3.8b";
        description = "Default model for chat";
      };

      historyFile = lib.mkOption {
        type = lib.types.path;
        default = "${paths.user.home}/.local/share/ai-chat/history.db";
        description = "SQLite database for chat history";
      };

      maxHistoryLines = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "Maximum lines of history to keep";
      };

      systemPrompt = lib.mkOption {
        type = lib.types.str;
        default = ''
          Sysadmin assistant. Execute commands, explain clearly.

          WORKFLOW:
          1. Run TOOL: command immediately (no questions)
          2. Show output
          3. Analyze and explain in plain English

          BEHAVIOR:
          - Assume defaults for vague queries
          - Always explain what output means
          - Identify issues, normal operations, or "no problems found"
          - Be direct, no pleasantries

          EXAMPLE:
          "errors" -> TOOL: journalctl -p err -b | tail -20
          After EVERY command, provide 2-3 sentence human summary.
        '';
        description = "Default system prompt for chat sessions";
      };
    };

    #==========================================================================
    # WORKFLOWS HTTP API (Sprint 5.4)
    #==========================================================================
    api = {
      enable = lib.mkEnableOption "HTTP API for local workflows (FastAPI)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 6021;
        description = "Port for workflows API";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address to bind to (localhost only for security)";
      };

      # Workflow-specific API settings
      cleanup = {
        allowedDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "${config.hwc.paths.hot.root}/inbox" "${paths.user.home}/Downloads" ];
          description = "Directories allowed for cleanup workflow via API";
        };
      };

      journal = {
        outputDir = lib.mkOption {
          type = lib.types.path;
          default = "${paths.user.home}/Documents/HWC-AI-Journal";
          description = "Directory for journal output from API";
        };
      };

      autodoc = {
        allowedDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ paths.nixos "${paths.user.home}/projects" ];
          description = "Directories allowed for autodoc workflow via API";
        };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkIf cfg.enable (mkMerge [

    #--------------------------------------------------------------------------
    # SHARED INFRASTRUCTURE
    #--------------------------------------------------------------------------
    {
      # Create log directory
      systemd.tmpfiles.rules = [
        "d ${cfg.logDir} 0755 eric users -"
      ];

      # Shared Python environment for AI workflows
      environment.systemPackages = with pkgs; [
        (python3.withPackages (ps: with ps; [
          requests      # For Ollama API calls
          pyyaml        # For config parsing
          rich          # For beautiful CLI output
        ]))
      ];
    }

    #--------------------------------------------------------------------------
    # FILE CLEANUP AGENT
    #--------------------------------------------------------------------------
    (mkIf cfg.fileCleanup.enable (import ./parts/file-cleanup.nix {
      inherit config lib pkgs cfg;
    }))

    #--------------------------------------------------------------------------
    # AUTOMATIC JOURNALING
    #--------------------------------------------------------------------------
    (mkIf cfg.journaling.enable (import ./parts/journaling.nix {
      inherit config lib pkgs cfg;
    }))

    #--------------------------------------------------------------------------
    # AUTO-DOCUMENTATION GENERATOR
    #--------------------------------------------------------------------------
    (mkIf cfg.autoDoc.enable (import ./parts/auto-doc.nix {
      inherit config lib pkgs cfg;
    }))

    #--------------------------------------------------------------------------
    # LOCAL CHAT CLI
    #--------------------------------------------------------------------------
    (mkIf cfg.chatCli.enable (import ./parts/chat-cli.nix {
      inherit config lib pkgs cfg;
    }))

    #--------------------------------------------------------------------------
    # WORKFLOWS HTTP API (Sprint 5.4)
    #--------------------------------------------------------------------------
    (mkIf cfg.api.enable (let
      # Package the API files
      apiPackage = pkgs.stdenv.mkDerivation {
        name = "hwc-workflows-api";
        src = ./api;
        installPhase = ''
          mkdir -p $out
          cp -r * $out/
        '';
      };

      # Python environment with dependencies
      pythonEnv = pkgs.python3.withPackages (ps: with ps; [
        fastapi
        uvicorn
        httpx
        pydantic
      ]);

      # Server startup script
      apiServer = pkgs.writeScriptBin "hwc-workflows-api" ''
        #!${pythonEnv}/bin/python3
        import sys
        sys.path.insert(0, "${apiPackage}")
        from server import app
        import uvicorn
        uvicorn.run(app, host="${cfg.api.host}", port=${toString cfg.api.port})
      '';
    in {
      # Make Python environment available
      environment.systemPackages = [ pythonEnv apiServer ];

      # API server as a systemd service
      systemd.services.hwc-ai-workflows-api = {
        description = "HWC Local Workflows API - HTTP API for AI workflows";
        after = [ "network.target" "ollama.service" ];
        wants = [ "ollama.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          User = lib.mkForce "eric";
          Group = lib.mkForce "users";  # Run as user to access home directories
          WorkingDirectory = config.hwc.paths.user.home;
          ExecStart = "${apiServer}/bin/hwc-workflows-api";

          # Pass configured paths as environment variables
          Environment = [
            "JOURNAL_DIR=${cfg.api.journal.outputDir}"
            "CLEANUP_DIRS=${lib.concatStringsSep ":" cfg.api.cleanup.allowedDirs}"
          ];

          Restart = "on-failure";
          RestartSec = "5s";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            cfg.logDir
            cfg.api.journal.outputDir
          ];

          # Resource limits
          MemoryMax = "2G";  # Workflows can be memory-intensive
          CPUQuota = "200%";  # Allow burst for processing

          # Kernel restrictions
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          SystemCallArchitectures = "native";
          RestrictRealtime = true;
          LockPersonality = true;
        };
      };

      # Create journal output directory
      systemd.tmpfiles.rules = [
        "d ${cfg.api.journal.outputDir} 0755 eric users -"
      ];
    }))

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    {
      assertions = [
        {
          assertion = cfg.enable -> config.hwc.ai.ollama.enable;
          message = "Local AI workflows require Ollama to be enabled (hwc.ai.ollama.enable = true)";
        }
      ];
    }

  ]);
}
