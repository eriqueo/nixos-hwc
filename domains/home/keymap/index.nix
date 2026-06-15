# domains/home/keymap/index.nix
#
# KEYMAP ROOT — single entry point for the unified workbench keymap, modelled
# exactly on domains/home/theme/index.nix.
#
#   theme:  hwc.home.theme.palette  -> .colors  -> app parts/appearance.nix
#   keymap: hwc.home.keymap (grammar) ------------> app parts/to-<app>.nix
#
# Materializes ./grammar.nix as the read-only `hwc.home.keymap.grammar` token
# set that every consumer reads via the guarded contract:
#
#     keymap = (config.hwc.home.keymap or {});
#     grammar = keymap.grammar or {};
#
# This module is INERT until imported. It is NOT under domains/home/apps/ (so
# it is not auto-imported); add it to a profile's imports to activate, then wire
# each app translator to its generator. Writing the files alone changes nothing.
#
# NAMESPACE: hwc.home.keymap.*   (Charter Law 2: namespace = folder)

{ config, lib, osConfig ? {}, ... }:

let
  grammar = import ./grammar.nix { inherit lib; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.keymap = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the unified keymap is materialized for consumers. Always-on by
        default (like the theme); apps read the grammar through the guarded
        contract and degrade to their own defaults if it is absent.
      '';
    };

    leader = lib.mkOption {
      type = lib.types.str;
      default = grammar.leader;
      description = "Intra-app leader key (Space). Single source of truth.";
    };

    metaLeader = lib.mkOption {
      type = lib.types.str;
      default = grammar.metaLeader;
      description = ''
        Inter-app meta leader (Alt+Space), intercepted only by zellij. Swap here
        in one edit; to-zellij.nix re-binds. Audited clear of Hyprland (SUPER-
        only; Super+Space=wofi) and every TUI (only nvim-cmp uses Ctrl+Space).
      '';
    };

    grammar = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Materialized keymap grammar from ./grammar.nix (read-only for apps).";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf config.hwc.home.keymap.enable {
    # Materialize the grammar as a read-only token set for app generators,
    # exactly as theme/index.nix does `hwc.home.theme.colors = activePalette`.
    hwc.home.keymap.grammar = grammar;
  };
}
