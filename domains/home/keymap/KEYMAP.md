<!-- generated — do not edit; run `nix run .#keymap-docs` -->
# Unified keymap

Space acts inside the focused app. Ctrl Space opens the inter-app layer. Rows and groups are sorted by chord/letter.

## Groups

| Letter | Meaning |
| --- | --- |
| ? | help |
| a | agent |
| b | buffer |
| c | compose |
| d | delete |
| f | find |
| g | go |
| l | language |
| m | mark |
| o | open |
| p | project |
| q | quit |
| s | sort |
| t | toggle |
| v | version |
| w | window |
| y | yank |

## khalt

| Chord | Description |
| --- | --- |
| Space ? | ? |
| Space c c | new |
| Space c d | duplicate |
| Space d d | delete |
| Space f f | search |
| Space g o | other |
| Space g t | today |
| Space o E | external edit |
| Space o e | view |
| Space o x | export |
| Space q r | reload |
| Space t v | mark |
| Space w a | view agenda |
| Space w m | view month |
| Space w q | view quarter |
| Space w z | cycle view |

### Bare aliases

| Key | Description |
| --- | --- |
| a | new |
| d | delete |
| enter | view |

## nvim

| Chord | Description |
| --- | --- |
| Space a A | Agent: ClaudeCodeDiffAccept |
| Space a a | Agent: ClaudeCode |
| Space a b | Agent: ClaudeCodeAdd % |
| Space a d | Agent: ClaudeCodeDiffDeny |
| Space a f | Agent: ClaudeCodeFocus |
| Space a r | Agent: ClaudeCode --resume |
| Space a s | Agent: ClaudeCodeSend |
| Space b 1 | Tab: 1 |
| Space b 2 | Tab: 2 |
| Space b 3 | Tab: 3 |
| Space b 4 | Tab: 4 |
| Space b a | Buffer: delete all others |
| Space b b | List buffers/tabs |
| Space b d | Buffer: delete |
| Space b f | Buffer: first |
| Space b l | Buffer: last |
| Space b n | Next |
| Space b p | Previous |
| Space b t | Tab: new |
| Space b x | Tab: close |
| Space c r | Replace: word under cursor |
| Space d b | Delete: buffer |
| Space d d | Delete: to black hole |
| Space d w | Delete: trailing whitespace |
| Space d x | Cut: to system clipboard |
| Space f R | Search: resume |
| Space f b | Find: buffers |
| Space f c | Find: commands |
| Space f f | Find file |
| Space f g | Grep / search content |
| Space f h | Find: help |
| Space f k | Find: keymaps |
| Space f n | Find: nixos files |
| Space f r | Recent files |
| Space f s | Find: neovim config |
| Space f t | Find TODOs |
| Space g 1 | Harpoon file 1 |
| Space g 2 | Harpoon file 2 |
| Space g 3 | Harpoon file 3 |
| Space g 4 | Harpoon file 4 |
| Space g c | Config (~/.config) |
| Space g d | Downloads |
| Space g h | Home |
| Space g n | NixOS config |
| Space g o | Go: documents |
| Space g r | Go: root |
| Space l D | Language: definition |
| Space l L | Trouble: lsp toggle focus=false win.position=right |
| Space l R | Language: references |
| Space l S | Trouble: symbols toggle focus=false |
| Space l X | Trouble: diagnostics toggle filter.buf=0 |
| Space l a | Language: code action |
| Space l d | Diagnostics |
| Space l f | Format |
| Space l l | Trouble: loclist toggle |
| Space l q | Trouble: qflist toggle |
| Space l r | Language: rename |
| Space l s | Language: workspace symbols |
| Space l x | Trouble: diagnostics toggle |
| Space m h | Mark: harpoon add |
| Space o c | Open: config dir |
| Space o h | Open: home dir |
| Space o n | Open: nixos config |
| Space o t | Tuxedo |
| Space o v | Open: file explorer (Oil) |
| Space p l | Session: load |
| Space p s | Session: save |
| Space t a | Select: all |
| Space t h | Toggle: highlight search |
| Space t m | Toggle harpoon menu |
| Space t n | Toggle: line numbers |
| Space t r | Toggle: relative numbers |
| Space t s | Toggle: spell check |
| Space t w | Toggle: wrap |
| Space v B | Git: full blame |
| Space v b | Git: blame line |
| Space v d | Git: diff |
| Space v p | Git: preview hunk |
| Space v r | Git: reset hunk |
| Space v s | Git: stage hunk |
| Space v t | Git: toggle line blame |
| Space v u | Git: undo stage hunk |
| Space w + | Window: increase height |
| Space w - | Window: decrease height |
| Space w < | Window: decrease width |
| Space w = | Window: equal size |
| Space w > | Window: increase width |
| Space w o | Window: close others |
| Space w q | Window: close |
| Space w s | Window: horizontal split |
| Space w v | Window: vertical split |
| Space y P | Paste: from system clipboard |
| Space y a | Yank: entire buffer to system clipboard |
| Space y c | Yank: to system clipboard |
| Space y d | Yank: directory |
| Space y n | Yank: filename |
| Space y p | Yank: file path |
| Space y y | Yank: line to clipboard |

