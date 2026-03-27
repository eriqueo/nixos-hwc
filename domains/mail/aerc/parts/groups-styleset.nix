# hwc-groups styleset — dead-simple, group-colored aerc theme
# Uses hwc palette colors. Tag groups get one color each, that's it.
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
''
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

*.selected.reverse  = toggle
*.selected.bold     = true

# msglist_* — NO .fg on any of these so [user] tag colors come through
msglist_unread.bold         = true
msglist_read.dim            = true
msglist_deleted.dim         = true
msglist_marked.underline    = true
msglist_result.bold         = true
msglist_thread_folded.bold  = true
msglist_thread_context.dim  = true

dirlist_default.fg  = ${h (c.fg2 or "a7aaad")}
dirlist_unread.fg   = ${fg0}
dirlist_unread.bold = true
dirlist_recent.fg   = ${sel}

statusline_default.fg  = ${fg}
statusline_default.bg  = ${h (c.bg0 or "1d2021")}
statusline_error.fg    = ${h (c.errorBright or "d08080")}
statusline_error.bold  = true
statusline_success.fg  = ${h (c.success or "a3be8c")}

completion_default.fg  = ${fg}
completion_default.bg  = ${bg2}
completion_pill.fg     = ${fg0}
completion_pill.bg     = ${h (c.bg3 or "32373c")}

selector_default.bg    = ${bg}
selector_focused.bg    = ${h (c.bg3 or "32373c")}
selector_focused.fg    = ${fg0}

[viewer]
url.fg        = ${h (c.link or "0085ba")}
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
default.fg        = ${dim}
default.dim       = true
''
