# nixos-hwc/modules/home/betterbird/parts/behavior.nix
#
# Betterbird Behavior: User Preferences, Filters, Tags & Email Rules
# Charter v5 compliant - Universal behavior domain for email interaction patterns
#
# DEPENDENCIES (Upstream):
#   - None (email behavior configuration)
#
# USED BY (Downstream):
#   - modules/home/betterbird/default.nix
#
# USAGE:
#   let behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
#   in { home.file = behavior.files profileBase; }
#

{ lib, pkgs, config, ... }:

{
  #============================================================================
  # CONFIGURATION FILES - User preferences, filters, and behavioral settings
  #============================================================================
  files = profileBase: {
    # Core user preferences and behavior settings
    "${profileBase}/user.js".text = ''
      // Enable userChrome.css customizations
      user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

      // Layout + view defaults - how the interface behaves
      user_pref("mail.pane_config.dynamic", 1); // vertical layout
      user_pref("mail.threadpane.use_correspondents", false);
      user_pref("mailnews.default_sort_type", 18); // sort by date
      user_pref("mailnews.default_sort_order", 2); // descending
      user_pref("mailnews.default_view_flags", 1); // threaded

      // Email tagging system - behavioral organization
      user_pref("mailnews.tags", "@Action,1,#FF0000,@Waiting,2,#FFA500,@Read Later,3,#0000FF,@Today,4,#FFFF00,@Clients,5,#00FF00,@Finance,6,#808080");
    '';

    # Email filtering rules - how emails are automatically processed
    "${profileBase}/filters/msgFilterRules.dat".text = ''
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
  };
}