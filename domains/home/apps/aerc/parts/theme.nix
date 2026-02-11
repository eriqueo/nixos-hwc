# aerc theme.nix - Adapter from palette to aerc styleset tokens
# Generates comprehensive aerc styleset with hex colors
{ config, lib, osConfig ? {}, ... }:

let
  # Consume global theme colors from config.hwc.home.theme.colors
  # This automatically updates when hwc.home.theme.palette changes
  c = config.hwc.home.theme.colors or {};

  # Helper to format hex colors for aerc (with # prefix)
  hex = color: "#${color}";

  # Aerc styleset token generator
  # Creates fg/bg/bold tuple for each UI element
  token = fg: bg: bold: { inherit fg bg bold; };

in {
  # Main section styles (no [section] prefix)
  tokens = {
    # ===== CORE UI ELEMENTS (Official) =====
    default = token (hex c.fg1) "default" false;
    error = token (hex c.error) "default" false;
    warning = token (hex c.warning) "default" false;
    success = token (hex c.success) "default" false;
    title = token (hex c.fg0) (hex c.bg2) true;
    header = token (hex c.accent) "default" true;

    # ===== TAB STYLING (Official) =====
    tab = token (hex c.fg2) (hex c.bg2) false;

    # ===== BORDERS & UI CHROME (Official) =====
    border = token (hex c.border) "default" false;
    stack = token (hex c.fg2) (hex c.bg1) false;  # UI stack element
    spinner = token (hex c.accent) "default" false;


     # A more general but powerful approach using the wildcard from the man page:
    "*.selected" = token (hex c.fg0) (hex c.bg3) true;

    # ===== MESSAGE LIST (Official + Custom) =====
    msglist_default = token (hex c.fg1) "default" false;
    msglist_unread = token (hex c.warning) "default" true;
    msglist_read = token (hex c.fg2) "default" false;
    msglist_flagged = token (hex c.errorBright) "default" true;
    msglist_deleted = token (hex c.fg3) "default" false;
    msglist_marked = token (hex c.bg1) (hex c.marked) true;
    msglist_result = token (hex c.accent) "default" true;

    # ===== SOURCE ACCOUNT COLORS (Colored text, not background) =====
    # Match against To/Cc/From headers to color by account in unified view.
    # Using subtle colors for text to preserve selection highlighting
    # Work primary (iheartwoodcraft.com) - green
    "msglist_*.To,~iheartwoodcraft.com"   = token (hex c.success) "default" false;
    "msglist_*.Cc,~iheartwoodcraft.com"   = token (hex c.success) "default" false;
    "msglist_*.From,~iheartwoodcraft.com" = token (hex c.success) "default" false;

    # Gmail business (heartwoodcraftmt@gmail.com) - teal/aqua
    "msglist_*.To,~heartwoodcraftmt@gmail.com"   = token (hex c.accent) "default" false;
    "msglist_*.Cc,~heartwoodcraftmt@gmail.com"   = token (hex c.accent) "default" false;
    "msglist_*.From,~heartwoodcraftmt@gmail.com" = token (hex c.accent) "default" false;

    # Gmail personal (eriqueokeefe@gmail.com) - purple
    "msglist_*.To,~eriqueokeefe@gmail.com"   = token (hex c.accentAlt) "default" false;
    "msglist_*.Cc,~eriqueokeefe@gmail.com"   = token (hex c.accentAlt) "default" false;
    "msglist_*.From,~eriqueokeefe@gmail.com" = token (hex c.accentAlt) "default" false;

    # Proton personal (eriqueo@proton.me) - orange/yellow
    "msglist_*.To,~eriqueo@proton.me"   = token (hex c.warning) "default" false;
    "msglist_*.Cc,~eriqueo@proton.me"   = token (hex c.warning) "default" false;
    "msglist_*.From,~eriqueo@proton.me" = token (hex c.warning) "default" false;


    # Official: Additional message states
    msglist_answered = token (hex c.success) "default" false;
    msglist_forwarded = token (hex c.info) "default" false;

    # Official: Thread-related styles
    msglist_thread_folded = token (hex c.accent) "default" false;
    msglist_thread_context = token (hex c.fg3) "default" false;
    msglist_thread_orphan = token (hex c.errorDim) "default" false;

    # Official: UI chrome for message list
    msglist_gutter = token (hex c.bg3) (hex c.bg2) false;
    msglist_pill = token (hex c.fg0) (hex c.bg3) false;

    # ===== DIRECTORY LIST (Official) =====
    dirlist_default = token (hex c.fg2) "default" false;
    dirlist_unread = token (hex c.success) "default" true;
    dirlist_recent = token (hex c.accent) "default" false;

    # ===== STATUS LINE =====
    statusline_default = token (hex c.fg1) (hex c.bg0) false;
    statusline_error = token (hex c.errorBright) (hex c.bg0) true;
    statusline_success = token (hex c.success) (hex c.bg0) false;

    # ===== COMPLETION POPOVER (Official) =====
    completion_default = token (hex c.fg1) (hex c.bg2) false;
    completion_description = token (hex c.fg3) (hex c.bg2) false;
    completion_gutter = token (hex c.bg3) (hex c.bg2) false;
    completion_pill = token (hex c.fg0) (hex c.bg3) false;

    # ===== MESSAGE VIEWER/COMPOSER (Official) =====
    part_switcher = token (hex c.bg2) (hex c.bg1) false;
    part_filename = token (hex c.fg0) "default" false;
    part_mimetype = token (hex c.fg3) "default" false;

    selector_default = token (hex c.fg1) "default" false;
    selector_focused = token (hex c.bg1) (hex c.selection) false;
    selector_chooser = token (hex c.accent) "default" true;

    # ===== PER-COLUMN COLORS (Custom enhancement for message list) =====
    # Note: These are NOT in official spec but may work
   # index_number = token (hex c.fg3) "default" false;
   # index_flags = token (hex c.warning) "default" false;
   # index_date = token (hex c.info) "default" false;
   # index_author = token (hex c.success) "default" false;
   # index_size = token (hex c.fg3) "default" false;
   # index_subject = token (hex c.fg1) "default" false;

    # ===== NOTMUCH TAG-BASED COLORS (legacy/optional) =====
    # Domain-level tags (use only these to color messages)
    "[messages].Tag:work"          = token (hex c.info)        "default" true;  #// Work domain: Bold info color
    "[messages].Tag:personal"      = token (hex c.success)     "default" true;  #// Personal domain: Bold success color

    # Status tags - OVERRIDE msglist_unread with account colors
    "[messages].Tag:unread"        = token (hex c.warning)     "default" true;  #// Unread: Bold warning
    "[messages].Tag:starred"       = token (hex c.errorBright) "default" true;  #// Starred: Bright error (star color)
    "[messages].Tag:action"        = token (hex c.marked)      (hex c.bg2) true; #// Action required: Highlighted
  };

  # [viewer] section styles - used by built-in colorize filter
  viewerTokens = {
    url = token (hex c.link) "default" false;
    header = token (hex c.accent) "default" true;
    signature = token (hex c.fg3) "default" false;

    # Diff/patch colors
    diff_meta = token (hex c.info) "default" true;
    diff_chunk = token (hex c.accent) "default" false;
    diff_chunk_func = token (hex c.accentAlt) "default" false;
    diff_add = token (hex c.successBright) "default" false;
    diff_del = token (hex c.errorBright) "default" false;

    # Quote levels for nested replies
    quote_1 = token (hex c.success) "default" false;
    quote_2 = token (hex c.info) "default" false;
    quote_3 = token (hex c.accent) "default" false;
    quote_4 = token (hex c.warning) "default" false;
    quote_x = token (hex c.error) "default" false;
  };
}
