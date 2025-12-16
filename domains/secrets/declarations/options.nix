# domains/secrets/declarations/options.nix
# Toggle for importing all agenix secret declarations

{ lib, ... }:
{
  options.hwc.secrets.declarations = {
    enable = lib.mkEnableOption "secret declarations aggregation" // {
      default = true;
    };
  };
}
