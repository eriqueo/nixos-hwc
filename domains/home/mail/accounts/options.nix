{ lib, ... }:
let t = lib.types; in
{
  options.hwc.home.mail.accountsResolved = lib.mkOption {
    type = t.attrs;            # attrset: name -> { maildir, roles = {sent,drafts,trash,spam,archive=[…]} }
    default = {};
    readOnly = true;
    description = "Derived per-account maildir + provider-specific special-folder roles for downstream modules.";
  };
}
