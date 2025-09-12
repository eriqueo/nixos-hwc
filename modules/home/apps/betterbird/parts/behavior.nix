{ lib, pkgs, config, ... }:
{
  files = profileBase: {
    "${profileBase}/user.js".text = ''
      // Enable custom CSS
      user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

      // Layout / threading
      user_pref("mail.pane_config.dynamic", 1);                  // Vertical view
      user_pref("mail.threadpane.use_correspondents", false);
      user_pref("mailnews.default_view_flags", 1);               // Threaded

      // Sort (18: date), 2: desc
      user_pref("mailnews.default_sort_type", 18);
      user_pref("mailnews.default_sort_order", 2);

      // Reader
      user_pref("mailnews.mark_message_read.auto", true);
      user_pref("mailnews.mark_message_read.delay", true);
      user_pref("mailnews.mark_message_read.delay.interval", 300);

      // Compose
      user_pref("mailnews.reply_followup_to", true);
      user_pref("mail.compose.autosave", true);
      user_pref("mail.compose.autosaveinterval", 2);

      // UI polish
      user_pref("browser.tabs.drawInTitlebar", true);
      user_pref("browser.tabs.inTitlebar", 1);
      user_pref("layout.css.prefers-color-scheme.content-override", 0);
    '';
  };
}
