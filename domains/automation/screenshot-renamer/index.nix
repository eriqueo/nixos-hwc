# Owns scheduling and containment; the pinned app owns OCR, proposals and receipts.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.automation.screenshotRenamer;
  paths = config.hwc.paths;
  app = inputs.screenshot-renamer.packages.${pkgs.system}.default;
  pi = pkgs.callPackage ../../home/apps/pi/parts/package.nix {};
  root = "${paths.user.inbox}/screenshots";
  state = "${paths.state}/screenshot-renamer";
  settings = pkgs.writeText "screenshot-renamer.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit root state;
    owner = cfg.ownerHost;
    pi = lib.getExe pi;
    tesseract = lib.getExe pkgs.tesseract;
    key_file = config.age.secrets.pi-dx1-api-key.path;
    allow_apply = cfg.mode == "apply";
    coverage = 0.5;
    notify_url = config.hwc.notifications.notify.url;
  });
  command = action: "${lib.getExe app} --config ${settings} ${action}";
  base = {
    Type = "oneshot";
    User = lib.mkForce "eric";
    Group = "users";
    SupplementaryGroups = [ "secrets" ];
    UMask = "0077";
    StateDirectory = "hwc/screenshot-renamer";
    StateDirectoryMode = "0700";
    ProtectSystem = "strict";
    ProtectHome = "tmpfs";
    BindReadOnlyPaths = [ root ];
    ReadWritePaths = [ state ];
    PrivateTmp = true;
    NoNewPrivileges = true;
    MemoryMax = "1G";
    TasksMax = 64;
    TimeoutStartSec = "615s";
    TimeoutStopSec = "15s";
    KillMode = "control-group";
  };
  timer = calendar: {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = calendar; Persistent = true; RandomizedDelaySec = "30s"; };
  };
in {
  options.hwc.automation.screenshotRenamer = {
    enable = lib.mkEnableOption "Single-owner screenshot proposal timer";
    ownerHost = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Runtime hostname guard for the only enabled processing owner";
    };
    mode = lib.mkOption {
      type = lib.types.enum [ "shadow" "apply" ];
      default = "shadow";
      description = "Apply still requires human holdout evidence and filesystem recovery proof";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = config.hwc.automation.inboxJanitor.enable;
        message = "Screenshot processing must run beside the single-owner inbox janitor"; }
      { assertion = config.hwc.data.borg.enable;
        message = "Screenshot receipts and recovery copies require Borg backup"; }
      { assertion = paths.state == "/var/lib/hwc";
        message = "Screenshot StateDirectory must match hwc.paths.state"; }
    ];
    environment.systemPackages = [ app ];
    environment.etc."screenshot-renamer.json".source = settings;
    # CRITICAL: consistent online SQLite snapshot and unresolved source copies.
    # The app caps recovery at 512 MiB and pauses effects when full; Borg retains
    # archived snapshots under its existing bounded prune policy.
    hwc.data.borg.sources = lib.mkAfter [ "${state}/backups" "${state}/recovery" ];
    systemd.services.screenshot-renamer = {
      description = "Propose screenshot names with isolated Pi and DX2";
      after = [ "network-online.target" "syncthing.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = base // {
        BindReadOnlyPaths = lib.optionals (cfg.mode == "shadow") [ root ] ++ [ config.age.secrets.pi-dx1-api-key.path ];
        BindPaths = lib.optionals (cfg.mode == "apply") [ root ];
        ExecStartPre = command "init";
        ExecStart = command cfg.mode;
      };
    };
    systemd.timers.screenshot-renamer = timer "*:0/15";
    # This checker does not depend on the worker succeeding or being scheduled.
    systemd.services.screenshot-renamer-check = {
      description = "Check screenshot progress and report changed failures";
      serviceConfig = base // { ExecStart = command "check"; TimeoutStartSec = "30s"; };
    };
    systemd.timers.screenshot-renamer-check = timer "*:0/5";
    systemd.services.screenshot-renamer-cleanup = {
      description = "Back up screenshot receipts and release resolved copies";
      serviceConfig = base // { ExecStart = command "cleanup"; };
    };
    systemd.timers.screenshot-renamer-cleanup = timer "daily";
  };
}
