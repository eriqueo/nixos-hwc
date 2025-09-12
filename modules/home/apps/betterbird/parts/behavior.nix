# Betterbird • Behavior part
# Pure behavioral prefs (no services, no packages, no account-coupled files).
{ lib, pkgs, config, ... }:

{
  files = profileBase: {
    # Global prefs for layout, threading, CSS enablement, etc.
    "${profileBase}/user.js".text = ''
      // Enable custom CSS
      user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

      // Layout / panes
      user_pref("mail.pane_config.dynamic", 1);                  // Vertical view
      user_pref("mail.threadpane.use_correspondents", false);    // Show From, not Correspondents
      user_pref("mailnews.default_view_flags", 1);               // Threaded

      // Sorting (18 = by date), 2 = descending
      user_pref("mailnews.default_sort_type", 18);
      user_pref("mailnews.default_sort_order", 2);

      // Message list behavior
      user_pref("mailnews.mark_message_read.auto", true);
      user_pref("mailnews.mark_message_read.delay", true);
      user_pref("mailnews.mark_message_read.delay.interval", 300);

      // Composition
      user_pref("mailnews.reply_followup_to", true);
      user_pref("mail.compose.autosave", true);
      user_pref("mail.compose.autosaveinterval", 2);

      // UI polish
      user_pref("browser.tabs.drawInTitlebar", true);
      user_pref("browser.tabs.inTitlebar", 1);
      user_pref("layout.css.prefers-color-scheme.content-override", 0); // Follow system
    '';
  };
}
