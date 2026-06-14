# domains/home/apps/khalt/index.nix
#
# khalt — forked khal/ikhal calendar TUI (its own repo at ~/600_apps/khalt,
# consumed as the `khalt` flake input). This module is a THIN TRANSLATOR (same
# role as domains/home/apps/todui): it imports khalt's reusable Home Manager
# module and feeds it an HWC-specific khal config.
#
# DRY: instead of re-listing calendars/locale/palette, it reuses the EXACT
# config generator the calendar domain already ships
# (domains/mail/calendar/parts/khal.nix), so khalt opens on the same calendars,
# theme and view as system khal. khalt-only additions (notably a [keybindings]
# block once the leader-key engine lands) are appended via `extraConfig`.
#
# NAMESPACE: hwc.home.apps.khalt.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.khalt.enable = true;   (set in a profile when ready)
#
# STATUS: scaffold. khalt currently builds and runs identically to khal v0.14.0.
# The zoomable agenda/quarter/month views and space-leader keybindings are the
# next implementation passes in the ~/600_apps/khalt source — see its README.

{ config, lib, pkgs, inputs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.khalt;

  # Reuse the calendar domain's khal-config generator with the live calendar
  # cfg, so khalt's config is byte-for-byte the system khal config. Coupling to
  # a sibling domain's parts/ generator is deliberate (single source of truth
  # for calendar definitions); revisit if the calendar domain is restructured.
  calCfg = config.hwc.mail.calendar;
  baseKhal = import ../../../mail/calendar/parts/khal.nix {
    inherit lib pkgs;
    cfg = calCfg;
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ inputs.khalt.homeManagerModules.khalt ];

  options.hwc.home.apps.khalt = {
    enable = lib.mkEnableOption "khalt — forked khal/ikhal TUI (zoom views + leader keys)";

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra khal-config text appended to the shared system-khal config. This
        is where khalt-only sections live — e.g. a [keybindings] block remapping
        ikhal commands, once the leader-key engine is implemented in the fork.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.khalt = {
      enable = true;
      configText = baseKhal.config
        + lib.optionalString (cfg.extraConfig != "") ("\n" + cfg.extraConfig);
      extraRuntimePackages = [ pkgs.vdirsyncer ];
    };
  };
}
