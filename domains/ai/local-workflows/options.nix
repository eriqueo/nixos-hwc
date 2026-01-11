# domains/server/ai/local-workflows/options.nix
#
# Options for local AI workflows and automation
# Charter v6.0 compliant

{ lib, config, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
  paths = config.hwc.paths;
in
{
  options.hwc.ai.local-workflows = {
    enable = mkEnableOption "Local AI automation workflows";

    # Shared settings
    ollamaEndpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:11434";
      description = "Ollama API endpoint for workflows";
    };

    logDir = mkOption {
      type = types.path;
      default = "/var/log/hwc-ai";
      description = "Directory for AI workflow logs";
    };

    #==========================================================================
    # FILE CLEANUP AGENT
    #==========================================================================
    fileCleanup = {
      enable = mkEnableOption "AI-powered file cleanup and organization agent";

      watchDirs = mkOption {
        type = types.listOf types.str;
        default = if paths.hot.root != null then [ "${paths.hot.root}/inbox" ] else [];
        description = "Directories to monitor and organize";
      };

      rulesDir = mkOption {
        type = types.path;
        default = "${paths.user.home}/.config/ai-cleanup/rules";
        description = "Directory containing organization rules";
      };

      schedule = mkOption {
        type = types.str;
        default = "*:0/30";  # Every 30 minutes
        description = "Systemd timer schedule (OnCalendar format)";
      };

      model = mkOption {
        type = types.str;
        default = "qwen2.5-coder:3b";
        description = "Model to use for file categorization";
      };

      dryRun = mkOption {
        type = types.bool;
        default = false;
        description = "Only log actions without moving files";
      };
    };

    #==========================================================================
    # AUTOMATIC JOURNALING
    #==========================================================================
    journaling = {
      enable = mkEnableOption "Automatic system event journaling with AI summaries";

      outputDir = mkOption {
        type = types.path;
        default = "${paths.user.home}/Documents/HWC-AI-Journal";
        description = "Directory for journal entries";
      };

      sources = mkOption {
        type = types.listOf (types.enum [
          "systemd-journal"
          "container-logs"
          "nixos-rebuilds"
          "backup-reports"
        ]);
        default = [ "systemd-journal" "container-logs" "nixos-rebuilds" ];
        description = "Event sources to include in journal";
      };

      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Journal frequency: daily, weekly, or OnCalendar format";
      };

      timeOfDay = mkOption {
        type = types.str;
        default = "02:00";
        description = "Time of day to generate journal (HH:MM format)";
      };

      model = mkOption {
        type = types.str;
        default = "llama3.2:3b";
        description = "Model to use for summarization";
      };

      retentionDays = mkOption {
        type = types.int;
        default = 90;
        description = "Days to retain journal entries (0 = keep forever)";
      };
    };

    #==========================================================================
    # AUTO-DOCUMENTATION GENERATOR
    #==========================================================================
    autoDoc = {
      enable = mkEnableOption "AI-powered code documentation generator (CLI tool)";

      model = mkOption {
        type = types.str;
        default = "qwen2.5-coder:3b";
        description = "Model to use for documentation generation";
      };

      templates = mkOption {
        type = types.path;
        default = "${paths.user.home}/.config/ai-doc/templates";
        description = "Directory containing documentation templates";
      };
    };

    #==========================================================================
    # LOCAL CHAT CLI
    #==========================================================================
    chatCli = {
      enable = mkEnableOption "Interactive CLI chat interface for local models";

      model = mkOption {
        type = types.str;
        default = "phi3.5:3.8b";
        description = "Default model for chat";
      };

      historyFile = mkOption {
        type = types.path;
        default = "${paths.user.home}/.local/share/ai-chat/history.db";
        description = "SQLite database for chat history";
      };

      maxHistoryLines = mkOption {
        type = types.int;
        default = 1000;
        description = "Maximum lines of history to keep";
      };

      systemPrompt = mkOption {
        type = types.str;
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
      enable = mkEnableOption "HTTP API for local workflows (FastAPI)";

      port = mkOption {
        type = types.port;
        default = 6021;
        description = "Port for workflows API";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address to bind to (localhost only for security)";
      };

      # Workflow-specific API settings
      cleanup = {
        allowedDirs = mkOption {
          type = types.listOf types.str;
          default = [ "${config.hwc.paths.hot.root or "/mnt/hot"}/inbox" "${paths.user.home}/Downloads" ];
          description = "Directories allowed for cleanup workflow via API";
        };
      };

      journal = {
        outputDir = mkOption {
          type = types.path;
          default = "${paths.user.home}/Documents/HWC-AI-Journal";
          description = "Directory for journal output from API";
        };
      };

      autodoc = {
        allowedDirs = mkOption {
          type = types.listOf types.str;
          default = [ paths.nixos "${paths.user.home}/projects" ];
          description = "Directories allowed for autodoc workflow via API";
        };
      };
    };
  };
}
