# domains/secrets/declarations/caddy.nix
{ lib, ... }:
{
  options.hwc.secrets.caddy = {
    certificate = lib.mkOption {
      type = lib.types.str;
      description = "Path to the TLS certificate for hwc-server.ocelot-wahoo.ts.net";
    };
    key = lib.mkOption {
      type = lib.types.str;
      description = "Path to the TLS private key for hwc-server.ocelot-wahoo.ts.net";
    };
  };
}
