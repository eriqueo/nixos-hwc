# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  imports = [
    ./options.nix
    ./ollama/default.nix
    ./open-webui/default.nix
    ./local-workflows/default.nix
    ./mcp/default.nix
    ./cloud/default.nix
    ./router/default.nix
    ./agent/default.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
