{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hwc.home.apps.agent-harness;
  home = config.home.homeDirectory;
  harness = inputs.agent-harness;
  revision = inputs.agent-harness.rev or "dirty";
  contract = import ./contract.nix { inherit revision; };
  expectedManifest = pkgs.writeText "agent-harness-manifest.json" (builtins.toJSON contract);
  configDirs = map (name: "${home}/${name}") ([ ".claude" ] ++ cfg.claudeConfigDirs);
  stateValidator = pkgs.writeShellApplication {
    name = "agent-state-validate";
    runtimeInputs = with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      gawk
    ];
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./state-validate.sh} "$@"
    '';
  };
  stateSync = pkgs.writeShellApplication {
    name = "agent-state-sync";
    runtimeInputs = [
      stateValidator
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      util-linux
      openssh
      curl
      jq
    ]);
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      export AGENT_CONFIG_DIRS=${lib.escapeShellArg (lib.concatStringsSep ":" configDirs)}
      export AGENT_STATE_VALIDATOR=${stateValidator}/bin/agent-state-validate
      export AGENT_STATE_NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      exec ${pkgs.bash}/bin/bash ${./state-sync.sh} "$@"
    '';
  };
  policyHook = pkgs.writeShellScriptBin "pre-commit" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
        pkgs.ripgrep
        (pkgs.python3.withPackages (p: [ p.pyyaml ]))
        pkgs.uv
      ]
    }:$PATH
    root=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
    exec ${pkgs.bash}/bin/bash "$root/bin/harness-policy-check"
  '';
  cli = pkgs.writeShellApplication {
    name = "agent-harness";
    runtimeInputs = [
      stateSync
      stateValidator
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      openssh
      nix
      systemd
      gawk
    ]);
    text = ''
      export AGENT_HARNESS_EXPECTED_MANIFEST=${expectedManifest}
      export AGENT_HARNESS_SYSTEM_MANIFEST=/etc/agent-harness-manifest.json
      export AGENT_HARNESS_SOURCE=${lib.escapeShellArg cfg.editableSource}
      export AGENT_HARNESS_NIXOS=${lib.escapeShellArg cfg.nixosRepo}
      export AGENT_HARNESS_FLEET_HOSTS=${lib.escapeShellArg (lib.concatStringsSep ":" cfg.fleetHosts)}
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./control.sh} "$@"
    '';
  };
  doctor = pkgs.writeShellScriptBin "agent-harness-doctor" ''exec ${cli}/bin/agent-harness doctor "$@"'';
in
{
  options.hwc.home.apps.agent-harness = {
    enable = lib.mkEnableOption "shared agent harness control plane";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.agent-state";
    };
    editableSource = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.claude-config";
    };
    nixosRepo = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.nixos";
    };
    fleetHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "hwc-server"
        "hwc-laptop"
      ];
    };
    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hwc-notify.hwc.iheartwoodcraft.com:29443/notify";
      description = "hwc-notify endpoint used for state-sync failure and recovery transitions";
    };
    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".claude_dx2_home" ];
    };
    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "1min";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cli
      doctor
      stateSync
      stateValidator
      (pkgs.writeShellScriptBin "log-mistake" ''exec ${pkgs.python3}/bin/python3 ${harness}/bin/log-mistake "$@"'')
    ];

    home.file = lib.mkMerge (
      map (dir: {
        "${dir}/skills".source = harness + "/skills";
        "${dir}/agents".source = harness + "/agents";
        "${dir}/commands".source = harness + "/commands";
        "${dir}/CLAUDE.md".source = harness + "/CLAUDE.md";
        "${dir}/standing-instructions.md".source = harness + "/standing-instructions.md";
        "${dir}/engineering-principles.md".source = harness + "/engineering-principles.md";
      }) ([ ".claude" ] ++ cfg.claudeConfigDirs)
    );

    home.activation.agentHarnessMemoryLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${stateSync}/bin/agent-state-sync link || echo "agent-harness: state clone missing; run agent-harness doctor" >&2
      if [ -d ${lib.escapeShellArg cfg.editableSource}/.git ]; then
        run ${pkgs.git}/bin/git -C ${lib.escapeShellArg cfg.editableSource} config core.hooksPath ${policyHook}/bin
      fi
    '';

    systemd.user.services.agent-state-sync = {
      Unit.Description = "Synchronize mutable agent memories and mistakes ledger";
      Service = {
        Type = "oneshot";
        ExecStart = "${stateSync}/bin/agent-state-sync sync";
        SuccessExitStatus = [ 75 ];
      };
    };
    systemd.user.timers.agent-state-sync = {
      Unit.Description = "Periodic agent state synchronization";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.syncInterval;
        Unit = "agent-state-sync.service";
      };
    };
  };
}
