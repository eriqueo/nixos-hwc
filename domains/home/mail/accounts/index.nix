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
        maildirName = "210_proton";
        mailboxMapping = {
          "INBOX"   = "000_inbox";
          "Sent"    = "010_sent";
          "Drafts"  = "011_drafts";
          "Archive" = "290_pers-archive";
          "Spam"    = "800_spam";
          "Trash"   = "900_trash";
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
          maildirName = "200_personal";
          mailboxMapping = {
            "INBOX"               = "000_inbox";
            "[Gmail]/Sent Mail"   = "010_sent";
            "[Gmail]/Drafts"      = "011_drafts";
            "[Gmail]/All Mail"    = "290_pers-archive";
            "[Gmail]/Starred"     = "210_pers-important";
            "[Gmail]/Spam"        = "800_spam";
            "[Gmail]/Trash"       = "900_trash";
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
            "INBOX"               = "000_inbox";
            "[Gmail]/Sent Mail"   = "010_sent";
            "[Gmail]/Drafts"      = "011_drafts";
            "[Gmail]/All Mail"    = "190_hwc-archive";
            "[Gmail]/Spam"        = "800_spam";
            "[Gmail]/Trash"       = "900_trash";
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
            "INBOX"   = "000_inbox";
            "Sent"    = "010_sent";
            "Drafts"  = "011_drafts";
            "Archive" = "190_hwc-archive";
            "Spam"    = "800_spam";
            "Trash"   = "900_trash";
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
