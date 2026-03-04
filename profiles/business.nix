# profiles/business.nix
#
# Business Profile - Business services and document management
#
# DEPENDENCIES:
#   - domains/business (business services implementation)
#   - hwc.server.containers.paperless (document management)
#   - hwc.data.databases.redis (caching)
#
# USED BY:
#   - machines/server/config.nix

{ lib, config, ... }:

{
  #==========================================================================
  # BASE - Domain imports
  #==========================================================================
  imports = [
    ../domains/business/index.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================

  # Business domain configuration
  hwc.business = {
    # Enable business domain by default when profile is imported
    enable = lib.mkDefault true;

    # Receipts OCR - disabled by default (requires explicit enablement)
    receiptsOcr.enable = lib.mkDefault false;

    # Business API - disabled by default (requires explicit enablement)
    api.enable = lib.mkDefault false;

    # Future services - disabled by default
    invoicing.enable = lib.mkDefault false;
    crm.enable = lib.mkDefault false;
  };

  # Related services - enabled when business profile is used
  # Paperless-NGX for document management
  hwc.server.containers.paperless.enable = lib.mkDefault true;

  # Redis for caching
  hwc.data.databases.redis.enable = lib.mkDefault true;
}
