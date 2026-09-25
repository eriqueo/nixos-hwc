# domains/home/core/repo-hooks/index.nix
#
# Declared git hooks — points core.hooksPath at a store dir built per repo, so
# every host (and any fresh clone, after one activation) runs the same hooks.
# Dispatched hooks forward to the repo-tracked copy in the checked-out tree;
# pinned hooks are store copies the checkout cannot change or remove. A hook
# that guards checkouts must be pinned: with a tree-relative hooksPath, a
# checkout of a commit that predates the hook deleted it before it ran
# (2026-09-25, .githooks/post-checkout).
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

  dispatcher = hooksDir: name: pkgs.writeShellScript "repo-hook-${name}" ''
    hook="$(${pkgs.git}/bin/git rev-parse --show-toplevel)/${hooksDir}/${name}"
    [ -x "$hook" ] || exit 0
    exec "$hook" "$@"
  '';
  hooksFor = r: pkgs.linkFarm "repo-hooks" (
    lib.mapAttrsToList (name: path: { inherit name path; }) (
      lib.genAttrs (lib.subtractLists (lib.attrNames r.pinned) r.dispatched) (dispatcher r.hooksDir)
      // r.pinned
    )
  );
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
          dispatched = lib.mkOption {
            type = t.listOf t.str;
            default = [ "pre-commit" "prepare-commit-msg" "commit-msg" "post-commit" "pre-push" "post-merge" "post-rewrite" "pre-rebase" ];
            description = "Hook names forwarded to <hooksDir>/<name> in the checked-out tree, when present there.";
          };
          pinned = lib.mkOption {
            type = t.attrsOf t.path;
            default = { };
            description = "Hook name -> file installed from the Nix store; the checked-out tree cannot change or remove it.";
          };
        };
      });
      default = [ ];
      description = "Repos whose core.hooksPath is pinned to a generated store hooks dir at activation.";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.activation.repoHooksPath = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (r: ''
        if [ -e "${r.path}/.git" ]; then
          _cur=$(${pkgs.git}/bin/git -C "${r.path}" config --local core.hooksPath || true)
          if [ "$_cur" != "${hooksFor r}" ]; then
            run ${pkgs.git}/bin/git -C "${r.path}" config core.hooksPath "${hooksFor r}"
            echo "repo-hooks: ${r.path} core.hooksPath ''${_cur:-<unset>} -> ${hooksFor r}"
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
