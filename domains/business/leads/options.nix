# domains/business/leads/options.nix
#
# Schema for hwc.business.leads.*
#
# Phase 0: just the enable toggle. Phase 2 will flesh out port, DB DSN ref,
# JT credential ref, HMAC secret ref, retry policy, etc.

{ lib, ... }:

{
  options.hwc.business.leads = {
    enable = lib.mkEnableOption ''
      Unified lead pipeline (hwc-leads).
      Single POST /leads HTTP endpoint replacing the three calculator /
      contact / appointment webhook paths. Validates → JT graph → DB →
      hwc-notify ping → customer email. Implementation lands in Phase 2 —
      see ~/.claude/plans/hashed-snacking-crab.md.
    '';
  };
}
