{ config, lib, pkgs, ... }:

let
  # Your email addresses - FILL THESE IN
  gmailWork = "heartwoodcraftmt@gmail.com";
  gmailPersonal = "eriqueokeefe@gmail.com";
  protonWork = "eric@iheartwoodcraft.com";
  protonPersonal = "eriqueo@proton.me";
  
  realName = "Eric O'Keefe";

  # Profile directory structure
  profileDir = "${config.home.homeDirectory}/.thunderbird/profiles/default";

  # user.js - Core preferences
  userJs = pkgs.writeText "user.js" ''
    // === UNIFIED FOLDERS ===
    user_pref("mail.folder.views.version", 1);
    user_pref("mailnews.default_view_flags", 1); // Unified folders view
    
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

  # prefs.js template - Account configuration
  # NOTE: User will need to add passwords via Thunderbird GUI on first run
  accountPrefs = ''
    // === ACCOUNT STRUCTURE ===
    // Gmail Work Account
    user_pref("mail.account.account1.identities", "id1");
    user_pref("mail.account.account1.server", "server1");
    user_pref("mail.identity.id1.fullName", "${realName}");
    user_pref("mail.identity.id1.useremail", "${gmailWork}");
    user_pref("mail.identity.id1.valid", true);
    user_pref("mail.server.server1.hostname", "imap.gmail.com");
    user_pref("mail.server.server1.name", "${gmailWork}");
    user_pref("mail.server.server1.port", 993);
    user_pref("mail.server.server1.socketType", 3); // SSL/TLS
    user_pref("mail.server.server1.type", "imap");
    user_pref("mail.server.server1.userName", "${gmailWork}");
    user_pref("mail.smtpserver.smtp1.hostname", "smtp.gmail.com");
    user_pref("mail.smtpserver.smtp1.port", 465);
    user_pref("mail.smtpserver.smtp1.username", "${gmailWork}");
    user_pref("mail.identity.id1.smtpServer", "smtp1");

    // Gmail Personal Account  
    user_pref("mail.account.account2.identities", "id2");
    user_pref("mail.account.account2.server", "server2");
    user_pref("mail.identity.id2.fullName", "${realName}");
    user_pref("mail.identity.id2.useremail", "${gmailPersonal}");
    user_pref("mail.identity.id2.valid", true);
    user_pref("mail.server.server2.hostname", "imap.gmail.com");
    user_pref("mail.server.server2.name", "${gmailPersonal}");
    user_pref("mail.server.server2.port", 993);
    user_pref("mail.server.server2.socketType", 3);
    user_pref("mail.server.server2.type", "imap");
    user_pref("mail.server.server2.userName", "${gmailPersonal}");
    user_pref("mail.smtpserver.smtp2.hostname", "smtp.gmail.com");
    user_pref("mail.smtpserver.smtp2.port", 465);
    user_pref("mail.smtpserver.smtp2.username", "${gmailPersonal}");
    user_pref("mail.identity.id2.smtpServer", "smtp2");

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
    user_pref("mail.smtpserver.smtp3.hostname", "127.0.0.1");
    user_pref("mail.smtpserver.smtp3.port", 1025);
    user_pref("mail.smtpserver.smtp3.username", "${protonWork}");
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
    user_pref("mail.server.server4.socketType", 2);
    user_pref("mail.server.server4.type", "imap");
    user_pref("mail.server.server4.userName", "${protonPersonal}");
    user_pref("mail.smtpserver.smtp4.hostname", "127.0.0.1");
    user_pref("mail.smtpserver.smtp4.port", 1025);
    user_pref("mail.smtpserver.smtp4.username", "${protonPersonal}");
    user_pref("mail.identity.id4.smtpServer", "smtp4");

    // Account list
    user_pref("mail.accountmanager.accounts", "account1,account2,account3,account4");
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

  # Setup script to initialize profile
  setupScript = pkgs.writeShellScript "setup-thunderbird-profile" ''
    set -e
    
    PROFILE_DIR="${profileDir}"
    
    echo "Setting up Thunderbird profile at $PROFILE_DIR..."
    
    # Create profile directory structure
    mkdir -p "$PROFILE_DIR"
    mkdir -p "$PROFILE_DIR/chrome"
    mkdir -p "$PROFILE_DIR/ImapMail"
    
    # Copy configuration files
    cp ${userJs} "$PROFILE_DIR/user.js"
    cp ${userChromeCss} "$PROFILE_DIR/chrome/userChrome.css"
    
    # Initialize prefs.js if it doesn't exist
    if [ ! -f "$PROFILE_DIR/prefs.js" ]; then
      cat > "$PROFILE_DIR/prefs.js" <<'EOF'
    # Mozilla User Preferences
    ${accountPrefs}
    ${tagsPrefs}
    ${tbkeysPrefs}
    EOF
    fi
    
    # Set up profiles.ini to use this profile
    PROFILES_INI="${config.home.homeDirectory}/.thunderbird/profiles.ini"
    mkdir -p "$(dirname "$PROFILES_INI")"
    
    cat > "$PROFILES_INI" <<EOF
    [General]
    StartWithLastProfile=1
    Version=2

    [Profile0]
    Name=default
    IsRelative=1
    Path=profiles/default
    Default=1
    EOF
    
    echo "✅ Profile setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Start Thunderbird: thunderbird"
    echo "2. Install tbkeys-lite addon for custom keybindings"
    echo "3. Add passwords for all 4 accounts (Thunderbird will prompt)"
    echo "4. For Proton accounts: Start proton-bridge first"
    echo ""
    echo "Your unified inboxes will be available in the 'Unified' folder view."
  '';

in {
  home.packages = [ pkgs.thunderbird ];
  
  home.activation.setupThunderbirdProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${setupScript}
  '';
  
  # Optional: Auto-start script
  home.file.".local/bin/mail" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Start proton bridge if needed
      if command -v protonmail-bridge >/dev/null 2>&1; then
        protonmail-bridge --cli &
        sleep 2
      fi
      
      # Start Thunderbird
      thunderbird
    '';
  };
}
