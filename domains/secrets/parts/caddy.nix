# domains/secrets/parts/caddy.nix
{ config, ... }:
{
  # Use root:root ownership for caddy secrets to avoid chown errors on laptops
  # Caddy service runs as root and can read these files
  config = {
    age.secrets."caddy-cert" = {
      file = ./caddy/hwc.ocelot-wahoo.ts.net.crt.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    age.secrets."caddy-key" = {
      file = ./caddy/hwc.ocelot-wahoo.ts.net.key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    hwc.secrets.caddy = {
      certificate = config.age.secrets."caddy-cert".path;
      key = config.age.secrets."caddy-key".path;
    };
  };
}
