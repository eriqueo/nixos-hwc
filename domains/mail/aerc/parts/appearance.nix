# domains/mail/aerc/parts/appearance.nix
# Pure function: palette colors → aerc styleset content.
#
# KEY RULE from aerc-stylesets(7):
#   "[user] style colors (fg/bg) will only be effective if the context
#    style does not define any."
# So msglist_* styles must NOT set .fg, or they'll block [user] tag colors.
# Use only bold/dim for message state differentiation.
{ lib, colors, tags }:

let
  c = colors;
  h = color: "#${color}";

  bg   = h (c.bg1 or "23282d");
  bg2  = h (c.bg2 or "2c3338");
  fg   = h (c.fg1 or "d5c4a1");
  fg0  = h (c.fg0 or "ebdbb2");
  dim  = h (c.fg3 or "50626f");
  sel  = h (c.accent or "d08770");
in
{
  stylesetContent = ''
*.default = true
*.normal  = true

# Force gruvbox dark bg everywhere — aerc defaults to palette 12 (blue) otherwise
*.bg                = ${bg}
border.bg           = ${bg}
title.bg            = ${bg2}
stack.bg            = ${bg}

error.fg            = ${h (c.error or "bf616a")}
error.bold          = true
warning.fg          = ${h (c.warning or "cf995f")}
warning.bold        = true
success.fg          = ${h (c.success or "a3be8c")}
success.bold        = true

title.fg            = ${fg0}
title.bg            = ${h (c.bg3 or "32373c")}
title.bold          = true

header.fg           = ${sel}
header.bold         = true

tab.fg              = ${h (c.fg2 or "a7aaad")}
tab.bg              = ${h (c.bg3 or "32373c")}

border.fg           = ${h (c.bg3 or "32373c")}

spinner.fg          = ${sel}

*.selected.fg       = ${h (c.bg0 or "1d2021")}
*.selected.bg       = ${h (c.fg2 or "a7aaad")}
*.selected.bold     = true

# msglist_* — NO .fg on any of these so [user] tag colors come through
msglist_unread.bold         = true
msglist_read.dim            = true
msglist_deleted.dim         = true
# Marked (bulk-select) rows: reverse video = a clear highlighter bar,
# inverting bg/fg per row (was a too-subtle bold+italic).
msglist_marked.reverse      = true
msglist_marked.bold         = true
msglist_result.bold         = true
msglist_thread_folded.bold  = true
msglist_thread_context.dim  = true
# Column-header row (forked aerc index-headers). fg+bg are set deliberately —
# the "no .fg" rule above only matters for message rows (so tag colors show);
# the header isn't a message, so give it a solid accent bar to read as a header.
msglist_header.fg           = ${bg}
msglist_header.bg           = ${sel}
msglist_header.bold         = true

# dirlist_* — NO .fg so [user] tag colors come through (same rule as msglist)
dirlist_unread.bold = true
dirlist_recent.bold = true

statusline_default.fg  = ${fg}
statusline_default.bg  = ${h (c.bg0 or "1d2021")}
statusline_error.fg    = ${h (c.errorBright or "d08080")}
statusline_error.bold  = true
statusline_success.fg  = ${h (c.success or "a3be8c")}

completion_default.fg  = ${fg}
completion_default.bg  = ${bg2}
completion_pill.fg     = ${fg0}
completion_pill.bg     = ${h (c.bg3 or "32373c")}

# which-key popover (forked aerc): a RAISED slate card — bg is LIGHTER than the
# terminal bg (bg3 vs bg1) so it visibly floats above the message list — with a
# copper border and an inverted cream title chip for a strong header accent.
# bg is set on every object so the lighter panel doesn't bleed to terminal bg
# under the text/border. Keys = copper, group keys = cool accent.
whichkey_default.bg    = ${h (c.bg3 or "32373c")}
whichkey_default.fg    = ${fg0}
whichkey_key.bg        = ${h (c.bg3 or "32373c")}
whichkey_key.fg        = ${sel}
whichkey_key.bold      = true
whichkey_group.bg      = ${h (c.bg3 or "32373c")}
whichkey_group.fg      = ${h (c.info or "83a598")}
whichkey_group.bold    = true
whichkey_border.bg     = ${h (c.bg3 or "32373c")}
whichkey_border.fg     = ${sel}
whichkey_title.bg      = ${fg0}
whichkey_title.fg      = ${h (c.bg0 or "1d2021")}
whichkey_title.bold    = true

selector_default.bg    = ${bg}
selector_focused.bg    = ${h (c.bg3 or "32373c")}
selector_focused.fg    = ${fg0}

[viewer]
url.fg        = ${h (c.link or "5e81ac")}
url.underline = true
header.fg     = ${sel}
header.bold   = true
signature.fg  = ${dim}
signature.dim = true
diff_add.fg   = ${h (c.successBright or "b4c89a")}
diff_del.fg   = ${h (c.errorBright or "d08080")}
quote_1.fg    = ${h (c.success or "a3be8c")}
quote_2.fg    = ${h (c.info or "5e81ac")}
quote_3.fg    = ${sel}
quote_x.fg    = ${dim}

[user]
${tags.tagStyleLines}
hide.fg           = ${dim}
starred.fg        = ${h (c.errorBright or "d08080")}
starred.bold      = true

# Scoped views (sidebar)
focus.fg          = ${fg0}
focus.bold        = true
today.fg          = ${fg}
week.fg           = ${fg}
people.fg         = ${h (c.warningBright or "fcbb74")}
action.fg         = ${h (c.error or "bf616a")}
action.bold       = true
family.fg         = ${h (c.warningBright or "fcbb74")}
keep.fg           = ${h (c.success or "a3be8c")}

# Family aggregate groups (each its family colour)
business.fg       = ${h (c.accent or "d08770")}
business.bold     = true
money.fg          = ${h (c.info or "5e81ac")}
money.bold        = true
growth.fg         = ${h (c.success or "a3be8c")}
growth.bold       = true
system.fg         = ${h (c.fg2 or "a7aaad")}
all.fg            = ${fg}
newsletters.fg    = ${dim}
notifications.fg  = ${dim}

important.fg      = ${sel}
important.bold    = true
inbox_i.fg        = ${fg0}
inbox_i.bold      = true
unread_u.fg       = ${fg0}
unread_u.bold     = true
sent_s.fg         = ${dim}
drafts.fg         = ${dim}
Archive_a.fg      = ${dim}
trash_d.fg        = ${dim}
spam_z.fg         = ${dim}
hide_my_email.fg  = ${dim}
# Readable default — was dim slate (fg3), the main 'unreadable rows' bug.
default.fg        = ${fg}
  '';
}
