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
        #uiName = "Proton";                 # shown in aerc tab
        #order = 20;                        # tab order
        type = "proton-bridge";
        realName = "Eric";
        address = "eriqueo@proton.me";
        login = "";
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = "200-personal";
        sync.patterns = [
          "INBOX" "210-inbox"
          "Archive" "211-archive"
          "Sent" "212-sent"
          "Drafts" "213-drafts"
          "Trash" "219-trash"
        ];
        send.msmtpAccount = "proton";
        primary = true;
      };
      
    gmail-personal = {
          name = "gmail-personal";
          #uiName = "Gmail (personal)";       # shown in aerc tab
          #order = 30;                        # tab order
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "eriqueokeefe@gmail.com";
          login = "eriqueokeefe@gmail.com";
          password = { mode = "agenix"; agenix = "/run/agenix/gmail-personal-password"; };
          maildirName = "200-personal";
          sync.patterns = [
            "INBOX" "210-inbox"
            "[Gmail]/All Mail" "211-archive"
            "[Gmail]/Sent Mail" "212-sent"
            "[Gmail]/Drafts" "213-drafts"
            "[Gmail]/Starred" "214-important"
            "[Gmail]/Trash" "219-trash"
          ];
          send.msmtpAccount = "gmail-personal";
        };

    gmail-business = {
          name = "gmail-business";
          #uiName = "Gmail (business)";       # shown in aerc tab
          #order = 40;                        # tab order
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "heartwoodcraftmt@gmail.com";
          login = "heartwoodcraftmt@gmail.com";
          password = { mode = "agenix"; agenix = "/run/agenix/gmail-business-password"; };
          maildirName = "100-work";
          sync.patterns = [
            "INBOX" "110-inbox"
            "[Gmail]/All Mail" "111-archive"
            "[Gmail]/Sent Mail" "112-sent"
            "[Gmail]/Drafts" "113-drafts"
            "[Gmail]/Trash" "119-trash"
          ];
          send.msmtpAccount = "gmail-business";
        };

    iheartwoodcraft = {
          name = "iheartwoodcraft";
          #uiName = "eric@iheartwoodcraft";   # shown in aerc tab
          #order = 10;                        # tab order (lower = left)
          type = "proton-bridge";
          realName = "Eric";
          address = "eric@iheartwoodcraft.com";
          login = "";
          password = { mode = "pass"; pass = "email/proton/bridge"; };
          maildirName = "100-work";
          sync.patterns = [
            "INBOX" "110-inbox"
            "Archive" "111-archive"
            "Sent" "112-sent"
            "Drafts" "113-drafts"
            "Trash" "119-trash"
          ];
          send.msmtpAccount = "iheartwoodcraft";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
