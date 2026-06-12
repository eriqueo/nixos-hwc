# domains/home/apps/qutebrowser/parts/keybindings.nix
#
# Neovim-inspired keybindings with Space as leader — same grammar as
# yazi/parts/keymap.nix and todui. Qutebrowser's defaults are already
# vim-flavored (hjkl scroll, gg/G, f hints, o/O open, / search, J/K tabs);
# this layer adds the Space-leader menus and aligns delete with dd.
{ }:
''
  # ════════════════════════════════════════════════════════════════════
  # DELETE — dd closes tab (yazi: dd = delete); bare d unbound so a
  # stray keypress can't close a tab.
  # ════════════════════════════════════════════════════════════════════
  config.unbind('d')
  config.bind('dd', 'tab-close')

  # ════════════════════════════════════════════════════════════════════
  # <Space>t — TABS (matches yazi <Space>t)
  # ════════════════════════════════════════════════════════════════════
  config.bind('<Space>tn', 'cmd-set-text -s :open -t')
  config.bind('<Space>tc', 'tab-close')
  config.bind('<Space>to', 'tab-only')
  config.bind('<Space>tp', 'tab-pin')
  config.bind('<Space>tm', 'tab-mute')
  config.bind('<Space>tg', 'tab-give')
  config.bind('<Space>tt', 'cmd-set-text -s :tab-select')

  # <Space><Space> — fuzzy jump to an open tab (zoxide-jump parallel)
  config.bind('<Space><Space>', 'cmd-set-text -s :tab-select')

  # ════════════════════════════════════════════════════════════════════
  # <Space>y — YANK variants (matches yazi <Space>y)
  # ════════════════════════════════════════════════════════════════════
  config.bind('<Space>yy', 'yank')
  config.bind('<Space>yt', 'yank title')
  config.bind('<Space>yd', 'yank domain')
  config.bind('<Space>ym', 'yank inline [{title}]({url})')
  config.bind('<Space>ys', 'yank selection')

  # ════════════════════════════════════════════════════════════════════
  # <Space>f — FIND / OPEN
  # ════════════════════════════════════════════════════════════════════
  config.bind('<Space>f', 'cmd-set-text -s :open')
  config.bind('<Space>/', 'cmd-set-text /')

  # ════════════════════════════════════════════════════════════════════
  # <Space>m — MEDIA: hand the page (or a hinted link) to mpv
  # ════════════════════════════════════════════════════════════════════
  config.bind('<Space>m', 'spawn mpv {url}')
  config.bind('<Space>M', 'hint links spawn mpv {hint-url}')

  # ════════════════════════════════════════════════════════════════════
  # <Space> misc
  # ════════════════════════════════════════════════════════════════════
  config.bind('<Space>p', 'open -p')        # private window
  config.bind('<Space>e', 'edit-url')       # edit current URL in nvim
  config.bind('<Space>b', 'cmd-set-text -s :quickmark-load -t')
  config.bind('<Space>h', 'history')        # browsing history page
  config.bind('<Space>?', 'help')

  # ════════════════════════════════════════════════════════════════════
  # Defaults kept on purpose (cheat-sheet, not bindings):
  #   hjkl scroll · gg/G top/bottom · <C-d>/<C-u> half page
  #   o/O open url (tab) · f/F follow link (tab) · H/L back/forward
  #   J/K next/prev tab · g0/g$ first/last tab · u undo closed tab
  #   m quickmark-save · b quickmark-open · / search, n/N
  #   i insert mode · v caret mode · r/R reload · q/@ record/run macro
  # ════════════════════════════════════════════════════════════════════
''
