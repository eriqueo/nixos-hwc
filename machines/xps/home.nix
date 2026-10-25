# machines/xps/home.nix
#
# MACHINE: HWC-XPS — Home Manager overrides (HM lane)
# Role home halves (base, desktop) provide defaults via the flake glue;
# this file adjusts only what is unique to this machine.

{ lib, pkgs, ... }:

{
  # Codex pinned to the upstream release binary. This machine is on the stable
  # channel (flake machines table: channel = "stable"), and 26.05 freezes codex
  # at the version it branched with — 0.146.0, with no path forward short of a
  # channel bump. The pin is the module's documented opt-in for exactly this.
  #
  # NOT promoted to a profile or made the module default, even though
  # machines/laptop/home.nix carries the same line: parts/package.nix fetches
  # an x86_64 musl tarball, and hwc-firestick is aarch64, so a default would
  # break its build. hwc-home also stays on stock pkgs.codex deliberately.
  # Promote only together with arch selection in the module.
  hwc.home.apps.codex.package =
    pkgs.callPackage ../../domains/home/apps/codex/parts/package.nix { };

  # Work owns mail. This recovery/media instance has no local Maildir.
  hwc.mail = {
    enable = lib.mkForce false;
    aerc.enable = lib.mkForce false;
    afew.enable = lib.mkForce false;
  };

  # Disable heavyweight apps not needed on this lightweight server/laptop build
  hwc.home.apps = {
    blender.enable = lib.mkForce false;
    freecad.enable = lib.mkForce false;
    obsidian.enable = lib.mkForce false;
    onlyoffice-desktopeditors.enable = lib.mkForce false;
    slack.enable = lib.mkForce false;
    bottles-unwrapped.enable = lib.mkForce false;

    # T3 Code, headless shape — this machine's OWN agent environment, not a
    # move of hwc-server's or hwc-work's. Each host keeps its own ~/.t3 store,
    # signing key and pairing; nothing is copied between them.
    #
    # The desktop role (profiles/desktop/home.nix) turns the Electron shape on
    # by default, and XPS takes that role for Dad's Plasma seat and Eric's
    # Hyprland session. Here it is turned off: the module asserts the two shapes
    # never coexist, because both write the same ~/.t3 SQLite store. Turning
    # desktop off also retires the Electron 43 override this file used to carry
    # (XPS is on nixpkgs-stable, which dropped Electron 43) — `electronPackage`
    # is only ever read when `desktop.enable` is true.
    t3code = {
      desktop.enable = false;
      serve.enable = true;
      serve.port = 3773;

      # LOOPBACK, deliberately NOT the 0.0.0.0 that hwc-server and hwc-work
      # use. Those two sit in Eric's own house; this one sits in Dad's, on a
      # household LAN that the firewall already trusts wholesale
      # (`trustedInterfaces` carries eno1 — domains/system/networking/index.nix).
      # A wider bind here would answer to every device on that LAN, which is
      # exactly what "private environment" rules out. Caddy is the only door:
      # t3-xps.<vhostDomain> (domains/networking/routes.nix), tailnet-only, with
      # the wildcard certificate and T3's own pairing auth behind it.
      serve.host = "127.0.0.1";
    };
  };
}
