# domains/home/apps/gpu-screen-recorder/sys.nix
# System-lane dependencies for gpu-screen-recorder
#
# ARCHITECTURE NOTE:
# This sys.nix file defines system-lane options because system evaluates
# before Home Manager. See CHARTER.md Law 7 for the sys.nix pattern.
#
# WHY THE SYSTEM LANE IS MANDATORY HERE (not just integration sugar):
# Promptless monitor capture on Wayland requires gsr-kms-server with
# cap_sys_admin. The nixpkgs module overrides the package with
# config.security.wrapperDir so the gpu-screen-recorder binary execs the
# setcap'd wrapper from /run/wrappers/bin instead of its own (uncapped)
# store copy. That override only exists on this lane — which is also why
# the home index.nix must NOT install the plain package (it would shadow
# this one in PATH and silently lose promptless capture).

{ config, lib, osConfig ? {}, ... }:

let
  cfg = config.hwc.system.apps.gpu-screen-recorder;
in
{
  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.gpu-screen-recorder = {
    enable = lib.mkEnableOption "gpu-screen-recorder with setcap gsr-kms-server wrapper (promptless Wayland monitor capture)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Installs the CLI system-wide AND creates the cap_sys_admin wrapper
    # for gsr-kms-server, with the package's wrapperDir override applied.
    programs.gpu-screen-recorder.enable = true;
  };
}
