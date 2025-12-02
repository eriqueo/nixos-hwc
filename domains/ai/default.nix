# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  imports = [
    ./options.nix
<<<<<<< HEAD
    # subdomains will be added here by PR 2
=======
    ./ollama/default.nix
    ./open-webui/default.nix
    ./local-workflows/default.nix
    ./mcp/default.nix
    # agent will be added later PR 5
>>>>>>> feat/ai-copy-modules
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
