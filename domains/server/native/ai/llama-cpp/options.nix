# domains/server/native/ai/llama-cpp/options.nix
#
# llama.cpp inference services — native systemd, runs as eric:users.
# Namespace: hwc.server.ai.llamaCpp (matches folder; `native/` is folder-only).
#
# Three services share one binary (pkgs.llama-cpp, CUDA-built):
#   - gpu:   small dense model on the local NVIDIA card (-ngl 999)
#   - cpu:   big MoE model in RAM, GPU disabled (-ngl 0)
#   - embed: small embedding model on the GPU (-ngl 999, --embeddings)
#
# All three are instances of one submodule type (`mkLlamaService`) — adding
# a fourth (e.g., a vision backend, an alt-quant) is a one-liner here.
#
# All listen on 127.0.0.1; Caddy fronts them on the public tailnet.
{ lib, config, ... }:
let
  paths = config.hwc.paths;
  liquidBase = "https://huggingface.co/LiquidAI";
  nomicBase  = "https://huggingface.co/nomic-ai";

  # One submodule type, parametrised by per-service defaults. Lets gpu/cpu/embed
  # share the same shape so the implementation in index.nix can iterate over
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
            # Force single slot. --parallel 1 alone is silently overridden
            # by kv_unified default (log: "setting n_parallel = 4 and
            # kv_unified = true"). --no-kv-unified lets --parallel 1 stick.
            "--parallel" "1"
            "--no-kv-unified"
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
}
