# domains/ai/default.nix
{ config, lib, ... }:
let
  cfg = config.hwc.ai;
in
{
  imports = [
    ./options.nix
    # subdomains will be added here by PR 2
  ];

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = true;
      message = "AI domain loaded";
    }];
  };
}
