# domains/business/leads/index.nix
#
# hwc-leads — unified lead pipeline.
#
# Single HTTP entry point (POST /leads) for every customer-facing form
# (contact, calculator, appointment). Validates inputs against a Zod
# schema, creates the JobTread graph (account / location / contact / job),
# writes a row to hwc.calculator_leads, hands the result to hwc-notify,
# and emits a customer-facing confirmation email.
#
# NAMESPACE: hwc.business.leads.*
#
# STATUS: Phase 0 scaffold only — enabling this module asserts until
# the Phase 2 implementation lands.
#
# See ~/.claude/plans/hashed-snacking-crab.md for the design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.leads;
in
{
  # OPTIONS
  imports = [ ./options.nix ];

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    # Phase 2 will:
    #   - bundle src/ into the Nix store via lib.sources.sourceFilesBySuffices
    #   - declare systemd.services.hwc-leads (User=eric, hardening, env from
    #     module options + agenix paths to JT key, HMAC secret, DB DSN)
    #   - register a Caddy route for POST /leads with rate-limiting
    #   - export JT custom-field mappings as data
    # Until then, enabling this module is an error so callers can't depend
    # on a non-existent service.
    assertions = [
      {
        assertion = false;
        message = ''
          hwc.business.leads is scaffolded but not yet implemented.
          See ~/.claude/plans/hashed-snacking-crab.md Phase 2 for the design.
        '';
      }
    ];
  };
}
