# Sets values only (no options). Lives under the domain so it’s uniform with others.
{
  hwc.home.mail.accounts = {
    proton = {
      name = "proton";
      type = "proton-bridge";
      realName = "Eric";
      address = "eriqueo@proton.me";
      login = "";
      password = { mode = "pass"; pass = "email/proton/bridge"; };
      maildirName = "proton";
      sync.patterns = [ "INBOX" "Sent" "Drafts" "Trash" "Archive" ];
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
      maildirName = "gmail-personal";
      sync.patterns = [
        "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/All Mail"
      ];
      send.msmtpAccount = "gmail-personal";
    };

    gmail-business = {
      name = "gmail-business";
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
  };
}