### Bare aliases

No bare aliases declared in the grammar; native app keys remain unchanged.

## todui

| Chord | Description |
| --- | --- |
| Space b l | lists menu |
| Space b n | next list |
| Space b p | previous list |
| Space c c | add |
| Space d d | delete |
| Space m j | set project |
| Space m k | set context |
| Space m l | move list |
| Space m p | set priority |
| Space m u | set due |
| Space m x | toggle done |
| Space o e | edit |
| Space q r | reload |
| Space q s | sync |
| Space s c | sort created |
| Space s d | sort due |
| Space s p | sort priority |
| Space t c | toggle completed |
| Space w w | toggle week |

### Bare aliases

| Key | Description |
| --- | --- |
| a | add |
| d | delete |
| e | edit |
| enter | edit |

## yazi

| Chord | Description |
| --- | --- |
| Space b 1 | Tab: 1 |
| Space b 2 | Tab: 2 |
| Space b 3 | Tab: 3 |
| Space b 4 | Tab: 4 |
| Space b c | Tab: close |
| Space b j | Next tab |
| Space b k | Prev tab |
| Space b n | Tab: new |
| Space b o | Tab: close others |
| Space c L | Relative symlink |
| Space c R | Rename (full) |
| Space c d | Create directory |
| Space c f | Create file/dir |
| Space c h | Hardlink |
| Space c l | Symlink |
| Space c r | Rename |
| Space d D | Delete permanently |
| Space d d | Delete (to trash) / remove favorite |
| Space f f | Find file |
| Space f g | Grep / search content |
| Space f l | Filter |
| Space g 0 | Go: inbox |
| Space g 1 | Go: work |
| Space g 2 | Go: personal |
| Space g 3 | Go: tech |
| Space g 5 | Go: media |
| Space g 9 | Go: vaults |
| Space g D | Half page down |
| Space g F | Page down |
| Space g G | Go to bottom |
| Space g M | Go: music |
| Space g N | Next favorite |
| Space g P | Previous favorite |
| Space g T | Go: trash |
| Space g U | Page up |
| Space g Z | FZF jump |
| Space g b | Go back/parent |
| Space g c | Config (~/.config) |
| Space g d | Downloads |
| Space g e | Enter/Open |
| Space g f | Go: favorites |
| Space g g | Go to top |
| Space g h | Home |
| Space g j | Move down |
| Space g k | Move up |
| Space g l | Focus files |
| Space g m | Go: media mount |
| Space g n | NixOS config |
| Space g p | Go: pictures |
| Space g t | Go: tmp |
| Space g u | Half page up |
| Space g v | Go: videos |
| Space g z | Zoxide jump |
| Space m f | Favorite: add current folder |
| Space m p | Change permissions |
| Space o O | Open with |
| Space o S | Shell command |
| Space o o | Open |
| Space o s | Shell command |
| Space q c | Cancel/Clear |
| Space q q | Quit |
| Space s a | Sort: alphabetical |
| Space s c | Sort: created |
| Space s e | Sort: extension |
| Space s m | Sort: modified |
| Space s n | Sort: natural |
| Space s r | Sort: reverse |
| Space s s | Sort: size |
| Space t A | Toggle all |
| Space t a | Select all |
| Space t c | Clear selection |
| Space t h | Toggle hidden |
| Space t j | Select & down |
| Space t k | Up & select |
| Space t s | Toggle select |
| Space w c | View: created time |
| Space w h | Help |
| Space w i | Inspect |
| Space w j | Preview: down |
| Space w k | Preview: up |
| Space w m | View: modified time |
| Space w n | View: clean |
| Space w p | View: permissions |
| Space w s | View: sizes |
| Space y V | Paste into hovered dir |
| Space y d | Copy: directory |
| Space y n | Copy: filename |
| Space y p | Copy: full path |
| Space y v | Paste here |
| Space y x | Cut |
| Space y y | Yank (copy) |

