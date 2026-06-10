# domains/secrets/declarations/caddy.nix
# HWC-EXCEPTION(Law 10): option declarations outside index.nix
# Justification: hand-written caddy cert mounts with runtime hostname
#   selection — the documented exception to the secrets generator (Law 4)
# Plan: permanent by design (see CHARTER.md §4)
# Revocable: yes (if cert selection moves into the generator)
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
