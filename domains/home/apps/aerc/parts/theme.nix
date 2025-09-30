# aerc theme.nix - Adapter from palette to aerc styleset tokens
# Generates comprehensive aerc styleset with hex colors
{ config, lib, ... }:

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
  tokens = {
    # ===== CORE UI ELEMENTS (Official) =====
    default = token (hex c.fg1) "default" false;
    error = token (hex c.error) "default" false;
    warning = token (hex c.warning) "default" false;
    success = token (hex c.success) "default" false;
    title = token (hex c.fg0) (hex c.bg2) true;
    header = token (hex c.accent) "default" true;

    # ===== TAB STYLING (Official + Custom) =====
    tab = token (hex c.fg2) (hex c.bg2) false;  # Official: single tab style
    tab_default = token (hex c.fg2) (hex c.bg2) false;  # Custom: keep for compatibility
    tab_selected = token (hex c.bg1) (hex c.accent) true;  # Custom: selected state

    # ===== BORDERS & UI CHROME (Official) =====
    border = token (hex c.border) "default" false;
    stack = token (hex c.fg2) (hex c.bg1) false;  # UI stack element
    spinner = token (hex c.accent) "default" false;

    # ===== MESSAGE LIST (Official + Custom) =====
    msglist_default = token (hex c.fg1) "default" false;
    msglist_unread = token (hex c.warning) "default" true;
    msglist_read = token (hex c.fg2) "default" false;
    msglist_flagged = token (hex c.errorBright) "default" true;
    msglist_deleted = token (hex c.fg3) "default" false;
    msglist_marked = token (hex c.bg1) (hex c.marked) true;
    msglist_result = token (hex c.accent) "default" true;

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

    # Selected states for message list
    msglist_default_selected = token (hex c.bg1) (hex c.selection) true;
    msglist_unread_selected = token (hex c.bg1) (hex c.selection) true;
    msglist_read_selected = token (hex c.bg1) (hex c.selection) false;
    msglist_flagged_selected = token (hex c.bg1) (hex c.errorBright) true;

    # ===== DIRECTORY LIST (sidebar/folders) =====
    dirlist_default = token (hex c.fg2) "default" false;
    dirlist_unread = token (hex c.success) "default" true;
    dirlist_recent = token (hex c.accent) "default" false;
    dirlist_selected = token (hex c.bg1) (hex c.selection) true;

    # ===== STATUS LINE =====
    statusline_default = token (hex c.fg1) (hex c.bg0) false;
    statusline_error = token (hex c.errorBright) (hex c.bg0) true;
    statusline_success = token (hex c.success) (hex c.bg0) false;

    # ===== COMPLETION POPOVER (Official + Custom) =====
    completion_default = token (hex c.fg1) (hex c.bg2) false;
    completion_selected = token (hex c.bg1) (hex c.selection) false;  # Custom

    # Official: Additional completion styles
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

    # ===== PER-COLUMN COLORS (message list columns) =====
    index_number = token (hex c.fg3) "default" false;
    index_flags = token (hex c.warning) "default" false;
    index_date = token (hex c.info) "default" false;
    index_author = token (hex c.success) "default" false;
    index_size = token (hex c.fg3) "default" false;
    index_subject = token (hex c.fg1) "default" false;

    # Selected column states
    index_number_selected = token (hex c.bg1) (hex c.selection) false;
    index_flags_selected = token (hex c.bg1) (hex c.selection) false;
    index_date_selected = token (hex c.bg1) (hex c.selection) false;
    index_author_selected = token (hex c.bg1) (hex c.selection) false;
    index_size_selected = token (hex c.bg1) (hex c.selection) false;
    index_subject_selected = token (hex c.bg1) (hex c.selection) true;

    # ===== VIEWER CONTENT COLORS (email body) =====
    # Official viewer section: Basic elements
    url = token (hex c.link) "default" false;  # Official: URLs (underline in defaults)
    signature = token (hex c.fg3) "default" false;  # Official: email signatures

    # Custom: Email headers (more specific than official "header")
    hdr_default = token (hex c.info) "default" false;
    hdr_from = token (hex c.accent) "default" false;
    hdr_to = token (hex c.accentAlt) "default" false;
    hdr_subject = token (hex c.accent) "default" true;
    hdr_date = token (hex c.info) "default" false;
    hdr_ccbcc = token (hex c.fg2) "default" false;

    # Custom: URL and links (body_ prefix for specificity)
    body_url = token (hex c.link) "default" false;
    body_email = token (hex c.linkHover) "default" false;

    # Quoted text levels (nested replies) - Custom names
    quoted0 = token (hex c.success) "default" false;
    quoted1 = token (hex c.info) "default" false;
    quoted2 = token (hex c.accent) "default" false;
    quoted3 = token (hex c.warning) "default" false;
    quoted4 = token (hex c.error) "default" false;
    quoted5 = token (hex c.errorBright) "default" false;

    # Official viewer section: quote_* for colorize filter
    quote_1 = token (hex c.success) "default" false;
    quote_2 = token (hex c.info) "default" false;
    quote_3 = token (hex c.accent) "default" false;
    quote_4 = token (hex c.warning) "default" false;
    quote_x = token (hex c.error) "default" false;  # Above level 4

    # Code and formatting
    body_code = token (hex c.fileCode) "default" false;
    body_bold = token (hex c.fg0) "default" true;
    body_italic = token (hex c.fg2) "default" false;
    body_h1 = token (hex c.accent) "default" true;
    body_h2 = token (hex c.accentAlt) "default" true;
    body_h3 = token (hex c.success) "default" false;
    body_listitem = token (hex c.warning) "default" false;

    # Diff/patch colors (Official viewer section)
    diff_meta = token (hex c.info) "default" true;
    diff_chunk = token (hex c.accent) "default" false;
    diff_chunk_func = token (hex c.accentAlt) "default" false;  # Official: function names in chunks
    diff_add = token (hex c.successBright) (hex c.bg0) false;
    diff_del = token (hex c.errorBright) (hex c.bg0) false;
    diff_context = token (hex c.fg2) "default" false;  # Custom: unchanged lines

    # GPG/encryption status
    body_sig_good = token (hex c.success) "default" false;
    body_sig_bad = token (hex c.error) "default" false;
    body_sig_unknown = token (hex c.warning) "default" false;
    body_gpg_good = token (hex c.fg3) "default" false;
    body_gpg_any = token (hex c.warning) "default" false;
    body_gpg_bad = token (hex c.errorBright) (hex c.errorDim) false;

    # Emoticons and special content
    body_emote = token (hex c.accent) "default" false;
  };

  # Boolean attributes (aerc uses string values)
  attrs = {
    bold = "true";
    normal = "false";
    italic = "true";
    underline = "true";
    dim = "true";
    reverse = "true";
    blink = "true";
  };
}