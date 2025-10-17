{ config, lib, pkgs, ... }:

let
  # IMAP-only configuration (separate from aerc)
  gmailWork = "heartwoodcraftmt@gmail.com";
  gmailPersonal = "eriqueokeefe@gmail.com";
  protonWork = "eric@iheartwoodcraft.com";
  protonPersonal = "eriqueo@proton.me";

  realName = "Eric O'Keefe";

  # Profile directory structure
  profileDir = "${config.home.homeDirectory}/.betterbird/profiles/default";

  # Password integration with existing pass system
  passwordCmd = account: pkgs.writeShellScript "get-${account}-password" ''
    set -euo pipefail
    export PATH="${pkgs.pass}/bin:${pkgs.gnupg}/bin:$PATH"
    export HOME="${config.home.homeDirectory}"
    export GNUPGHOME="${config.home.homeDirectory}/.gnupg"
    export PASSWORD_STORE_DIR="${config.home.homeDirectory}/.password-store"

    case "${account}" in
      "gmail-business") pass show email/gmail/business | tr -d '\n' ;;
      "gmail-personal") pass show email/gmail/personal | tr -d '\n' ;;
      "proton-work") pass show email/proton/bridge | tr -d '\n' ;;
      "proton-personal") pass show email/proton/bridge | tr -d '\n' ;;
      *) echo "Unknown account: ${account}" >&2; exit 1 ;;
    esac
  '';

  # Unified Folders & Smart Folders configuration
  unifiedFoldersConfig = ''
    // === UNIFIED FOLDERS ===
    user_pref("mail.folder.views.version", 1);
    user_pref("mailnews.default_view_flags", 1); // Enable unified folders

    // === SMART FOLDERS (Virtual Folders) ===
    // Work View: Gmail Work + Proton Work inboxes
    user_pref("mail.server.server_virtual1.directory", "mailbox://nobody@smart%20mailboxes/work");
    user_pref("mail.server.server_virtual1.hostname", "smart mailboxes");
    user_pref("mail.server.server_virtual1.name", "Work");
    user_pref("mail.server.server_virtual1.type", "none");
    user_pref("mail.server.server_virtual1.virtualFolders", "Inbox");
    user_pref("mail.server.server_virtual1.Inbox.searchFolderUri", "mailbox://heartwoodcraftmt%40gmail.com@imap.gmail.com/INBOX|mailbox://eric%40iheartwoodcraft.com@127.0.0.1/INBOX");
    user_pref("mail.server.server_virtual1.Inbox.searchFolderFlag", "1");

    // Personal View: Gmail Personal + Proton Personal inboxes
    user_pref("mail.server.server_virtual2.directory", "mailbox://nobody@smart%20mailboxes/personal");
    user_pref("mail.server.server_virtual2.hostname", "smart mailboxes");
    user_pref("mail.server.server_virtual2.name", "Personal");
    user_pref("mail.server.server_virtual2.type", "none");
    user_pref("mail.server.server_virtual2.virtualFolders", "Inbox");
    user_pref("mail.server.server_virtual2.Inbox.searchFolderUri", "mailbox://eriqueokeefe%40gmail.com@imap.gmail.com/INBOX|mailbox://eriqueo%40proton.me@127.0.0.1/INBOX");
    user_pref("mail.server.server_virtual2.Inbox.searchFolderFlag", "1");
  '';

  # user.js - Core preferences
  userJs = pkgs.writeText "user.js" ''
    ${unifiedFoldersConfig}
    
    // === APPEARANCE ===
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    user_pref("ui.systemUsesDarkTheme", 1);
    user_pref("mail.ui.display.dateformat.default", 1); // Relative dates
    user_pref("mailnews.display.html_as", 3); // Plain text preferred
    user_pref("mail.inline_attachments", false);
    
    // === BEHAVIOR ===
    user_pref("mail.compose.default_to_paragraph", false); // Plain text compose
    user_pref("mailnews.mark_message_read.auto", true);
    user_pref("mailnews.mark_message_read.delay", true);
    user_pref("mailnews.mark_message_read.delay.interval", 0); // Instant mark as read
    user_pref("mail.server.default.check_new_mail", true);
    user_pref("mail.server.default.check_time", 5); // Check every 5 min
    
    // === KEYBOARD NAVIGATION ===
    user_pref("mail.advance_on_spacebar", true);
    user_pref("mail.delete_matches_sort_order", true);
    user_pref("accessibility.typeaheadfind", true);
    
    // === PRIVACY ===
    user_pref("mailnews.message_display.disable_remote_image", true);
    user_pref("mail.phishing.detection.enabled", true);
    user_pref("privacy.donottrackheader.enabled", true);
    
    // === COMPOSITION ===
    user_pref("mail.compose.autosave", true);
    user_pref("mail.compose.autosaveinterval", 2);
    user_pref("mail.identity.default.compose_html", false); // Plain text by default
    user_pref("mailnews.reply_header_type", 1); // Simple reply header
    
    // === SEARCH ===
    user_pref("mailnews.database.global.indexer.enabled", true); // Enable search indexing
    user_pref("mail.spotlight.enable", true);
  '';

  # userChrome.css - UI theme (Nord-inspired, matching your aerc theme)
  userChromeCss = pkgs.writeText "userChrome.css" ''
    /* === NORD COLOR SCHEME === */
    :root {
      --nord0: #2e3440;
      --nord1: #3b4252;
      --nord2: #434c5e;
      --nord3: #4c566a;
      --nord4: #d8dee9;
      --nord5: #e5e9f0;
      --nord6: #eceff4;
      --nord7: #8fbcbb;
      --nord8: #88c0d0;
      --nord9: #81a1c1;
      --nord10: #5e81ac;
      --nord11: #bf616a;
      --nord12: #d08770;
      --nord13: #ebcb8b;
      --nord14: #a3be8c;
      --nord15: #b48ead;
      
      /* Account colors */
      --gmail-work: var(--nord8);    /* Aqua */
      --gmail-personal: var(--nord11); /* Red */
      --proton-work: var(--nord10);   /* Blue */
      --proton-personal: var(--nord15); /* Purple */
    }

    /* === GLOBAL BACKGROUND === */
    #messengerWindow,
    #folderTree,
    #threadTree,
    #messagepane {
      background-color: var(--nord0) !important;
      color: var(--nord4) !important;
    }

    /* === FOLDER TREE === */
    #folderTree treechildren::-moz-tree-row(selected) {
      background-color: var(--nord3) !important;
    }
    
    #folderTree treechildren::-moz-tree-cell-text(selected) {
      color: var(--nord6) !important;
    }

    /* === MESSAGE LIST === */
    #threadTree treechildren::-moz-tree-row {
      background-color: var(--nord1) !important;
      border-bottom: 1px solid var(--nord0) !important;
    }

    #threadTree treechildren::-moz-tree-row(selected) {
      background-color: var(--nord3) !important;
    }

    #threadTree treechildren::-moz-tree-row(unread) {
      font-weight: bold !important;
    }

    /* Color messages by account - based on tags */
    #threadTree treechildren::-moz-tree-image(tagged, gmail-work) {
      background-color: var(--gmail-work) !important;
    }
    
    #threadTree treechildren::-moz-tree-image(tagged, gmail-personal) {
      background-color: var(--gmail-personal) !important;
    }
    
    #threadTree treechildren::-moz-tree-image(tagged, proton-work) {
      background-color: var(--proton-work) !important;
    }
    
    #threadTree treechildren::-moz-tree-image(tagged, proton-personal) {
      background-color: var(--proton-personal) !important;
    }

    /* === TOOLBAR === */
    #mail-toolbar-menubar2,
    #tabs-toolbar {
      background-color: var(--nord1) !important;
      border-bottom: 1px solid var(--nord3) !important;
    }

    /* === BUTTONS === */
    toolbarbutton {
      background-color: var(--nord2) !important;
      color: var(--nord4) !important;
      border: 1px solid var(--nord3) !important;
    }

    toolbarbutton:hover {
      background-color: var(--nord3) !important;
    }

    /* === COMPOSITION WINDOW === */
    #MsgHeadersToolbar {
      background-color: var(--nord1) !important;
    }

    /* === SCROLLBARS === */
    scrollbar {
      background-color: var(--nord0) !important;
    }

    scrollbar thumb {
      background-color: var(--nord3) !important;
    }

    scrollbar thumb:hover {
      background-color: var(--nord10) !important;
    }
  '';

  # Account configuration - framework only
  # NOTE: Accounts should be added manually via Thunderbird UI for OAuth2
  accountPrefs = ''
    // === OAUTH2 FRAMEWORK ===
    user_pref("mail.server.default.oauth2.scope", "https://mail.google.com/");
    user_pref("mail.smtpserver.default.oauth2.scope", "https://mail.google.com/");
    user_pref("mailnews.oauth2.google.scope", "https://mail.google.com/");

    // Enable OAuth2 for Gmail by default
    user_pref("mail.smtpserver.default.authMethod", 10);
    user_pref("mail.server.default.authMethod", 10);

    // Proton Work Account
    user_pref("mail.account.account3.identities", "id3");
    user_pref("mail.account.account3.server", "server3");
    user_pref("mail.identity.id3.fullName", "${realName}");
    user_pref("mail.identity.id3.useremail", "${protonWork}");
    user_pref("mail.identity.id3.valid", true);
    user_pref("mail.server.server3.hostname", "127.0.0.1"); // Proton Bridge
    user_pref("mail.server.server3.name", "${protonWork}");
    user_pref("mail.server.server3.port", 1143);
    user_pref("mail.server.server3.socketType", 2); // STARTTLS
    user_pref("mail.server.server3.type", "imap");
    user_pref("mail.server.server3.userName", "${protonWork}");
    user_pref("mail.server.server3.isSecure", true);
    user_pref("mail.server.server3.override_namespaces", true);
    user_pref("mail.smtpserver.smtp3.hostname", "127.0.0.1");
    user_pref("mail.smtpserver.smtp3.port", 1025);
    user_pref("mail.smtpserver.smtp3.username", "${protonWork}");
    user_pref("mail.smtpserver.smtp3.try_ssl", 2); // STARTTLS
    user_pref("mail.identity.id3.smtpServer", "smtp3");

    // Proton Personal Account
    user_pref("mail.account.account4.identities", "id4");
    user_pref("mail.account.account4.server", "server4");
    user_pref("mail.identity.id4.fullName", "${realName}");
    user_pref("mail.identity.id4.useremail", "${protonPersonal}");
    user_pref("mail.identity.id4.valid", true);
    user_pref("mail.server.server4.hostname", "127.0.0.1"); // Proton Bridge
    user_pref("mail.server.server4.name", "${protonPersonal}");
    user_pref("mail.server.server4.port", 1143);
    user_pref("mail.server.server4.socketType", 2); // STARTTLS
    user_pref("mail.server.server4.type", "imap");
    user_pref("mail.server.server4.userName", "${protonPersonal}");
    user_pref("mail.server.server4.isSecure", true);
    user_pref("mail.server.server4.override_namespaces", true);
    user_pref("mail.smtpserver.smtp4.hostname", "127.0.0.1");
    user_pref("mail.smtpserver.smtp4.port", 1025);
    user_pref("mail.smtpserver.smtp4.username", "${protonPersonal}");
    user_pref("mail.smtpserver.smtp4.try_ssl", 2); // STARTTLS
    user_pref("mail.identity.id4.smtpServer", "smtp4");

    // IMAP Download & Offline Settings
    // Gmail Work (server1)
    user_pref("mail.server.server1.download_on_biff", true);
    user_pref("mail.server.server1.offline_download", true);
    user_pref("mail.server.server1.check_new_mail", true);

    // Gmail Personal (server2)
    user_pref("mail.server.server2.download_on_biff", true);
    user_pref("mail.server.server2.offline_download", true);
    user_pref("mail.server.server2.check_new_mail", true);

    // Proton Work (server3)
    user_pref("mail.server.server3.download_on_biff", true);
    user_pref("mail.server.server3.offline_download", true);
    user_pref("mail.server.server3.check_new_mail", true);

    // Proton Personal (server4)
    user_pref("mail.server.server4.download_on_biff", true);
    user_pref("mail.server.server4.offline_download", true);
    user_pref("mail.server.server4.check_new_mail", true);

    // Account list
    user_pref("mail.accountmanager.accounts", "account1,account2,account3,account4,server_virtual1,server_virtual2");
    user_pref("mail.accountmanager.defaultaccount", "account1");
    user_pref("mail.smtpservers", "smtp1,smtp2,smtp3,smtp4");
  '';

  # Tags configuration
  tagsPrefs = ''
    // === TAGS FOR ACCOUNT IDENTIFICATION ===
    user_pref("mailnews.tags.gmail-work.tag", "gmail-work");
    user_pref("mailnews.tags.gmail-work.color", "#88c0d0");
    user_pref("mailnews.tags.gmail-work.ordinal", "1");
    
    user_pref("mailnews.tags.gmail-personal.tag", "gmail-personal");
    user_pref("mailnews.tags.gmail-personal.color", "#bf616a");
    user_pref("mailnews.tags.gmail-personal.ordinal", "2");
    
    user_pref("mailnews.tags.proton-work.tag", "proton-work");
    user_pref("mailnews.tags.proton-work.color", "#5e81ac");
    user_pref("mailnews.tags.proton-work.ordinal", "3");
    
    user_pref("mailnews.tags.proton-personal.tag", "proton-personal");
    user_pref("mailnews.tags.proton-personal.color", "#b48ead");
    user_pref("mailnews.tags.proton-personal.ordinal", "4");
  '';

  # Message filters for auto-tagging
  msgFilterRules = pkgs.writeText "msgFilterRules.dat" ''
    version=9
    logging=no
    
    name="Tag Gmail Work"
    enabled="yes"
    type="1"
    action="AddTag gmail-work"
    condition="AND (account,is,${gmailWork})"
    
    name="Tag Gmail Personal"
    enabled="yes"
    type="1"
    action="AddTag gmail-personal"
    condition="AND (account,is,${gmailPersonal})"
    
    name="Tag Proton Work"
    enabled="yes"
    type="1"
    action="AddTag proton-work"
    condition="AND (account,is,${protonWork})"
    
    name="Tag Proton Personal"
    enabled="yes"
    type="1"
    action="AddTag proton-personal"
    condition="AND (account,is,${protonPersonal})"
  '';

  # tbkeys configuration (aerc-like keybindings)
  tbkeysPrefs = ''
    // === KEYBOARD SHORTCUTS (requires tbkeys-lite addon) ===
    // Message list navigation
    user_pref("extensions.tbkeys.key.j", "cmd:cmd_nextMsg");
    user_pref("extensions.tbkeys.key.k", "cmd:cmd_previousMsg");
    user_pref("extensions.tbkeys.key.g.g", "cmd:cmd_firstMsg");
    user_pref("extensions.tbkeys.key.shift+g", "cmd:cmd_lastMsg");
    
    // Actions
    user_pref("extensions.tbkeys.key.d", "cmd:cmd_delete");
    user_pref("extensions.tbkeys.key.u", "cmd:cmd_undo");
    user_pref("extensions.tbkeys.key.r", "cmd:cmd_reply");
    user_pref("extensions.tbkeys.key.shift+r", "cmd:cmd_replyall");
    user_pref("extensions.tbkeys.key.f", "cmd:cmd_forward");
    user_pref("extensions.tbkeys.key.c", "cmd:cmd_newMessage");
    user_pref("extensions.tbkeys.key.a", "cmd:cmd_archive");
    
    // Search and filter
    user_pref("extensions.tbkeys.key.slash", "cmd:cmd_search");
    user_pref("extensions.tbkeys.key.n", "cmd:cmd_nextUnreadMsg");
    user_pref("extensions.tbkeys.key.shift+n", "cmd:cmd_previousUnreadMsg");
    
    // Tagging
    user_pref("extensions.tbkeys.key.t", "cmd:cmd_addTag");
    user_pref("extensions.tbkeys.key.1", "cmd:cmd_tag1");
    user_pref("extensions.tbkeys.key.2", "cmd:cmd_tag2");
    user_pref("extensions.tbkeys.key.3", "cmd:cmd_tag3");
    user_pref("extensions.tbkeys.key.4", "cmd:cmd_tag4");
    
    // Folder navigation (space-based like aerc)
    user_pref("extensions.tbkeys.key.space.w", "unifiedFolders"); // Work view
    user_pref("extensions.tbkeys.key.space.p", "unifiedFolders"); // Personal view
    user_pref("extensions.tbkeys.key.space.i", "cmd:cmd_goFolder,Inbox");
    user_pref("extensions.tbkeys.key.space.s", "cmd:cmd_goFolder,Sent");
    user_pref("extensions.tbkeys.key.space.d", "cmd:cmd_goFolder,Drafts");
    user_pref("extensions.tbkeys.key.space.t", "cmd:cmd_goFolder,Trash");
  '';


