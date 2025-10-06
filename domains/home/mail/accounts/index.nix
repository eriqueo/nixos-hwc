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
        maildirName = "proton";
        # include Proton custom folders:
        sync.patterns = [ "INBOX" "Sent" "Drafts" "Trash" "Archive" "Folders/*" "Labels/*" ];
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
          maildirName = "gmail-personal";
          sync.patterns = [
            "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/All Mail"
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
          maildirName = "gmail-business";
          sync.patterns = [
            "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/All Mail"
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
          maildirName = "iheartwoodcraft";
          # include Proton custom folders:
          sync.patterns = [ "INBOX" "Sent" "Drafts" "Trash" "Archive" "Folders/*" ];
          send.msmtpAccount = "iheartwoodcraft";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
