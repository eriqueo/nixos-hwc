# domains/home/core/repo-hooks/index.nix
#
# Declared git hooks — points core.hooksPath at a repo-tracked hooks dir so
# every host (and any fresh clone, after one activation) runs the same hooks.
# Self-heals at HM activation, same shape as claude-code's settings.json
# gate-hook wiring (02b0895b). Handles a hooksPath previously set to anything
# (including /dev/null) by overwriting it, and skips repos not cloned here.
#
# NAMESPACE: hwc.home.core.repoHooks.*
# USED BY: profiles/base/home.nix

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.core.repoHooks;
  t = lib.types;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.core.repoHooks = {
    enable = lib.mkEnableOption "declared git hooks (core.hooksPath) for listed repos";

    repos = lib.mkOption {
      type = t.listOf (t.submodule {
        options = {
          path = lib.mkOption {
            type = t.str;
            description = "Absolute path to the repo checkout on this host.";
          };
          hooksDir = lib.mkOption {
            type = t.str;
            default = ".githooks";
            description = "Repo-relative directory holding the tracked hooks.";
          };
        };
      });
      default = [ ];
      description = "Repos whose core.hooksPath is pinned to an in-repo hooks dir at activation.";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.activation.repoHooksPath = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (r: ''
        if [ -e "${r.path}/.git" ]; then
          if [ -d "${r.path}/${r.hooksDir}" ]; then
            _cur=$(${pkgs.git}/bin/git -C "${r.path}" config --local core.hooksPath || true)
            if [ "$_cur" != "${r.hooksDir}" ]; then
              run ${pkgs.git}/bin/git -C "${r.path}" config core.hooksPath "${r.hooksDir}"
              echo "repo-hooks: ${r.path} core.hooksPath ''${_cur:-<unset>} -> ${r.hooksDir}"
            fi
          else
            echo "repo-hooks: ${r.path}/${r.hooksDir} missing — hooksPath not set" >&2
          fi
        else
          echo "repo-hooks: ${r.path} is not a git checkout here — skipped" >&2
        fi
      '') cfg.repos
    );

    assertions = [
      {
        assertion = cfg.repos != [ ];
        message = "hwc.home.core.repoHooks.repos must list at least one repo when enabled.";
      }
    ];
  };
}
