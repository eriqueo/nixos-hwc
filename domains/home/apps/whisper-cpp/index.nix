# domains/home/apps/whisper-cpp/index.nix
#
# whisper.cpp (CUDA build on machines with NVIDIA) plus declarative model
# management. Each requested model is fetched once via fetchurl (hash-pinned)
# and symlinked into modelsDir so `whisper-cli -m <modelsDir>/ggml-<name>.bin`
# resolves without imperative downloads.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.whisper-cpp;

  # Upstream GGML weights from https://huggingface.co/ggerganov/whisper.cpp
  # Add new entries by running:
  #   nix hash file --type sha256 --base32 <local-copy>
  # then `nix store add-file <local-copy>` to seed the store without redownload.
  knownModels = {
    "large-v3"  = "1qnijhsv47x1vx2vixy4jr8n0k6q8ham9ggrqh1m53dr82s85lb4";
    "medium.en" = "0mj3vbvaiyk5x2ids9zlp2g94a01l4qar9w109qcg3ikg0sfjdyc";
  };

  fetchModel = name: pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${name}.bin";
    sha256 = knownModels.${name};
  };

  whisperPkg =
    if cfg.cuda
    then pkgs.whisper-cpp.override { cudaSupport = true; }
    else pkgs.whisper-cpp;

  modelFiles = lib.listToAttrs (map (m: {
    name = "${cfg.modelsDir}/ggml-${m}.bin";
    value = { source = fetchModel m; };
  }) cfg.models);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.whisper-cpp = {
    enable = lib.mkEnableOption "whisper.cpp speech-to-text with declarative models";

    cuda = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build whisper-cpp with CUDA backend (NVIDIA GPUs only).";
    };

    models = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames knownModels));
      default = [ "medium.en" ];
      example = [ "large-v3" "medium.en" ];
      description = "GGML model names to install. Symlinked into modelsDir as ggml-<name>.bin.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/models/whisper";
      description = "Directory where model symlinks live. Absolute path.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ whisperPkg ];

    # home.file paths must be relative to $HOME — strip the prefix.
    home.file = lib.mapAttrs' (path: spec:
      lib.nameValuePair (lib.removePrefix "${config.home.homeDirectory}/" path) spec
    ) modelFiles;
  };
}
