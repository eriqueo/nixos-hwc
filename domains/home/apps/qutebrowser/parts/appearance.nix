# domains/home/apps/qutebrowser/parts/appearance.nix
#
# Maps hwc.home.theme palette tokens onto qutebrowser's color settings
# (tabs, statusbar, completion, hints, messages, prompts, downloads).
# Pure function — guarded token reads with hwc-palette fallbacks so the
# module evaluates even when the theme surface is absent.
{ lib, colors, monoFont }:
let
  bg0     = colors.bg0 or "1d2021";
  bg1     = colors.bg1 or "282828";
  bg2     = colors.bg2 or "2c3338";
  bg3     = colors.bg3 or "32373c";
  fg0     = colors.fg0 or "ebdbb2";
  fg1     = colors.fg1 or "d5c4a1";
  fg2     = colors.fg2 or "a7aaad";
  fg3     = colors.fg3 or "50626f";
  accent  = colors.accent or "d08770";
  warning = colors.warning or "cf995f";
  error   = colors.error or "bf616a";
  success = colors.success or "a3be8c";
  info    = colors.info or "5e81ac";
  selBg   = colors.selectionBg or "434c5e";
  selFg   = colors.selectionFg or "ebdbb2";
  c = hex: "'#${hex}'";
in
''
  # ── Fonts ────────────────────────────────────────────────────────────
  c.fonts.default_family = '${monoFont}'
  c.fonts.default_size = '11pt'
  c.fonts.web.family.fixed = '${monoFont}'

  # ── Webpage dark mode ────────────────────────────────────────────────
  c.colors.webpage.preferred_color_scheme = 'dark'
  c.colors.webpage.darkmode.enabled = True
  c.colors.webpage.darkmode.algorithm = 'lightness-cielab'
  c.colors.webpage.bg = ${c bg1}

  # ── Tabs ─────────────────────────────────────────────────────────────
  c.colors.tabs.bar.bg = ${c bg0}
  c.colors.tabs.even.bg = ${c bg2}
  c.colors.tabs.even.fg = ${c fg2}
  c.colors.tabs.odd.bg = ${c bg2}
  c.colors.tabs.odd.fg = ${c fg2}
  c.colors.tabs.selected.even.bg = ${c bg1}
  c.colors.tabs.selected.even.fg = ${c fg0}
  c.colors.tabs.selected.odd.bg = ${c bg1}
  c.colors.tabs.selected.odd.fg = ${c fg0}
  c.colors.tabs.pinned.even.bg = ${c bg3}
  c.colors.tabs.pinned.even.fg = ${c fg1}
  c.colors.tabs.pinned.odd.bg = ${c bg3}
  c.colors.tabs.pinned.odd.fg = ${c fg1}
  c.colors.tabs.pinned.selected.even.bg = ${c bg1}
  c.colors.tabs.pinned.selected.even.fg = ${c fg0}
  c.colors.tabs.pinned.selected.odd.bg = ${c bg1}
  c.colors.tabs.pinned.selected.odd.fg = ${c fg0}
  c.colors.tabs.indicator.start = ${c info}
  c.colors.tabs.indicator.stop = ${c success}
  c.colors.tabs.indicator.error = ${c error}

  # ── Statusbar ────────────────────────────────────────────────────────
  c.colors.statusbar.normal.bg = ${c bg0}
  c.colors.statusbar.normal.fg = ${c fg1}
  c.colors.statusbar.insert.bg = ${c success}
  c.colors.statusbar.insert.fg = ${c bg0}
  c.colors.statusbar.command.bg = ${c bg1}
  c.colors.statusbar.command.fg = ${c fg0}
  c.colors.statusbar.caret.bg = ${c info}
  c.colors.statusbar.caret.fg = ${c bg0}
  c.colors.statusbar.caret.selection.bg = ${c selBg}
  c.colors.statusbar.caret.selection.fg = ${c selFg}
  c.colors.statusbar.passthrough.bg = ${c warning}
  c.colors.statusbar.passthrough.fg = ${c bg0}
  c.colors.statusbar.private.bg = ${c bg3}
  c.colors.statusbar.private.fg = ${c fg1}
  c.colors.statusbar.url.fg = ${c fg1}
  c.colors.statusbar.url.success.https.fg = ${c success}
  c.colors.statusbar.url.success.http.fg = ${c warning}
  c.colors.statusbar.url.error.fg = ${c error}
  c.colors.statusbar.url.warn.fg = ${c warning}
  c.colors.statusbar.url.hover.fg = ${c accent}
  c.colors.statusbar.progress.bg = ${c accent}

  # ── Completion (the :open / :tab-select menu) ────────────────────────
  c.colors.completion.fg = ${c fg1}
  c.colors.completion.odd.bg = ${c bg1}
  c.colors.completion.even.bg = ${c bg1}
  c.colors.completion.category.bg = ${c bg0}
  c.colors.completion.category.fg = ${c accent}
  c.colors.completion.category.border.top = ${c bg0}
  c.colors.completion.category.border.bottom = ${c bg0}
  c.colors.completion.item.selected.bg = ${c selBg}
  c.colors.completion.item.selected.fg = ${c selFg}
  c.colors.completion.item.selected.border.top = ${c selBg}
  c.colors.completion.item.selected.border.bottom = ${c selBg}
  c.colors.completion.item.selected.match.fg = ${c warning}
  c.colors.completion.match.fg = ${c warning}
  c.colors.completion.scrollbar.bg = ${c bg1}
  c.colors.completion.scrollbar.fg = ${c bg3}

  # ── Hints (f follow-link overlays) ───────────────────────────────────
  c.colors.hints.bg = ${c warning}
  c.colors.hints.fg = ${c bg0}
  c.colors.hints.match.fg = ${c fg3}
  c.hints.border = '1px solid #${bg0}'

  # ── Keyhint popup (pending-key helper, e.g. after <Space>) ──────────
  c.colors.keyhint.bg = ${c bg0}
  c.colors.keyhint.fg = ${c fg1}
  c.colors.keyhint.suffix.fg = ${c warning}

  # ── Messages ─────────────────────────────────────────────────────────
  c.colors.messages.error.bg = ${c error}
  c.colors.messages.error.fg = ${c fg0}
  c.colors.messages.error.border = ${c error}
  c.colors.messages.warning.bg = ${c warning}
  c.colors.messages.warning.fg = ${c bg0}
  c.colors.messages.warning.border = ${c warning}
  c.colors.messages.info.bg = ${c bg2}
  c.colors.messages.info.fg = ${c fg1}
  c.colors.messages.info.border = ${c bg2}

  # ── Prompts & downloads ──────────────────────────────────────────────
  c.colors.prompts.bg = ${c bg2}
  c.colors.prompts.fg = ${c fg1}
  c.colors.prompts.border = '1px solid #${bg3}'
  c.colors.prompts.selected.bg = ${c selBg}
  c.colors.prompts.selected.fg = ${c selFg}
  c.colors.downloads.bar.bg = ${c bg0}
  c.colors.downloads.start.bg = ${c info}
  c.colors.downloads.start.fg = ${c bg0}
  c.colors.downloads.stop.bg = ${c success}
  c.colors.downloads.stop.fg = ${c bg0}
  c.colors.downloads.error.bg = ${c error}
  c.colors.downloads.error.fg = ${c fg0}

  # ── Context menu ─────────────────────────────────────────────────────
  c.colors.contextmenu.menu.bg = ${c bg1}
  c.colors.contextmenu.menu.fg = ${c fg1}
  c.colors.contextmenu.selected.bg = ${c selBg}
  c.colors.contextmenu.selected.fg = ${c selFg}
  c.colors.contextmenu.disabled.bg = ${c bg1}
  c.colors.contextmenu.disabled.fg = ${c fg3}
''
