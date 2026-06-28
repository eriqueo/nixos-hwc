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

  paths = config.hwc.paths;
  liquidBase = "https://huggingface.co/LiquidAI";
  nomicBase  = "https://huggingface.co/nomic-ai";

  # One submodule type, parametrised by per-service defaults. Lets gpu/cpu/embed
  # share the same shape so the implementation below can iterate over
  # `[ "gpu" "cpu" "embed" ]` without three near-identical option trees.
  mkLlamaService = { defaults }: lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this llama-server instance";

      port = lib.mkOption {
        type = lib.types.port;
        default = defaults.port;
        description = "Loopback port for this llama-server instance.";
      };

      modelFile = lib.mkOption {
        type = lib.types.str;
        default = defaults.modelFile;
        description = "GGUF filename under hwc.server.ai.llamaCpp.modelsDir.";
      };

      modelUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = defaults.modelUrl or null;
        description = ''
          Source URL for one-time model download via ExecStartPre.
          Set to null to disable auto-download (assumes file exists).
        '';
      };

      contextSize = lib.mkOption {
        type = lib.types.int;
        default = defaults.contextSize or 8192;
        description = "Context window in tokens (-c).";
      };

      gpuLayers = lib.mkOption {
        type = lib.types.int;
        default = defaults.gpuLayers or 0;
        description = ''
          Layers to offload to GPU (-ngl). 999 = all, 0 = CPU-only.
          For embedding models on the Quadro P1000, 999 is safe (sub-1GB VRAM).
        '';
      };

      threads = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = defaults.threads or null;
        description = ''
          CPU threads (-t). null = let llama.cpp pick. On i7-8700K
          (6c/12t), 6 is usually optimal for CPU inference (one thread
          per physical core; HT rarely helps memory-bound workloads).
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaults.extraArgs or [];
        description = "Extra llama-server arguments appended verbatim.";
      };
    };
  };

  # Per-architecture CUDA override. The cached llama-cpp binary targets
  # sm_75+ only; Pascal (sm_61) needs a local rebuild. We swap the existing
  # -DCMAKE_CUDA_ARCHITECTURES flag rather than appending so CMake doesn't
  # see two definitions. CMake wants integers (61), not version strings
  # (6.1), so strip dots from user-supplied capabilities.
  cmakeArchList =
    if cfg.cudaCapabilities == null then null
    else lib.concatStringsSep ";"
      (map (c: lib.replaceStrings [ "." ] [ "" ] c) cfg.cudaCapabilities);

  # Base package. null (default) = use pkgs.llama-cpp as built by the host's
  # global nixpkgs.config.cudaSupport (server's stable-cuda set has it on).
  # On hosts whose pkgs set does NOT enable cudaSupport globally (the unstable
  # laptop), set cudaSupport = true to force the CUDA backend via a per-package
  # override — the whisper-cpp / blender precedent — so -ngl actually offloads.
  basePkg =
    if cfg.cudaSupport == null then pkgs.llama-cpp
    else pkgs.llama-cpp.override { cudaSupport = cfg.cudaSupport; };

  llamaCppPkg =
    if cfg.cudaCapabilities == null then basePkg
    else basePkg.overrideAttrs (old: {
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

  mkService = { name, svcCfg, hardening, resources ? {} }: {
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
    } // hardening // resources;
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
    # embed is GPU-resident (-ngl 999) but can silently fall back to CPU when the
    # 4GB card is full (the chat model + its KV cache can fill it). The resource
    # caps ensure that fallback de-prioritises against the camera/NVR stack
    # (frigate) instead of starving it — defence-in-depth behind the daemon's
    # content-hash dedup, which is what actually keeps embed request volume near
    # zero when the vault is quiet.
    { name = "embed"; svcCfg = cfg.embed; hardening = gpuHardening;
      resources = { CPUWeight = 20; Nice = 10; }; }
  ];

  enabledServices = lib.filter (s: s.svcCfg.enable) subServices;

in
{
  #========================================================================
  # OPTIONS
  #========================================================================
  options.hwc.server.ai.llamaCpp = {
    enable = lib.mkEnableOption "llama.cpp native inference services";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Service user (Charter: native services run as eric:users).";
    };

    modelsDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.ai.models}/llama-cpp";
      description = ''
        Directory storing downloaded GGUF model files. Derived from
        hwc.paths.ai.models so it respects the path-abstraction contract.
      '';
    };

    cudaSupport = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = ''
        Force the llama-cpp CUDA backend on/off via a per-package
        `.override { cudaSupport = ...; }`. null (default) = leave pkgs.llama-cpp
        as-is, trusting the host's global nixpkgs.config.cudaSupport — correct
        for the server, whose stable-cuda pkgs set already builds with CUDA.

        Set true on hosts whose pkgs set does NOT enable cudaSupport globally
        (e.g. the unstable laptop's pkgs-laptop). Without it, -ngl is silently
        ignored and inference runs on the CPU. Follows the whisper-cpp / blender
        per-package override precedent. Setting this forces a local llama-cpp
        rebuild; the CUDA toolkit itself comes from cache.nixos-cuda.org.
      '';
    };

    cudaCapabilities = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [ "6.1" ];
      description = ''
        Override CMAKE_CUDA_ARCHITECTURES for the GPU build. null = use the
        nixpkgs default (currently 75;80;86;89;90;100;120 — modern data-center
        cards only). Set to [ "6.1" ] for Pascal (Quadro P1000, GTX 10xx),
        [ "7.5" ] for Turing (RTX 20xx, Quadro RTX), etc.

        Setting this forces a local rebuild — the binary cache only ships
        the default arch list. Build time on an i7-8700K is ~15-25 minutes.
      '';
    };

    gpu = lib.mkOption {
      type = mkLlamaService {
        defaults = {
          port = 11500;
          modelFile = "LFM2-2.6B-Q4_K_M.gguf";
          modelUrl = "${liquidBase}/LFM2-2.6B-GGUF/resolve/main/LFM2-2.6B-Q4_K_M.gguf";
          contextSize = 8192;
          gpuLayers = 999;
          threads = null;
          extraArgs = [];
        };
      };
      default = {};
      description = ''
        GPU-accelerated chat service. Default: LFM2-2.6B Q4 (~1.5 GB) fully
        offloaded to the local NVIDIA card. Sized for the Quadro P1000.
      '';
    };

    cpu = lib.mkOption {
      type = mkLlamaService {
        defaults = {
          port = 11501;
          modelFile = "LFM2-24B-A2B-Q4_K_M.gguf";
          modelUrl = "${liquidBase}/LFM2-24B-A2B-GGUF/resolve/main/LFM2-24B-A2B-Q4_K_M.gguf";
          contextSize = 8192;
          gpuLayers = 0;
          threads = null;
          extraArgs = [];
        };
      };
      default = {};
      description = ''
        CPU-only chat service. Default: LFM2-24B-A2B Q4 (~14 GB) loaded in
        host RAM. Memory-bandwidth bound; ~6 tok/s on i7-8700K because only
        ~2 B parameters are active per token (MoE sparsity).
      '';
    };

    embed = lib.mkOption {
      type = mkLlamaService {
        defaults = {
          port = 11502;
          modelFile = "nomic-embed-text-v1.5.Q5_K_M.gguf";
          modelUrl = "${nomicBase}/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q5_K_M.gguf";
          # nomic-embed-text was trained at 2048 tokens; exceeding causes
          # GGML_ASSERT crashes in slot mgmt. Keep n_ctx == training context.
          contextSize = 2048;
          gpuLayers = 999;
          threads = null;
          extraArgs = [
            "--embeddings" "--pooling" "mean"
            # Batch / micro-batch sized to fit several chunks comfortably.
            "--ubatch-size" "4096"
            "--batch-size" "4096"
            # --parallel 1 gets silently overridden to 4 by kv_unified, and
            # the build doesn't accept --no-kv-unified. Accept 4 slots; the
            # daemon-side chunk cap keeps each chunk well under per-slot
            # context (2048 / 4 = 512 with unified, full 2048 otherwise).
          ];
        };
      };
      default = {};
      description = ''
        Embeddings service. Default: nomic-embed-text-v1.5 Q5 (~270 MB,
        768-dim vectors) on the GPU. Powers RAG retrieval over the brain
        vault (consumed by persona-daemon).

        Note: llama.cpp's flag is `--embeddings` (with the 's'); the
        OpenAI-compat endpoint is `/v1/embeddings`. extraArgs already
        includes both that flag and `--pooling mean` for sentence-level
        vectors.
      '';
    };
  };

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
