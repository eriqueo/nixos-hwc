# domains/home/apps/whisper-cpp/index.nix
#
# whisper.cpp (CUDA build on machines with NVIDIA) plus declarative model
# management. Each requested model is fetched once via fetchurl (hash-pinned).
# Consumers use modelPaths directly; no model directory is created in $HOME.
#
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.whisper-cpp;

  # Upstream GGML weights from https://huggingface.co/ggerganov/whisper.cpp
  # Add new entries by running:
  #   nix hash file --type sha256 --base32 <local-copy>
  # then `nix store add-file <local-copy>` to seed the store without redownload.
  # Pinned to one HF revision so a re-upload under /resolve/main/ cannot
  # break a clean rebuild against a stale hash.
  hfRevision = "5359861c739e955e79d9a303bcbc70fb988958b1";
  knownModels = {
    "base.en"   = "00nhqqvgwyl9zgyy7vk9i3n017q2wlncp5p7ymsk0cpkdp47jdx0";
    "large-v3"  = "1qnijhsv47x1vx2vixy4jr8n0k6q8ham9ggrqh1m53dr82s85lb4";
    "medium.en" = "0mj3vbvaiyk5x2ids9zlp2g94a01l4qar9w109qcg3ikg0sfjdyc";
  };

  fetchModel = name: pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/${hfRevision}/ggml-${name}.bin";
    sha256 = knownModels.${name};
  };

  whisperPkg =
    if cfg.cuda
    then pkgs.whisper-cpp.override { cudaSupport = true; }
    else pkgs.whisper-cpp;

  modelPaths = lib.genAttrs cfg.models fetchModel;


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
      description = "GGML model names to retain in the Nix store and expose through modelPaths.";
    };

    modelPaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "Hash-pinned model store files, keyed by configured model name.";
    };


  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ whisperPkg ];
    hwc.home.apps.whisper-cpp.modelPaths = modelPaths;
    # REPLACEABLE: Nix fetches and GC manage the weights. Retain even models
    # not selected by dictation; they must survive store GC for CLI use.
    home.extraDependencies = lib.attrValues modelPaths;

  };
}
