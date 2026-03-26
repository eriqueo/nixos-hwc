# domains/system/core/authentik/index.nix
#
# Authentik SSO/Identity Provider
# NAMESPACE: hwc.system.core.authentik.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.core.authentik;
in
{
  options.hwc.system.core.authentik = {
    enable = lib.mkEnableOption "Authentik SSO/Identity Provider";
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/goauthentik/server:2024.12"; };
    database = {
      host = lib.mkOption { type = lib.types.str; default = "10.89.0.1"; };
      port = lib.mkOption { type = lib.types.port; default = 5432; };
      name = lib.mkOption { type = lib.types.str; default = "authentik"; };
      user = lib.mkOption { type = lib.types.str; default = "authentik"; };
    };
    redis = {
      host = lib.mkOption { type = lib.types.str; default = "10.89.0.1"; };
      port = lib.mkOption { type = lib.types.port; default = 6380; };
    };
    reverseProxy = {
      port = lib.mkOption { type = lib.types.port; default = 15543; };
      internalPort = lib.mkOption { type = lib.types.port; default = 9200; };
      internalHttpsPort = lib.mkOption { type = lib.types.port; default = 9201; };
    };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "host" ]; default = "media"; };
  };

  imports = [ ./parts/config.nix ];
  config = lib.mkIf cfg.enable { };
}
