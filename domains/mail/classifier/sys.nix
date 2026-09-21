{ config, inputs, lib, pkgs, ... }:
let
  cfg = config.hwc.mail.classifier.system;
  # The fleet package set has CUDA enabled for GPU workloads. Import the same
  # pinned nixpkgs revision with CUDA disabled so every transitive Python
  # dependency (including transformers' torch) stays CPU-only.
  cpuPkgs = import inputs.nixpkgs {
    inherit (pkgs) system;
    config = {
      allowUnfree = true;
      cudaSupport = false;
    };
  };
  cpuPython = cpuPkgs.python3Packages;
  laya = cpuPython.buildPythonPackage rec {
    pname = "laya";
    version = "0.3.5";
    pyproject = true;
    src = pkgs.fetchFromGitHub {
      owner = "NandhaKishorM";
      repo = "laya";
      rev = "573e5b62696ba441230cd6be71d593331b5d23af";
      hash = "sha256-cbUuLBMBC7WwqAf7m7Ihs6qkx7H7FdwhPVMWfgnfg8c=";
    };
    build-system = [ cpuPython.setuptools ];
    # This service is deliberately CPU-only. The fleet enables CUDA globally,
    # so plain `torch` would pull a multi-gigabyte GPU closure it cannot use.
    dependencies = with cpuPython; [
      torchWithoutCuda transformers safetensors huggingface-hub numpy
    ];
    doCheck = false;
  };
  python = cpuPkgs.python3.withPackages (_: [ laya ]);
  runtime = pkgs.writeShellApplication {
    name = "mail-classifier-runtime";
    runtimeInputs = [ python pkgs.notmuch ];
    text = ''
      exec ${python}/bin/python3 ${inputs.system-one}/scripts/mail_classifier.py "$@"
    '';
  };
  modelServer = pkgs.writeShellScript "mail-classifier-model" ''
    exec ${runtime}/bin/mail-classifier-runtime serve \
      --socket /run/hwc-mail-classifier/laya.sock \
      --cache /var/cache/hwc-mail-classifier/huggingface \
      --model convaiinnovations/laya \
      --revision 00c37c405e3c3ad73ee070227614c89cda06b99e
  '';
in
{
  # OPTIONS
  options.hwc.mail.classifier.system.enable = lib.mkEnableOption "resident CPU Laya mail-classifier";

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ runtime ];

    systemd.services.mail-classifier-model = {
      description = "Laya local mail-classifier model";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HF_HOME = "/var/cache/hwc-mail-classifier/huggingface";
        HF_HUB_CACHE = "/var/cache/hwc-mail-classifier/huggingface/hub";
        HF_XET_CACHE = "/var/cache/hwc-mail-classifier/huggingface/xet";
        XDG_CACHE_HOME = "/var/cache/hwc-mail-classifier";
      };
      serviceConfig = {
        Type = "simple";
        User = lib.mkForce "eric";
        Group = "users";
        RuntimeDirectory = "hwc-mail-classifier";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "hwc/mail-classifier";
        StateDirectoryMode = "0700";
        CacheDirectory = "hwc-mail-classifier";
        CacheDirectoryMode = "0700";
        ExecStart = modelServer;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5m";
        TimeoutStopSec = "30s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictSUIDSGID = true;
      };
    };

    # CRITICAL: ledger is retained indefinitely and covered by /var/lib/hwc
    # backups. REPLACEABLE: the pinned model cache can be deleted and rebuilt.
    systemd.tmpfiles.rules = [
      "d /var/lib/hwc/mail-classifier 0700 eric users -"
      "d /var/cache/hwc-mail-classifier 0700 eric users -"
      "e /var/cache/hwc-mail-classifier - - - 30d"
    ];
  };
}
