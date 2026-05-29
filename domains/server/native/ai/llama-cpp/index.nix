# domains/server/native/ai/llama-cpp/index.nix
#
# Implementation for hwc.server.ai.llamaCpp.
#
# Architecture: one nixpkgs llama-cpp binary (CUDA-built via global
# cudaSupport) drives two systemd services. The GPU service offloads
# all layers to the Quadro P1000; the CPU service runs the 24B MoE in
# host RAM with -ngl 0 so cuBLAS is loaded but unused.
#
# Model files are downloaded lazily via ExecStartPre into modelsDir.
# Files persist across reboots; the download script is idempotent.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.ai.llamaCpp;

  # Per-architecture CUDA override. The cached llama-cpp binary targets
  # sm_75+ only; Pascal (sm_61) needs a local rebuild. We swap the existing
  # -DCMAKE_CUDA_ARCHITECTURES flag rather than appending so CMake doesn't
  # see two definitions.
  llamaCppPkg =
    if cfg.cudaCapabilities == null then pkgs.llama-cpp
    else pkgs.llama-cpp.overrideAttrs (old: {
      cmakeFlags = map (f:
        if lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f
        then "-DCMAKE_CUDA_ARCHITECTURES:STRING=${lib.concatStringsSep ";" cfg.cudaCapabilities}"
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

  mkServerArgs = svcCfg: gpuLayers: extraThreads:
    [
      "--model" "${cfg.modelsDir}/${svcCfg.modelFile}"
      "--host" "127.0.0.1"
      "--port" (toString svcCfg.port)
      "-c" (toString svcCfg.contextSize)
      "-ngl" (toString gpuLayers)
    ]
    ++ lib.optionals (extraThreads != null) [ "-t" (toString extraThreads) ]
    ++ svcCfg.extraArgs;

  mkService = { name, svcCfg, gpuLayers, threads, hardening }: {
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
        ++ mkServerArgs svcCfg gpuLayers threads);

      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = "2h";  # first-boot model download can be huge
    } // hardening;
  };

  gpuHardening = {
    # GPU service needs /dev/nvidia*; do not lock device access.
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    ReadWritePaths = [ cfg.modelsDir ];
  };

  cpuHardening = {
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    PrivateDevices = true;        # CPU service: no device access needed
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    ReadWritePaths = [ cfg.modelsDir ];
  };

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
    # GPU service: LFM2-2.6B Q4 on Quadro P1000
    #========================================================================
    systemd.services.llama-gpu = lib.mkIf cfg.gpu.enable (mkService {
      name = "gpu";
      svcCfg = cfg.gpu;
      gpuLayers = cfg.gpu.gpuLayers;
      threads = null;
      hardening = gpuHardening;
    });

    #========================================================================
    # CPU service: LFM2-24B-A2B Q4 in RAM
    #========================================================================
    systemd.services.llama-cpu = lib.mkIf cfg.cpu.enable (mkService {
      name = "cpu";
      svcCfg = cfg.cpu;
      gpuLayers = 0;
      threads = cfg.cpu.threads;
      hardening = cpuHardening;
    });

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.enable -> (cfg.gpu.enable || cfg.cpu.enable);
        message = "hwc.server.ai.llamaCpp.enable is true but no sub-service is enabled. Set gpu.enable and/or cpu.enable.";
      }
      {
        assertion = !(cfg.gpu.enable && cfg.cpu.enable) || cfg.gpu.port != cfg.cpu.port;
        message = "hwc.server.ai.llamaCpp gpu.port and cpu.port must differ.";
      }
      {
        assertion = cfg.gpu.enable -> (config.hwc.system.hardware.gpu.type or "none") == "nvidia";
        message = "hwc.server.ai.llamaCpp.gpu requires hwc.system.hardware.gpu.type = \"nvidia\".";
      }
      {
        assertion = cfg.modelsDir != null && lib.hasPrefix "/" cfg.modelsDir;
        message = "hwc.server.ai.llamaCpp.modelsDir must be an absolute path (derived from hwc.paths.ai.models on servers).";
      }
    ];
  };
}
