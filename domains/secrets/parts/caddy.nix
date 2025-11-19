# domains/secrets/parts/caddy.nix
{ config, lib, ... }:
{
  # Only declare caddy secrets when caddy user exists (server only)
  # Prevents chown errors on laptops that don't have the caddy user
  config = lib.mkIf (builtins.hasAttr "caddy" config.users.users) {
    age.secrets."caddy-cert" = {
      file = ./caddy/hwc.ocelot-wahoo.ts.net.crt.age;
      owner = "caddy";
      group = "caddy";
    };
    age.secrets."caddy-key" = {
      file = ./caddy/hwc.ocelot-wahoo.ts.net.key.age;
      owner = "caddy";
      group = "caddy";
    };

    hwc.secrets.caddy = {
      certificate = config.age.secrets."caddy-cert".path;
      key = config.age.secrets."caddy-key".path;
    };
  };
}
