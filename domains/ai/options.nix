# domains/ai/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.ai = {
    enable = mkEnableOption "AI domain - top level enable";
    # provide minimal top-level defaults; submodules define details.
  };
}
