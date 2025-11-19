# domains/server/ai/ai-bible/parts/ai-bible.nix
#
# AI Bible - Self-documenting NixOS configuration system
#
# Automatically analyzes the NixOS codebase and generates comprehensive
# documentation using local LLM. Provides REST API for querying docs.
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (for data directory paths)
#   - Ollama service (optional, for LLM-powered documentation)
#
# USED BY (Downstream):
#   - profiles/ai.nix (enables via hwc.services.aiBible.enable)
#
# USAGE:
#   hwc.services.aiBible.enable = true;
#   # Access web UI at http://localhost:8888

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.aiBible;
  paths = config.hwc.paths;

  # Python environment with all dependencies
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    pyyaml
    requests
  ]);

  # The AI Bible service script
  serviceScript = pkgs.writeScript "ai-bible-service" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    export BIBLE_PORT="${toString cfg.port}"
    export BIBLE_DATA_DIR="${cfg.dataDir}"
    export BIBLE_CODEBASE_ROOT="${cfg.codebase.rootPath}"
    export BIBLE_LLM_ENDPOINT="${cfg.llm.endpoint}"
    export BIBLE_LLM_MODEL="${cfg.llm.model}"
    export BIBLE_LLM_ENABLED="${if cfg.features.llmIntegration then "true" else "false"}"
    export BIBLE_CATEGORIES="${lib.concatStringsSep "," cfg.features.categories}"

    exec ${pythonEnv}/bin/python ${./ai_bible_service.py}
  '';

  # Scan trigger script
  scanScript = pkgs.writeScript "ai-bible-scan" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Trigger scan via API
    ${pkgs.curl}/bin/curl -X POST http://localhost:${toString cfg.port}/api/scan || true
  '';

in {
  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ai-bible ai-bible -"
      "d ${cfg.dataDir}/logs 0750 ai-bible ai-bible -"
      "d ${cfg.dataDir}/documentation 0750 ai-bible ai-bible -"
    ];

    # Create dedicated user for the service
    users.users.ai-bible = {
      isSystemUser = true;
      group = "ai-bible";
      description = "AI Bible documentation service";
      home = cfg.dataDir;
    };

    users.groups.ai-bible = {};

    #==========================================================================
    # MAIN SERVICE
    #==========================================================================
    systemd.services.ai-bible = {
      description = "AI Bible Self-Documenting System";
      documentation = [ "https://github.com/yourusername/nixos-hwc" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++
        lib.optional (cfg.llm.provider == "ollama" && cfg.features.llmIntegration)
          "ollama.service";

      # Only require Ollama if LLM integration is enabled
      requires = lib.optional (cfg.llm.provider == "ollama" && cfg.features.llmIntegration)
        "ollama.service";

      serviceConfig = {
        Type = "simple";
        ExecStart = "${serviceScript}";
        Restart = "on-failure";
        RestartSec = "10s";

        # Run as dedicated user
        User = "ai-bible";
        Group = "ai-bible";

        # Security hardening
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

        # Allow read access to /etc/nixos for codebase scanning
        ReadOnlyPaths = [ "/etc/nixos" ];

        # Allow write access to state directory
        ReadWritePaths = [ cfg.dataDir ];

        # Resource limits
        MemoryMax = "2G";
        CPUQuota = "100%";
      };
    };

    #==========================================================================
    # AUTO-SCAN TIMER (if enabled)
    #==========================================================================
    systemd.timers.ai-bible-scan = lib.mkIf cfg.features.autoGeneration {
      description = "AI Bible automatic scan timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.codebase.scanInterval;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    systemd.services.ai-bible-scan = lib.mkIf cfg.features.autoGeneration {
      description = "AI Bible codebase scan";
      after = [ "ai-bible.service" ];
      requires = [ "ai-bible.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${scanScript}";
        User = "ai-bible";
        Group = "ai-bible";
      };
    };

    #==========================================================================
    # POST-BUILD HOOK (trigger scan after successful rebuild)
    #==========================================================================
    system.activationScripts.ai-bible-post-build = lib.mkIf cfg.features.autoGeneration {
      text = ''
        # Trigger AI Bible scan after system activation
        if systemctl is-active --quiet ai-bible.service; then
          ${scanScript} &
        fi
      '';
    };

    #==========================================================================
    # NETWORKING
    #==========================================================================
    networking.firewall = lib.mkIf cfg.features.webApi {
      allowedTCPPorts = [ cfg.port ];
    };

    #==========================================================================
    # HELPFUL ALIASES
    #==========================================================================
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "ai-bible-scan" ''
        ${scanScript}
        echo "AI Bible scan triggered. Check status at http://localhost:${toString cfg.port}"
      '')

      (pkgs.writeShellScriptBin "ai-bible-status" ''
        ${pkgs.curl}/bin/curl -s http://localhost:${toString cfg.port}/api/status | ${pkgs.jq}/bin/jq
      '')
    ];
  };
}
