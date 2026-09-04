# domains/automation/refinery/container.nix
#
# Refinery, container mode: the SAME image every host runs (built by the
# eriqueo/refinery repo's CI as ghcr.io/eriqueo/refinery, or locally with
# `podman build -f deploy/Dockerfile`). One process serves the board, drains
# native runs inline and polls DataX for promoted remediation proposals. All
# host specifics are the env file (agenix `refinery-env`) and the volumes below,
# so moving to a droplet is: copy /var/lib/refinery + the env file, `docker
# compose up`, point DNS (deploy/README.md in that repo is the runbook).
#
# Native mode (index.nix) and container mode never run at the same time: the
# board port is one Caddy upstream. `hwc.automation.refinery.mode` selects.
#
# NAMESPACE: hwc.automation.refinery.* (options declared in index.nix)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.automation.refinery;
  paths = config.hwc.paths;
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;
  # Mount points inside the container. The engine reads these through the
  # REFINERY_* env below; host paths on the left are the options in index.nix.
  vaultMount = "/mnt/refinery/vault";
  srMount = "/mnt/refinery/sr-gauntlet";
  dx1Mount = "/mnt/refinery/dx1-gauntlet";
in
{
  config = lib.mkIf (cfg.enable && cfg.mode == "container") (lib.mkMerge [
    (mkContainer {
      name = "refinery";
      image = cfg.image;
      pull = cfg.imagePull;
      networkMode = "media";
      gpuEnable = false;
      timeZone = config.time.timeZone or "UTC";
      memory = "2g";
      cpus = "1.5";
      memorySwap = "3g";
      # The image runs as uid 1000 (`refinery`), which is eric on this host, so
      # the state dir and the vault binds keep their ownership.
      user = "1000:100";
      ports = [ "127.0.0.1:${toString cfg.port}:8060" ];
      volumes =
        [ "/var/lib/refinery:/var/lib/refinery" ]
        ++ lib.optionals (cfg.vaultDir != null) [
          "${cfg.vaultDir}/_inbox/nightly_builds:${vaultMount}/_inbox/nightly_builds"
          "${cfg.vaultDir}/runs:${vaultMount}/runs:ro"
        ]
        ++ lib.optionals (cfg.srGauntletDir != null) [
          "${cfg.srGauntletDir}/investigations:${srMount}/investigations:ro"
          "${cfg.srGauntletDir}/state:${srMount}/state:ro"
        ]
        ++ lib.optionals (cfg.dx1GauntletDir != null) [
          "${cfg.dx1GauntletDir}/investigations:${dx1Mount}/investigations:ro"
          "${cfg.dx1GauntletDir}/state:${dx1Mount}/state:ro"
        ];
      # Secrets and host-specific values (DataX secret, GitHub token, DX1 key,
      # REFINERY_REPOS, git identity, board URL) come from the agenix env file.
      environmentFiles = [ config.age.secrets."refinery-env".path ];
      environment = {
        REFINERY_DATAX_BASE_URL = cfg.dataxBaseUrl;
        REFINERY_NATIVE_DRAIN = "inline";
      } // lib.optionalAttrs (cfg.vaultDir != null) { REFINERY_VAULT_DIR = vaultMount; }
        // lib.optionalAttrs (cfg.srGauntletDir != null) { REFINERY_SR_GAUNTLET_DIR = srMount; }
        // lib.optionalAttrs (cfg.dx1GauntletDir != null) { REFINERY_DX1_GAUNTLET_DIR = dx1Mount; };
    })
    {
      # The state dir is shared with native mode; keep it owned by eric so a
      # switch back to native mode needs no chown.
      systemd.tmpfiles.rules = [
        "d /var/lib/refinery 0775 eric users - -"
        "d /var/lib/refinery/repos 0775 eric users - -"
        "d /var/lib/refinery/native 0775 eric users - -"
        "d /var/lib/refinery/native-run 0775 eric users - -"
      ];
      # The env file's ownership (eric, 0400) is declared where every secret's
      # mount is: domains/secrets/declarations/generated.nix mountOverrides.
    }
  ]);
}
