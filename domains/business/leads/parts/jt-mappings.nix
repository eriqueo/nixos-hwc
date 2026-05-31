# domains/business/leads/parts/jt-mappings.nix
#
# JobTread organization-specific identifiers used by the Phase 2.4
# JtJobtreadAdapter. Pure Nix data — serialised to JSON and passed to
# the runtime via HWC_LEADS_JT_CONFIG_FILE. The TS service never bakes
# these IDs into source.
#
# Source: cross-referenced from the live work_calculator_lead n8n
# workflow (SoLwmxgkMILrOYbP) on 2026-05-31. If JT moves the custom
# field IDs (rare — they're internal), change here + rebuild.

{
  # HWC's JobTread organization. All accounts created by hwc-leads
  # belong here.
  organizationId = "22Nm3uFevXMb";

  # Default location for new accounts. HWC's customers are all local;
  # for now every lead-created Location is "Primary" at this address.
  # Variable per-lead address support lands when contact-form / calc
  # actually collects an address (not in Phase 2 scope).
  defaultLocation = {
    name = "Primary";
    address = "Bozeman, MT";
  };

  # JT custom field IDs on Contact records. These are the field IDs
  # HWC's JT instance assigned when those custom fields were created.
  contactCustomFields = {
    phone = "22Nm3uGb7WT2";
    email = "22Nm3uGRBrPX";
  };

  # JT account `type` for customer accounts. Other valid values exist
  # in JT (vendor, subcontractor, …) but hwc-leads only creates customers.
  accountType = "customer";
}
