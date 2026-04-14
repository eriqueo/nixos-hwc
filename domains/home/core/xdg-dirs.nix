# domains/home/core/xdg-dirs.nix
# Declarative XDG user directories (Home Manager) aligned with HWC paths
#
# STRUCTURE PHILOSOPHY:
#   000_inbox  — OS/app catch-all, unsorted (Downloads, Documents symlink here)
#   x00_inbox  — Domain-level unsorted
#   x10_admin  — Identity, credentials, compliance
#   x20_operations — Active work, jobs, projects
#   x30_financial  — Money (HWC + personal only; tech spending → 230_financial)
#   x40_development — Growth, marketing, learning
#   x50_reference  — Static knowledge, docs, manuals
#   x90_archive    — Dead storage
#
{ config, lib, osConfig ? {}, ... }:
let
  home   = config.home.homeDirectory;
  inbox  = "${home}/000_inbox";
  hwc    = "${home}/100_hwc";
  pers   = "${home}/200_personal";
  tech   = "${home}/300_tech";
  media  = "${home}/500_media";
in {
  config = {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;

      # OS catch-all — anything the system or apps dump gets sorted from here
      desktop   = inbox;
      download  = "${inbox}/downloads";
      documents = "${inbox}/documents";

      # Templates live in HWC operations (where they're actually used)
      templates = "${hwc}/120_operations/templates";

      # Public share maps to inbox (nothing truly public)
      publicShare = inbox;

      # Media — unchanged
      pictures = "${media}/510_pictures";
      music    = "${media}/520_music";
      videos   = "${media}/530_videos";
    };

    # Ensure all domain folders exist on activation
    home.activation.ensureHwcDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p \
        ${inbox} \
        ${inbox}/downloads \
        ${inbox}/documents \
        \
        ${hwc}/100_inbox \
        ${hwc}/110_admin \
        ${hwc}/110_admin/certificates \
        ${hwc}/110_admin/contracts \
        ${hwc}/110_admin/insurance \
        ${hwc}/110_admin/legal \
        ${hwc}/110_admin/licenses \
        ${hwc}/120_operations \
        ${hwc}/120_operations/jobs \
        ${hwc}/120_operations/jobtread \
        ${hwc}/120_operations/templates \
        ${hwc}/120_operations/sops \
        ${hwc}/130_financial \
        ${hwc}/130_financial/taxes \
        ${hwc}/130_financial/taxes/2022 \
        ${hwc}/130_financial/taxes/2023 \
        ${hwc}/130_financial/taxes/2024 \
        ${hwc}/130_financial/taxes/_reference \
        ${hwc}/130_financial/receipts \
        ${hwc}/130_financial/receipts/2023 \
        ${hwc}/130_financial/receipts/2024 \
        ${hwc}/130_financial/receipts/2025 \
        ${hwc}/130_financial/statements \
        ${hwc}/130_financial/overhead \
        ${hwc}/130_financial/budgets \
        ${hwc}/140_development \
        ${hwc}/140_development/marketing \
        ${hwc}/140_development/website \
        ${hwc}/140_development/business_structure \
        ${hwc}/140_development/coaching \
        ${hwc}/150_reference \
        ${hwc}/150_reference/ebooks \
        ${hwc}/150_reference/technical_docs \
        ${hwc}/150_reference/cost_books \
        ${hwc}/190_archive \
        \
        ${pers}/200_inbox \
        ${pers}/210_admin \
        ${pers}/220_operations \
        ${pers}/230_financial \
        ${pers}/240_development \
        ${pers}/250_reference \
        ${pers}/290_archive \
        \
        ${tech}/300_inbox \
        ${tech}/310_admin \
        ${tech}/320_operations \
        ${tech}/340_development \
        ${tech}/350_reference \
        ${tech}/390_archive \
        \
        ${media}/500_inbox \
        ${media}/510_pictures \
        ${media}/520_music \
        ${media}/530_videos \
        ${media}/540_blender \
        ${media}/550_courses
    '';
  };
}
