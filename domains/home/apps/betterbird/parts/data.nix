{ osConfig ? {}, colors ? {} }:
let c = colors;
in {
  # List your tags here; tools.nix will write proper prefs lines.
  tags = [
    { name = "@Action";      color = "#${c.error or "bf616a"}";         ordinal = 1; }
    { name = "@Waiting";     color = "#${c.warning or "cf995f"}";       ordinal = 2; }
    { name = "@Read Later";  color = "#${c.info or "5e81ac"}";          ordinal = 3; }
    { name = "@Today";       color = "#${c.warningBright or "fcbb74"}"; ordinal = 4; }
    { name = "@Clients";     color = "#${c.success or "a3be8c"}";       ordinal = 5; }
    { name = "@Finance";     color = "#${c.fg3 or "50626f"}";           ordinal = 6; }
  ];

  # Your current filter set (keep as-is).
  filtersDat = ''
    version="9"
    logging="yes"

    name="Tag Clients - Action"
    enabled="yes"
    type="1"
    action="AddTag"
    actionValue="@Action"
    action="AddTag"
    actionValue="@Clients"
    condition="OR (from,contains,bmyincplans.com) (subject,contains,Estimate)"

    name="Move Promos"
    enabled="yes"
    type="1"
    action="Move to folder"
    actionValue="mailbox://<account-identifier>/Promotions"
    condition="OR (subject,contains,unsubscribe) (subject,contains,% off) (subject,contains,sale)"

    name="Finance"
    enabled="yes"
    type="1"
    action="AddTag"
    actionValue="@Finance"
    condition="OR (subject,contains,invoice) (subject,contains,receipt) (from,contains,intuit.com)"
  '';
}