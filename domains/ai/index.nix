# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./framework/index.nix     # Hardware-agnostic AI framework (NEW)
    ./ollama/index.nix
    ./open-webui/index.nix
    ./local-workflows/index.nix
    ./mcp/index.nix
    ./cloud/index.nix
    ./router/index.nix
    ./agent/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };

}
