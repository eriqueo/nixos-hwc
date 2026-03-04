{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.hwc.server.shared = {
    # accumulator used by services to publish reverse proxy routes
    routes = mkOption {
      internal = true;
      type = types.listOf (types.attrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes (service-provided).";
    };
  };

  # NOTE: Container helpers are in pure.nix (mkContainer) and infra.nix (mkInfraContainer)
  # Import them directly: import ../_shared/pure.nix { inherit lib pkgs; }
  # These module-based helpers are kept for backwards compatibility only
  config.hwc.server.shared.lib = {
    # Route helper for reverse proxy configuration
    mkRoute = { path, upstream, stripPrefix ? false }:
      { inherit path upstream stripPrefix; };
  };
}
