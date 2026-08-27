# domains/home/apps/doctl/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.doctl;

  # `doctl auth init` validates against cloud.digitalocean.com/v1/oauth/token/info
  # and rejects tokens that endpoint itself accepts (measured 2026-08-26, doctl
  # 1.160.1). The token therefore never enters config.yaml. It is read from
  # agenix per invocation, so it lives in one process instead of the shell env.
  # eric is in the `secrets` group (gid 975), so 0440 root:secrets is readable.
  doctlScript = pkgs.writeShellScriptBin "doctl" ''
    set -u

    secret=/run/agenix/digitalocean-access-token

    if [[ ! -r "$secret" ]]; then
      echo "doctl: missing or unreadable secret: $secret" >&2
      echo "       (is eric in the 'secrets' group? has nixos-rebuild run since the secret was added?)" >&2
      exit 1
    fi

    DIGITALOCEAN_ACCESS_TOKEN="$(tr -d '\r\n' < "$secret")"
    export DIGITALOCEAN_ACCESS_TOKEN

    exec ${pkgs.doctl}/bin/doctl "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.doctl = {
    enable = lib.mkEnableOption "doctl — DigitalOcean CLI, authenticated from agenix";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ doctlScript ];
  };
}
