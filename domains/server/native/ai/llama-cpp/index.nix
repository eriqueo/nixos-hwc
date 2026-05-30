# domains/server/native/ai/llama-cpp/index.nix
#
# Implementation for hwc.server.ai.llamaCpp.
#
# Architecture: one nixpkgs llama-cpp binary (CUDA-built via global
# cudaSupport) drives N systemd services, all instances of the same
# `mkService` helper. Currently: llama-gpu, llama-cpu, llama-embed.
#
# Model files are downloaded lazily via ExecStartPre into modelsDir.
# Files persist across reboots; the download script is idempotent.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.ai.llamaCpp;

  # Per-architecture CUDA override. The cached llama-cpp binary targets
  # sm_75+ only; Pascal (sm_61) needs a local rebuild. We swap the existing
  # -DCMAKE_CUDA_ARCHITECTURES flag rather than appending so CMake doesn't
  # see two definitions. CMake wants integers (61), not version strings
  # (6.1), so strip dots from user-supplied capabilities.
  cmakeArchList =
    if cfg.cudaCapabilities == null then null
    else lib.concatStringsSep ";"
      (map (c: lib.replaceStrings [ "." ] [ "" ] c) cfg.cudaCapabilities);

  llamaCppPkg =
    if cfg.cudaCapabilities == null then pkgs.llama-cpp
    else pkgs.llama-cpp.overrideAttrs (old: {
      cmakeFlags = map (f:
        if lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f
        then "-DCMAKE_CUDA_ARCHITECTURES:STRING=${cmakeArchList}"
        else f
      ) (old.cmakeFlags or []);
    });

  llamaBin = "${llamaCppPkg}/bin/llama-server";

  fetchScript = pkgs.writeShellApplication {
    name = "llama-cpp-fetch-model";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      set -euo pipefail
      dest="$1"
      url="$2"
      mkdir -p "$(dirname "$dest")"
      if [ -s "$dest" ]; then
        echo "Model present: $dest"
        exit 0
      fi
      echo "Downloading $url -> $dest"
      curl -fL --retry 5 --retry-delay 30 \
        --connect-timeout 30 \
        --progress-bar \
        -o "$dest.partial" "$url"
      mv "$dest.partial" "$dest"
      echo "Download complete: $(du -h "$dest" | cut -f1) $dest"
    '';
  };

  # All llama-server CLI arguments derived purely from the submodule shape.
  # Adding a new sub-service requires no changes here.
  mkServerArgs = svcCfg:
    [
      "--model" "${cfg.modelsDir}/${svcCfg.modelFile}"
      "--host" "127.0.0.1"
      "--port" (toString svcCfg.port)
      "-c" (toString svcCfg.contextSize)
      "-ngl" (toString svcCfg.gpuLayers)
    ]
    ++ lib.optionals (svcCfg.threads != null) [ "-t" (toString svcCfg.threads) ]
    ++ svcCfg.extraArgs;

  mkService = { name, svcCfg, hardening }: {
    description = "llama.cpp inference server (${name})";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = [ pkgs.coreutils ];

    serviceConfig = {
      Type = "simple";
      User = lib.mkForce cfg.user;
      Group = "users";
      StateDirectory = "hwc/llama-cpp";
      StateDirectoryMode = "0750";

      ExecStartPre = lib.mkIf (svcCfg.modelUrl != null) [
        "${fetchScript}/bin/llama-cpp-fetch-model ${cfg.modelsDir}/${svcCfg.modelFile} ${svcCfg.modelUrl}"
      ];

      ExecStart = lib.concatStringsSep " " ([ llamaBin ]
        ++ mkServerArgs svcCfg);

      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "2h";  # first-boot model download can be huge
    } // hardening;
  };

  # GPU services need /dev/nvidia*; do not lock device access.
  gpuHardening = {
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    ReadWritePaths = [ cfg.modelsDir ];
  };

  # CPU service has no device-access need; tighten further.
  cpuHardening = gpuHardening // {
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
  };

  # All declared sub-services with their hardening profile.
  # Adding a new instance (e.g., a vision backend) = one entry here.
  subServices = [
    { name = "gpu";   svcCfg = cfg.gpu;   hardening = gpuHardening; }
    { name = "cpu";   svcCfg = cfg.cpu;   hardening = cpuHardening; }
    { name = "embed"; svcCfg = cfg.embed; hardening = gpuHardening; }
  ];

  enabledServices = lib.filter (s: s.svcCfg.enable) subServices;

in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #========================================================================
    # State + model directory
    #========================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.modelsDir} 0750 ${cfg.user} users -"
    ];

    #========================================================================
    # Systemd services — one per enabled sub-service
    #========================================================================
    systemd.services = lib.listToAttrs (map (s: {
      name = "llama-${s.name}";
      value = mkService s;
    }) enabledServices);

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.enable -> enabledServices != [];
        message = ''
          hwc.server.ai.llamaCpp.enable is true but no sub-service is enabled.
          Set at least one of gpu.enable / cpu.enable / embed.enable.
        '';
      }
      {
        assertion = let
          ports = map (s: s.svcCfg.port) enabledServices;
        in lib.length ports == lib.length (lib.unique ports);
        message = ''
          hwc.server.ai.llamaCpp: all enabled sub-services must use distinct
          ports. Enabled: ${lib.concatMapStringsSep ", "
            (s: "${s.name}=${toString s.svcCfg.port}") enabledServices}.
        '';
      }
      {
        assertion = (cfg.gpu.enable || cfg.embed.enable) ->
          (config.hwc.system.hardware.gpu.type or "none") == "nvidia";
        message = ''
          hwc.server.ai.llamaCpp gpu/embed services require
          hwc.system.hardware.gpu.type = "nvidia".
        '';
      }
      {
        assertion = cfg.modelsDir != null && lib.hasPrefix "/" cfg.modelsDir;
        message = "hwc.server.ai.llamaCpp.modelsDir must be an absolute path (derived from hwc.paths.ai.models on servers).";
      }
    ];
  };
}