### Bare aliases

No bare aliases declared in the grammar; native app keys remain unchanged.

## aerc

| Chord | Description | Scope |
| --- | --- | --- |
| Space ? | Binding sheet | global |
| Space b c | Close tab | closable |
| Space b n | Next tab | global |
| Space b p | Previous tab | global |
| Space c a | Reply all | message |
| Space c c | Compose | account |
| Space c f | Forward | message |
| Space c r | Reply | message |
| Space d d | Trash (record outcome) | message |
| Space f T | Search all mail by tag… | account |
| Space f a | Search all mail by words… | account |
| Space f c | Clear filter/search | account |
| Space f d | Filter by Domain… | account |
| Space f f | Filter folder by words… | account |
| Space f s | Jump to matching words… | account |
| Space f t | Filter folder by tag… | account |
| Space g A | All mail | account |
| Space g B | Backlog | account |
| Space g I | Raw inbox | account |
| Space g T | Trash | account |
| Space g _ | Hide-my-email | account |
| Space g a | Archive | account |
| Space g b | Bulk | account |
| Space g d | DID | account |
| Space g i | DO | account |
| Space g j | JUNK | account |
| Space g k | DONT KNOW | account |
| Space g l | LOOK | account |
| Space g s | Sent | account |
| Space g u | Unread | account |
| Space g z | Spam | account |
| Space m a | Archive (record outcome) | message |
| Space m d | Set Domain… | message |
| Space m j | Mark and move down | message |
| Space m k | Mark and move up | message |
| Space m l | Routing rules… | message |
| Space m s | Set State… | message |
| Space m t | Optional tags… | message |
| Space m u | Review unsubscribe | message |
| Space m v | Read/unread… | message |
| Space m x | Move to folder… (no learning) | message |
| Space o c | Import calendar event (no RSVP) | message |
| Space o l | URL picker | message |
| Space o p | Paperless handoff | message |
| Space o t | Task handoff | message |
| Space q q | Confirm quit | global |
| Space q r | Reload configuration | global |
| Space q s | Sync mail | global |
| Space s a | Alphabetical subject A–Z | account |
| Space s d | Newest first | account |
| Space s f | Sender, then newest | account |
| Space s s | Subject, then newest | account |
| Space t a | Fold all threads | account |
| Space t h | Toggle headers | view |
| Space t t | Toggle selected fold | account |
| Space w i | Local image preview (remote images blocked) | view |
| Space w n | Next MIME part / attachment | view |
| Space w p | Previous MIME part / attachment | view |
| Space w s | Switch styleset… | global |
| Space y l | Copy URL via picker | message |
| Space y m | Copy to folder… | message |

### Bare aliases

| Key | Context | Description / action |
| --- | --- | --- |
| C | list | Reply all |
| R | view | Reply all |
| c | list | Compose |
| f | view | Forward |
| r | view | Reply |
| d | list | Trash (record outcome) |
| D | list | Trash (record outcome) |
| d | view | Trash (record outcome) |
| a | list | Archive (record outcome) |
| a | view | Archive (record outcome) |
| J | list | Mark and move down |
| K | list | Mark and move up |
| r | list | read |
| u | list | unread |
| X | list | Move to folder… (no learning) |
| u | view | URL picker |
| p | view | Paperless handoff |
| t | view | Task handoff |
| Y | list | Copy to folder… |

## Workbench globals

