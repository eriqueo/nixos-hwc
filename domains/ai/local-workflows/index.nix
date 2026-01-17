# domains/server/ai/local-workflows/default.nix
#
# Local AI workflows and automation implementation
# Charter v6.0 compliant

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.local-workflows;
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
