# nixos-hwc/machines/laptop/home.nix
#
# MACHINE: Laptop — Home facts (empty by design)
# Purpose: keep machine-local *facts* only. No Home Manager activation here.
#
# DEPENDENCIES (Upstream):
#   - None
#
# USED BY (Downstream):
#   - machines/laptop/config.nix (optional include)
#
# IMPORTS REQUIRED IN:
#   - None (profiles orchestrate Home Manager)
#
# CHARTER NOTES:
#   - “Profiles activate Modules.” No user-level modules are imported here.
#   - HM activation lives in profiles/workstation.nix (home-manager.users.eric { imports = [...] }).
#   - Base profile handles hwc.home.user.* facts.

{ lib, ... }:

{
  ##############################################################################
  ##  MACHINE HOME FACTS (INTENTIONALLY EMPTY)
  ##  Keep machine-local *facts* here if needed later. No HM wiring/imports.
  ##############################################################################

  # Nothing to set here. Profiles/base.nix enables hwc.home.user
  # Profiles/workstation.nix activates Home Manager and imports home modules.
}