| Chord | Description |
| --- | --- |
| Space a a | Ask agent about item |
| Space a s | Send item to agent |

## Workbench Mail

Omitted rows are reference entries, not active bindings. Menu rows open choices supplied by the mail contract.

| Chord | Description | Realization |
| --- | --- | --- |
| Space ? | Binding sheet | omitted: aerc app control |
| Space b c | Close tab | omitted: Tabs belong to aerc |
| Space b n | Next tab | omitted: Tabs belong to aerc |
| Space b p | Previous tab | omitted: Tabs belong to aerc |
| Space c a | Reply all | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space c c | Compose | handoff: compose |
| Space c f | Forward | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space c r | Reply | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space d d | Trash (record outcome) | native verb: trash |
| Space f T | Search all mail by tag… | omitted: aerc list filtering and search |
| Space f a | Search all mail by words… | omitted: aerc list filtering and search |
| Space f c | Clear filter/search | omitted: aerc list filtering and search |
| Space f d | Filter by Domain… | omitted: aerc list filtering and search |
| Space f f | Filter folder by words… | omitted: aerc list filtering and search |
| Space f s | Jump to matching words… | omitted: aerc list filtering and search |
| Space f t | Filter folder by tag… | omitted: aerc list filtering and search |
| Space g A | All mail | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g B | Backlog | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g I | Raw inbox | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g T | Trash | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g _ | Hide-my-email | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g a | Archive | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g b | Bulk | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g d | DID | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g i | DO | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g j | JUNK | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g k | DONT KNOW | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g l | LOOK | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g s | Sent | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g u | Unread | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space g z | Spam | omitted: aerc folder navigation; Workbench Mail uses stages |
| Space m a | Archive (record outcome) | native verb: archive |
| Space m d | Set Domain… | menu: domain |
| Space m j | Mark and move down | omitted: aerc list selection and movement |
| Space m k | Mark and move up | omitted: aerc list selection and movement |
| Space m l | Routing rules… | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space m s | Set State… | menu: state |
| Space m t | Optional tags… | omitted: aerc fact/tag menus; Workbench item intents cannot supply a fact parameter or open a tag picker |
| Space m u | Review unsubscribe | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space m v | Read/unread… | menu: read-status |
| Space m x | Move to folder… (no learning) | omitted: aerc folder move; Workbench moves by state with m s |
| Space o c | Import calendar event (no RSVP) | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space o l | URL picker | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space o p | Paperless handoff | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space o t | Task handoff | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space q q | Confirm quit | omitted: aerc app control |
| Space q r | Reload configuration | omitted: aerc app control |
| Space q s | Sync mail | omitted: aerc app control |
| Space s a | Alphabetical subject A–Z | omitted: aerc list sorting |
| Space s d | Newest first | omitted: aerc list sorting |
| Space s f | Sender, then newest | omitted: aerc list sorting |
| Space s s | Subject, then newest | omitted: aerc list sorting |
| Space t a | Fold all threads | omitted: aerc thread folding |
| Space t h | Toggle headers | omitted: Raw headers belong to aerc viewer |
| Space t t | Toggle selected fold | omitted: aerc thread folding |
| Space w i | Local image preview (remote images blocked) | omitted: MIME image preview belongs to aerc viewer |
| Space w n | Next MIME part / attachment | omitted: MIME parts belong to aerc viewer |
| Space w p | Previous MIME part / attachment | omitted: MIME parts belong to aerc viewer |
| Space w s | Switch styleset… | omitted: Stylesets belong to aerc |
| Space y l | Copy URL via picker | omitted: No aerc thread-load completion or message-selection contract; action could target another message |
| Space y m | Copy to folder… | omitted: No aerc thread-load completion or message-selection contract; action could target another message |

### Bare aliases

| Key | Native verb |
| --- | --- |
| d | trash |
| D | trash |
| a | archive |
| r | mark-read |
| u | mark-unread |

## Accepted differences

Bare `a` adds in todui/khalt but archives in aerc/Workbench Mail. In the aerc viewer, bare `r` replies and bare `u` opens the URL picker; list aliases mark read/unread. Native keys absent from the grammar are not listed here.
