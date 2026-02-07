{ osConfig ? {}}:
{
  # List your tags here; tools.nix will write proper prefs lines.
  tags = [
    { name = "@Action";      color = "#FF0000"; ordinal = 1; }
    { name = "@Waiting";     color = "#FFA500"; ordinal = 2; }
    { name = "@Read Later";  color = "#0000FF"; ordinal = 3; }
    { name = "@Today";       color = "#FFFF00"; ordinal = 4; }
    { name = "@Clients";     color = "#00FF00"; ordinal = 5; }
    { name = "@Finance";     color = "#808080"; ordinal = 6; }
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