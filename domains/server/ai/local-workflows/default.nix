# domains/server/ai/local-workflows/default.nix
#
# Local AI workflows and automation implementation
# Charter v6.0 compliant

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.ai.local-workflows;
  inherit (lib) mkIf mkMerge;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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
        "d ${cfg.logDir} 0755 root root -"
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
    # VALIDATION
    #--------------------------------------------------------------------------
    {
      assertions = [
        {
          assertion = cfg.enable -> config.hwc.server.ai.ollama.enable;
          message = "Local AI workflows require Ollama to be enabled (hwc.server.ai.ollama.enable = true)";
        }
      ];
    }

  ]);
}
