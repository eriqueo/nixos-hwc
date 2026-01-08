# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  imports = [
    ./options.nix
    ./ollama/index.nix
    ./open-webui/index.nix
    ./local-workflows/index.nix
    ./mcp/index.nix
    ./cloud/index.nix
    ./router/index.nix
    ./agent/index.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
