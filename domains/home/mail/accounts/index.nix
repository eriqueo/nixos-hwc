#==========================================================================
# OPTIONS
#==========================================================================
# Sets values only (no options). Lives under the domain so it's uniform with others.
{
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  hwc.home.mail.accounts = {
    proton = {
        name = "proton";
        type = "proton-bridge";
        realName = "Eric";
        address = "eriqueo@proton.me";
        login = "";
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = "200_personal";
        mailboxMapping = {
          "personal_inbox" = "inbox";    # Server-side filtered folder
          "Sent"           = "sent";
          "Drafts"         = "drafts";
          "Archive"        = "archive";
        };
        sync.wildcards = [ "Folders/*" "Labels/*" ];
        send.msmtpAccount = "proton";
        primary = true;
      };
      
    gmail-personal = {
          name = "gmail-personal";
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "eriqueokeefe@gmail.com";
          login = "eriqueokeefe@gmail.com";
          password = { mode = "agenix"; agenix = "/run/agenix/gmail-personal-password"; };
          maildirName = "210_gmail-personal";
          mailboxMapping = {
            "INBOX"               = "inbox";
            "[Gmail]/Sent Mail"   = "sent";
            "[Gmail]/Drafts"      = "drafts";
            "[Gmail]/Starred"     = "starred";
          };
          send.msmtpAccount = "gmail-personal";
        };

    gmail-business = {
          name = "gmail-business";
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "heartwoodcraftmt@gmail.com";
          login = "heartwoodcraftmt@gmail.com";
          password = { mode = "agenix"; agenix = "/run/agenix/gmail-business-password"; };
          maildirName = "110_gmail-business";
          mailboxMapping = {
            "INBOX"               = "inbox";
            "[Gmail]/Sent Mail"   = "sent";
            "[Gmail]/Drafts"      = "drafts";
            "[Gmail]/Starred"     = "starred";
          };
          send.msmtpAccount = "gmail-business";
        };

    iheartwoodcraft = {
          name = "iheartwoodcraft";
          type = "proton-bridge";
          realName = "Eric";
          address = "eric@iheartwoodcraft.com";
          login = "";
          password = { mode = "pass"; pass = "email/proton/bridge"; };
          maildirName = "100_hwc";
          mailboxMapping = {
            "hwc_inbox" = "inbox";    # Server-side filtered folder (note: underscore, not hyphen)
            "Sent"      = "sent";
            "Drafts"    = "drafts";
            "Archive"   = "archive";
          };
          sync.wildcards = [ "Folders/*" ];
          send.msmtpAccount = "iheartwoodcraft";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
