# aerc theme.nix - adapter from palette to aerc styleset tokens
{ config, lib, ... }:

let
  # Consume global theme colors from config.hwc.home.theme.colors
  # This automatically updates when hwc.home.theme.palette changes
  colors = config.hwc.home.theme.colors or {};

  # Aerc uses different color specification than neomutt
  # It supports: "default", w3c color names, hex codes, palette indices
  roleToAerc = {
    # Map terminal color roles to appropriate values for aerc
    red = "red"; brightRed = "lightred"; 
    green = "green"; brightGreen = "lightgreen";
    yellow = "yellow"; brightYellow = "lightyellow"; 
    blue = "blue"; brightBlue = "lightblue";
    magenta = "magenta"; brightMagenta = "lightmagenta"; 
    cyan = "cyan"; brightCyan = "lightcyan";
    black = "black"; brightBlack = "gray"; 
    white = "white"; brightWhite = "brightwhite";
    default = "default";
  };

  # Map semantic colors for aerc (similar to neomutt but adapted for aerc's style objects)
  pick = {
    fg           = roleToAerc.white;
    fgDim        = roleToAerc.brightBlack;
    bg           = roleToAerc.default;
    muted        = roleToAerc.brightBlack;

    good         = roleToAerc.green;
    warn         = roleToAerc.yellow;
    crit         = roleToAerc.red;
    info         = roleToAerc.blue;

    accent       = roleToAerc.cyan;
    accentAlt    = roleToAerc.magenta;
    accent2      = roleToAerc.brightBlue;

    selectionFg  = roleToAerc.black;
    selectionBg  = roleToAerc.cyan;

    b_good       = roleToAerc.brightGreen;
    b_warn       = roleToAerc.brightYellow;
    b_crit       = roleToAerc.brightRed;
    b_info       = roleToAerc.brightBlue;
    b_accent     = roleToAerc.brightCyan;
    b_accentAlt  = roleToAerc.brightMagenta;
    b_fg         = roleToAerc.brightWhite;
  };

  # Helper function to create style token
  token = fg: bg: bold: { inherit fg bg bold; };

in {
  tokens = {
    # ===== CORE UI ELEMENTS (aerc specific) =====
    default = token pick.fg pick.bg false;
    error = token pick.crit pick.bg false;
    warning = token pick.warn pick.bg false;
    success = token pick.good pick.bg false;
    
    # ===== TAB STYLING =====
    tab_default = token pick.fgDim pick.bg false;
    tab_selected = token pick.fg pick.bg true;
    
    # ===== BORDERS =====
    border = token pick.muted pick.bg false;
    
    # ===== MESSAGE LIST (equivalent to neomutt index colors) =====
    msglist_default = token pick.warn pick.bg false;
    msglist_unread = token pick.b_warn pick.bg true;
    msglist_read = token pick.warn pick.bg false;
    msglist_flagged = token pick.crit pick.bg true;
    msglist_deleted = token pick.fgDim pick.bg false;
    msglist_marked = token pick.selectionFg pick.selectionBg true;
    msglist_result = token pick.b_accent pick.bg true;
    
    # Selected states for message list
    msglist_default_selected = token pick.selectionFg pick.selectionBg true;
    msglist_unread_selected = token pick.b_warn pick.selectionBg true;
    msglist_read_selected = token pick.warn pick.selectionBg true;
    msglist_flagged_selected = token pick.b_crit pick.selectionBg true;
    
    # ===== DIRECTORY LIST (sidebar equivalent) =====
    dirlist_default = token pick.fgDim pick.bg false;
    dirlist_unread = token pick.good pick.bg true;
    dirlist_recent = token pick.accent pick.bg false;
    dirlist_selected = token pick.selectionFg pick.selectionBg true;
    
    # ===== STATUS LINE =====
    statusline_default = token pick.b_warn pick.bg false;
    statusline_error = token pick.crit pick.bg true;
    statusline_success = token pick.good pick.bg false;
    
    # ===== COMPLETION POPOVER =====
    completion_default = token pick.fg pick.bg false;
    completion_selected = token pick.selectionFg pick.selectionBg false;
    
    # ===== MESSAGE VIEWER/COMPOSER =====
    part_switcher = token pick.accent pick.bg false;
    selector_default = token pick.fg pick.bg false;
    selector_focused = token pick.selectionFg pick.selectionBg false;
    selector_chooser = token pick.accent pick.bg false;
    
    # ===== SPINNER =====
    spinner = token pick.accent pick.bg false;
    
    # ===== VIEWER CONTENT COLORS (for colorize filter) =====
    # Email headers
    hdr_default = token pick.info pick.bg false;
    hdr_from = token pick.b_accentAlt pick.bg false;
    hdr_subject = token pick.b_accent pick.bg false;
    hdr_ccbcc = token pick.b_fg pick.bg false;
    
    # URL and links
    body_url = token pick.b_info pick.bg false;
    body_email = token pick.b_crit pick.bg false;
    
    # Quoted text levels
    quoted0 = token pick.good pick.bg false;
    quoted1 = token pick.info pick.bg false;
    quoted2 = token pick.accent pick.bg false;
    quoted3 = token pick.warn pick.bg false;
    quoted4 = token pick.crit pick.bg false;
    quoted5 = token pick.b_crit pick.bg false;
    
    # Code and formatting
    body_code = token pick.good pick.bg false;
    body_h1 = token pick.b_info pick.bg false;
    body_h2 = token pick.b_accent pick.bg false;
    body_h3 = token pick.b_good pick.bg false;
    body_listitem = token pick.warn pick.bg false;
    
    # Signature
    signature = token pick.good pick.bg false;
    
    # Diff/patch colors
    diff_meta = token pick.b_info pick.bg true;
    diff_chunk = token pick.b_accent pick.bg false;
    diff_add = token pick.b_good pick.bg false;
    diff_del = token pick.b_crit pick.bg false;
    
    # GPG/encryption
    body_sig_good = token pick.accent pick.bg false;
    body_sig_bad = token pick.crit pick.bg false;
    body_gpg_good = token pick.muted pick.bg false;
    body_gpg_any = token pick.b_warn pick.bg false;
    body_gpg_bad = token pick.b_warn pick.crit false;
    
    # Emoticons and special content
    body_emote = token pick.b_accent pick.bg false;
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
