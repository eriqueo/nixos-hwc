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