in {
  # Module structure for integration with betterbird/index.nix
  packages = [ pkgs.thunderbird ];

  env = {
    THUNDERBIRD_PROFILE = "default";
  };

  services = {
    # No services needed for IMAP-only mode
  };

  files = profileBase: {
    # Declarative profile files
    ".betterbird/profiles.ini".text = ''
      [General]
      StartWithLastProfile=1
      Version=2

      [Profile0]
      Name=default
      IsRelative=1
      Path=profiles/default
      Default=1
    '';

    ".betterbird/profiles/default/user.js".source = userJs;
    ".betterbird/profiles/default/chrome/userChrome.css".source = userChromeCss;

    ".betterbird/profiles/default/prefs.js".text = ''
      # Mozilla User Preferences
      ${accountPrefs}
      ${tagsPrefs}
      ${tbkeysPrefs}
    '';

    # Auto-start script
    ".local/bin/mail-gui" = {
      executable = true;
      text = ''
        #!/bin/sh
        # Thunderbird launcher with Bridge integration
        set -e

        # Check if this is first run
        PROFILE_DIR="${config.home.homeDirectory}/.betterbird/profiles/default"
        FIRST_RUN=false
        if [ ! -d "$PROFILE_DIR/ImapMail" ]; then
          FIRST_RUN=true
        fi

        # Check if Proton Bridge is running
        if ! pgrep -x "protonmail-bridge" >/dev/null 2>&1; then
          echo "🔄 Starting Proton Bridge..."
          if command -v protonmail-bridge >/dev/null 2>&1; then
            protonmail-bridge --cli &
            sleep 3
          else
            echo "⚠️  Proton Bridge not found - Proton accounts may not work"
          fi
        else
          echo "✅ Proton Bridge already running"
        fi

        # Check certificate
        if [ -f "/etc/ssl/local/proton-bridge.pem" ]; then
          echo "✅ Proton Bridge certificate ready"
        else
          echo "⚠️  Proton Bridge certificate missing - STARTTLS may fail"
        fi

        if [ "$FIRST_RUN" = "true" ]; then
          echo ""
          echo "📧 FIRST-TIME SETUP REQUIRED:"
          echo ""
          echo "ADD GMAIL ACCOUNTS MANUALLY:"
          echo "1. Account Settings → Account Actions → Add Mail Account"
          echo "2. Gmail Work: heartwoodcraftmt@gmail.com"
          echo "3. Gmail Personal: eriqueokeefe@gmail.com"
          echo "4. Use 'Configure manually' and set Authentication to 'OAuth2'"
          echo "5. Thunderbird will open browser for Google sign-in"
          echo ""
          echo "ADD PROTON ACCOUNTS:"
          echo "6. Proton Work: eric@iheartwoodcraft.com (Bridge password)"
          echo "7. Proton Personal: eriqueo@proton.me (Bridge password)"
          echo "8. Server: 127.0.0.1:1143 (IMAP), 127.0.0.1:1025 (SMTP), STARTTLS"
          echo ""
          echo "OPTIONAL:"
          echo "9. Install tbkeys-lite addon for vim-like keybindings"
          echo "10. Enable unified folders in View menu"
          echo ""
        fi

        echo "🚀 Starting Thunderbird..."
        thunderbird
      '';
    };

    # Setup guide script
    ".local/bin/betterbird-setup" = {
      executable = true;
      text = ''
        #!/bin/sh
        echo "=== Thunderbird Email Account Setup Guide ==="
        echo ""
        echo "🔧 GMAIL ACCOUNTS (OAuth2 - No App Passwords Needed):"
        echo ""
        echo "1. Open Thunderbird Account Settings"
        echo "2. Account Actions → Add Mail Account"
        echo ""
        echo "GMAIL WORK:"
        echo "   Email: heartwoodcraftmt@gmail.com"
        echo "   Click 'Configure manually'"
        echo "   IMAP: imap.gmail.com:993 (SSL/TLS)"
        echo "   SMTP: smtp.gmail.com:465 (SSL/TLS)"
        echo "   Authentication: OAuth2 (both IMAP & SMTP)"
        echo ""
        echo "GMAIL PERSONAL:"
        echo "   Email: eriqueokeefe@gmail.com"
        echo "   Same settings as above"
        echo ""
        echo "🔧 PROTON ACCOUNTS (Bridge Required):"
        echo ""
        echo "PROTON WORK:"
        echo "   Email: eric@iheartwoodcraft.com"
        echo "   IMAP: 127.0.0.1:1143 (STARTTLS)"
        echo "   SMTP: 127.0.0.1:1025 (STARTTLS)"
        echo "   Authentication: Normal password"
        echo "   Password: Use Bridge-generated password"
        echo ""
        echo "PROTON PERSONAL:"
        echo "   Email: eriqueo@proton.me"
        echo "   Same settings as above"
        echo ""
        echo "📋 Bridge Password Commands:"
        echo "   protonmail-bridge --cli"
        echo "   > list"
        echo "   > info 0  # Shows passwords for each account"
        echo ""
        echo "🎯 After Setup:"
        echo "   • View → Folder Pane → Unified Folders"
        echo "   • Install tbkeys-lite addon for vim keybindings"
        echo "   • Check status: betterbird-status"
      '';
    };

    # Integration info script
    ".local/bin/betterbird-status" = {
      executable = true;
      text = ''
        #!/bin/sh
        echo "=== Thunderbird IMAP Integration Status ==="
        echo ""
        echo "📁 Profile: ${profileDir}"
        echo "🔐 Proton Bridge: $(systemctl --user is-active protonmail-bridge.service 2>/dev/null || echo 'not managed by systemd')"
        echo "📜 Certificate: $([ -f /etc/ssl/local/proton-bridge.pem ] && echo 'present' || echo 'missing')"
        echo ""
        echo "⚙️  Profile exists: $([ -d '${profileDir}' ] && echo 'yes' || echo 'no')"
        echo "📧 IMAP Storage: $([ -d '${profileDir}/ImapMail' ] && echo '~/.betterbird/profiles/default/ImapMail' || echo 'not created yet')"
        echo ""
        echo "🔗 Email Architecture:"
        echo "   • aerc ← → ~/Maildir ← → mbsync ← → IMAP Servers"
        echo "   • Thunderbird ← → ~/.betterbird/ImapMail ← → IMAP Servers"
        echo "   • Separate systems, no shared storage"
        echo ""
        echo "📂 Setup Guide: betterbird-setup"
      '';
    };
  };

}
