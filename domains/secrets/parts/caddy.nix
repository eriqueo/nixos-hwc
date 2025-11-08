# domains/secrets/parts/caddy.nix
{ config, ... }:
{
  config = {
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
