# domains/secrets/parts/caddy.nix
{ config, lib, ... }:
let
  # Select cert based on hostname
  hostname = config.networking.hostName;
  certFile = if hostname == "hwc-xps"
    then ./caddy/hwc-xps.ocelot-wahoo.ts.net.crt.age
    else ./caddy/hwc.ocelot-wahoo.ts.net.crt.age;
  keyFile = if hostname == "hwc-xps"
    then ./caddy/hwc-xps.ocelot-wahoo.ts.net.key.age
    else ./caddy/hwc.ocelot-wahoo.ts.net.key.age;
in
{
  # Use root:root ownership for caddy secrets to avoid chown errors on laptops
  # Caddy service runs as root and can read these files
  config = {
    age.secrets."caddy-cert" = {
      file = certFile;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    age.secrets."caddy-key" = {
      file = keyFile;
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
