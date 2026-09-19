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

  # ── Read by hwc-crm only (hwc-leads ignores unknown keys) ─────────────
  # Job custom fields. Phase is the ONE status field since 2026-09-18 (job
  # Status and customer Status were deleted). Run PM Report is required: a
  # job without a value rejects every later update.
  jobCustomFields = {
    phase = "22P4fguBu3Ub";
    jobType = "22P4fgU4XmLY";
    runPmReport = "22PdsGQDV5pV";
    jobLostReason = "22PUGv3vsqBU";
    siteVisit = "22PVyDzw2gXH";
  };

  # Customer (account) custom fields.
  accountCustomFields = {
    leadSource = "22PUGvBnXeYs";
    projectType = "22Nnj9KMKEPC";
  };

  # Option texts hwc-crm writes on intake. Must match the live field
  # options exactly (verified against the org 2026-09-18).
  intakeValues = {
    phase = "1. Contacted";
    leadSource = "Website";
    jobTypeByCalculator = { bathroom = "Bathroom"; deck = "Deck"; };
    projectTypeByCalculator = { bathroom = "Bathroom Remodel"; deck = "Deck"; };

    # The contact + inline forms let the customer choose these. hwc-crm
    # writes a choice only when it is listed here; JobTread rejects the
    # whole create on an unknown option.
    leadSourceOptions = [
      "Website" "Google Local Service" "Google General" "Facebook"
      "Short Term Rental" "Repeat" "Instagram" "Chamber" "Word of Mouth"
      "Insurance" "Other"
    ];
    projectTypeOptions = [
      "Bathroom Remodel" "Exterior" "Interior" "Custom" "Deck" "Fence" "Addition"
    ];
    # Customer "Project Type" → job "Job Type". Addition has no Job Type.
    jobTypeByProjectType = {
      "Bathroom Remodel" = "Bathroom";
      "Deck" = "Deck";
      "Interior" = "Interior General";
      "Exterior" = "Exterior General";
      "Fence" = "Exterior General";
      "Custom" = "Custom";
    };
  };
}
