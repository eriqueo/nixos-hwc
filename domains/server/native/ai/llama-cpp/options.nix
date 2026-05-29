# domains/server/native/ai/llama-cpp/options.nix
#
# llama.cpp inference services — native systemd, runs as eric:users.
# Namespace: hwc.server.ai.llamaCpp (matches folder; `native/` is folder-only).
#
# Two services share one binary (pkgs.llama-cpp, CUDA-built via
# nixpkgs.config.cudaSupport):
#   - gpu: small dense model on the local NVIDIA card (-ngl 999)
#   - cpu: big MoE model in RAM, GPU disabled (-ngl 0)
#
# Both listen on 127.0.0.1; Caddy fronts them on the public tailnet.
{ lib, config, ... }:
let
  paths = config.hwc.paths;
  hfBase = "https://huggingface.co/LiquidAI";
in
{
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

    gpu = {
      enable = lib.mkEnableOption "GPU-accelerated llama-server (CUDA)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 11500;
        description = "Loopback port for the GPU llama-server.";
      };

      modelFile = lib.mkOption {
        type = lib.types.str;
        default = "LFM2-2.6B-Q4_K_M.gguf";
        description = "GGUF filename under modelsDir.";
      };

      modelUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "${hfBase}/LFM2-2.6B-GGUF/resolve/main/LFM2-2.6B-Q4_K_M.gguf";
        description = ''
          Source URL for one-time model download via ExecStartPre.
          Set to null to disable auto-download (assumes file exists).
        '';
      };

      contextSize = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Context window in tokens (-c).";
      };

      gpuLayers = lib.mkOption {
        type = lib.types.int;
        default = 999;
        description = "Layers to offload to GPU (-ngl). 999 = all.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra llama-server arguments appended verbatim.";
      };
    };

    cpu = {
      enable = lib.mkEnableOption "CPU-only llama-server (large MoE in RAM)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 11501;
        description = "Loopback port for the CPU llama-server.";
      };

      modelFile = lib.mkOption {
        type = lib.types.str;
        default = "LFM2-24B-A2B-Q4_K_M.gguf";
        description = "GGUF filename under modelsDir.";
      };

      modelUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "${hfBase}/LFM2-24B-A2B-GGUF/resolve/main/LFM2-24B-A2B-Q4_K_M.gguf";
        description = ''
          Source URL for one-time model download. ~14 GB; first boot
          will block on the download (TimeoutStartSec is set high).
        '';
      };

      contextSize = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Context window in tokens.";
      };

      threads = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          CPU threads (-t). null = let llama.cpp pick. On i7-8700K
          (6c/12t), 6 is usually optimal for inference (one thread per
          physical core; HT rarely helps memory-bound workloads).
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra llama-server arguments appended verbatim.";
      };
    };
  };
}
