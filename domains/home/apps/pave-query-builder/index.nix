# domains/home/apps/pave-query-builder/index.nix
#
# pave-query-builder — trap-safe Pave (JobTread API) query builder, TUI + CLI
# (its own repo at ~/600_apps/pave-query-builder, consumed as the
# `pave-query-builder` flake input). This module is a THIN TRANSLATOR: it imports
# the app's reusable Home Manager module and feeds it HWC-specific values. The
# app itself knows nothing about HWC (hexagonal: inbound adapter).
#
# NAMESPACE: hwc.home.apps.pave-query-builder.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.pave-query-builder.enable = true;   (set in profiles/desktop)

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.home.apps.pave-query-builder;

  # Hand the app the jt-mcp schema for the introspection fallback + enum
  # validation. Set unconditionally (not pathExists-guarded — that returns false
  # under pure flake eval); the app's schema loader degrades gracefully if the
  # file is absent, so baking the HWC path is safe even on a checkout-less host.
  schemaPath = "${config.home.homeDirectory}/700_datax/jt-mcp/schema_pretty.json";
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ inputs.pave-query-builder.homeManagerModules.pave-query-builder ];

  options.hwc.home.apps.pave-query-builder = {
    enable = lib.mkEnableOption "pave-query-builder — trap-safe Pave query TUI + CLI";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.pave-query-builder = {
      enable = true;
      inherit schemaPath;
      # Mutation guardrail: leave at the app's built-in default (HWC test org
      # only). Widen deliberately here if a real org ever needs writes.
      # mutationOrgs = [ "22Nm3uFevXMb" ];
    };

    # Launcher entry — it's a TUI, so host it in kitty (the session terminal).
    xdg.desktopEntries.pave-query-builder = {
      name = "Pave Query Builder";
      genericName = "JobTread API query builder";
      comment = "Trap-safe Pave (JobTread) query TUI";
      exec = "kitty -e pave-query";
      terminal = false;
      categories = [ "Utility" "Development" ];
      settings.Keywords = "jobtread;pave;api;query;";
    };
  };
}
