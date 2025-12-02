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
    # agent will be added later PR 5
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
