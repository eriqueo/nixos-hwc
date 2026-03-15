# aerc theme.nix – Generates a valid aerc styleset file from your palette
{ config, lib, osConfig ? {}, ... }:

let
  c = config.hwc.home.theme.colors or {};

  hex = color: "#${color}";

  # Helper to generate a full <object>.<attr> = value line
  styleLine = obj: attr: val:
    if val == null then "" else "${obj}.${attr} = ${val}";

  # Helper for boolean attrs (true/false/toggle)
  boolLine = obj: attr: val:
    if val == null then "" else styleLine obj attr (if val then "true" else "false");

in {
  # This attribute will be used in config.nix to write the styleset file
  stylesetContent = ''
    # hwc-theme – Gruvbox-inspired dark theme for aerc
    # Generated from palette – valid per aerc-stylesets(7)

    # Reset most defaults so we have full control
    *.default = true
    *.normal  = true

    # ──────────────────────────────────────────────────────────────
    # Core UI elements (main section)
    # ──────────────────────────────────────────────────────────────

    default.fg          = ${hex c.fg1}
    error.fg            = ${hex c.error}
    error.bold          = true
    warning.fg          = ${hex c.warning}
    warning.bold        = true
    success.fg          = ${hex c.success}
    success.bold        = true

    title.fg            = ${hex c.fg0}
    title.bg            = ${hex c.bg2}
    title.bold          = true

    header.fg           = ${hex c.accent}
    header.bold         = true

    tab.fg              = ${hex c.fg2}
    tab.bg              = ${hex c.bg2}

    border.fg           = ${hex c.border}

    stack.fg            = ${hex c.fg2}
    stack.bg            = ${hex c.bg1}

    spinner.fg          = ${hex c.accent}
    spinner.bold        = true

    # Selection highlight (wildcard)
    *.selected.fg       = ${hex c.fg0}
    *.selected.bg       = ${hex c.bg3}
    *.selected.bold     = true

    # ──────────────────────────────────────────────────────────────
    # Message list
    # ──────────────────────────────────────────────────────────────

    msglist_default.fg          = default
    msglist_unread.fg           = ${hex c.warning}
    msglist_unread.bold         = true
    msglist_read.fg             = ${hex c.fg3}
    msglist_flagged.fg          = ${hex c.errorBright}
    msglist_flagged.bold        = true
    msglist_deleted.fg          = ${hex c.fg3}
    msglist_marked.fg           = ${hex c.marked}
    msglist_marked.bg           = ${hex c.bg2}
    msglist_marked.bold         = true
    msglist_result.fg           = ${hex c.accent}
    msglist_result.bold         = true

    msglist_answered.fg         = ${hex c.success}
    msglist_forwarded.fg        = ${hex c.info}

    msglist_thread_folded.fg    = ${hex c.accent}
    msglist_thread_context.fg   = ${hex c.fg3}
    msglist_thread_orphan.fg    = ${hex c.errorDim}

    msglist_gutter.bg           = ${hex c.bg3}
    msglist_gutter.fg           = ${hex c.bg2}
    msglist_pill.fg             = ${hex c.fg0}
    msglist_pill.bg             = ${hex c.bg3}

    # Dynamic From/To/Cc coloring by domain
    msglist_*.From,~iheartwoodcraft.com.fg   = ${hex c.success}
    msglist_*.To,~iheartwoodcraft.com.fg     = ${hex c.success}
    msglist_*.Cc,~iheartwoodcraft.com.fg     = ${hex c.success}

    msglist_*.From,~heartwoodcraftmt@gmail.com.fg = ${hex c.accent}
    msglist_*.To,~heartwoodcraftmt@gmail.com.fg   = ${hex c.accent}
    msglist_*.Cc,~heartwoodcraftmt@gmail.com.fg   = ${hex c.accent}

    msglist_*.From,~eriqueokeefe@gmail.com.fg = ${hex c.accentAlt}
    msglist_*.To,~eriqueokeefe@gmail.com.fg   = ${hex c.accentAlt}
    msglist_*.Cc,~eriqueokeefe@gmail.com.fg   = ${hex c.accentAlt}

    msglist_*.From,~eriqueo@proton.me.fg = ${hex c.warning}
    msglist_*.To,~eriqueo@proton.me.fg   = ${hex c.warning}
    msglist_*.Cc,~eriqueo@proton.me.fg   = ${hex c.warning}

    # ──────────────────────────────────────────────────────────────
    # Directory list
    # ──────────────────────────────────────────────────────────────

    dirlist_default.fg  = ${hex c.fg2}
    dirlist_unread.fg   = ${hex c.success}
    dirlist_unread.bold = true
    dirlist_recent.fg   = ${hex c.accent}

    # ──────────────────────────────────────────────────────────────
    # Statusline & completion
    # ──────────────────────────────────────────────────────────────

    statusline_default.fg  = ${hex c.fg1}
    statusline_default.bg  = ${hex c.bg0}
    statusline_default.dim = true

    statusline_error.fg    = ${hex c.errorBright}
    statusline_error.bold  = true

    statusline_success.fg  = ${hex c.success}

    completion_default.fg       = ${hex c.fg1}
    completion_default.bg       = ${hex c.bg2}
    completion_description.fg   = ${hex c.fg3}
    completion_description.dim  = true
    completion_gutter.bg        = ${hex c.bg3}
    completion_pill.fg          = ${hex c.fg0}
    completion_pill.bg          = ${hex c.bg3}

    # ──────────────────────────────────────────────────────────────
    # [viewer] – used by built-in colorize filter
    # ──────────────────────────────────────────────────────────────

    [viewer]

    url.fg        = ${hex c.link}
    url.underline = true

    header.fg     = ${hex c.accent}
    header.bold   = true

    signature.fg  = ${hex c.fg3}
    signature.dim = true

    diff_meta.fg       = ${hex c.info}
    diff_meta.bold     = true

    diff_chunk.fg      = ${hex c.accent}
    diff_chunk_func.fg = ${hex c.accentAlt}
    diff_chunk_func.dim = true

    diff_add.fg        = ${hex c.successBright}
    diff_del.fg        = ${hex c.errorBright}

    quote_1.fg = ${hex c.success}
    quote_2.fg = ${hex c.info}
    quote_3.fg = ${hex c.accent}
    quote_3.dim = true
    quote_4.fg = ${hex c.warning}
    quote_4.dim = true
    quote_x.fg  = ${hex c.error}
    quote_x.dim = true

    # ──────────────────────────────────────────────────────────────
    # [user] – for .StyleMap in column-tags template
    # ──────────────────────────────────────────────────────────────

    [user]

    finance.fg     = ${hex c.success}
    bank.fg        = ${hex c.successBright}
    insurance.fg   = ${hex c.successDim}
    work.fg        = ${hex c.warning}
    coaching.fg    = ${hex c.warningBright}
    hwcmt.fg       = ${hex c.warning}
    personal.fg    = ${hex c.accentAlt}
    tech.fg        = ${hex c.accent}
    hide.fg        = ${hex c.fg3}
    action.fg      = ${hex c.marked}
    action.bg      = ${hex c.bg2}
    action.bold    = true
    starred.fg     = ${hex c.errorBright}
    starred.bold   = true
  '';
}
