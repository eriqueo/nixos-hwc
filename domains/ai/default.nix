# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  imports = [
    ./options.nix
    ./ollama/index.nix  # Explicitly use index.nix (Charter compliant)
    ./open-webui/default.nix  # TODO: migrate to index.nix
    ./local-workflows/default.nix  # TODO: migrate to index.nix
    ./mcp/default.nix  # TODO: migrate to index.nix
    ./cloud/default.nix  # TODO: migrate to index.nix
    ./router/default.nix  # TODO: migrate to index.nix
    ./agent/default.nix  # TODO: migrate to index.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
