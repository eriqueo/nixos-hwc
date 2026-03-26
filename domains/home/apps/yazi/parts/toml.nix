{
  "yazi/yazi.toml" = {
    text = ''
      [mgr]
      sort_by = "natural"
      sort_dir_first = true
      mouse_events = [ "click", "scroll" ]
      show_hidden = false
      show_symlink = true
      show_symlink_icon = true
      linemode = "btime"
      scrolloff = 5

      [preview]
      max_width = 600
      max_height = 900
      cache_dir = ""
      ueberzug_scale = 1
      ueberzug_offset = [ 0, 0, 0, 0 ]

      [opener]
      edit = [
        { run = 'nvim %s', block = true, for = "unix" }
      ]
      open = [ { run = 'xdg-open %s', orphan = true, desc = "Open" } ]
      office = [ { run = 'setsid onlyoffice-desktopeditors %s &>/dev/null &', orphan = true, desc = "OnlyOffice" } ]
      extract = [ { run = '7z x -y %s', desc = "Extract here (7z)", for = "unix" } ]

      [open]
      prepend_rules = [
        # Office by extension (more reliable than MIME detection)
        { url = "*.docx", use = ["office"] },
        { url = "*.doc", use = ["office"] },
        { url = "*.xlsx", use = ["office"] },
        { url = "*.xls", use = ["office"] },
        { url = "*.pptx", use = ["office"] },
        { url = "*.ppt", use = ["office"] },
        { url = "*.odt", use = ["office"] },
        { url = "*.ods", use = ["office"] },
        { url = "*.odp", use = ["office"] },
        # Archives
        { mime = "application/{zip,gzip,x-7z-compressed,x-xz,x-bzip*,x-rar,x-tar}", use = ["extract"] }
      ]
      rules = [
        { url = "*/", use = [ "open" ] },
        { mime = "text/*", use = [ "edit" ] },
        { mime = "video/*", use = [ "open" ] },
        { mime = "audio/*", use = [ "open" ] },
        { mime = "image/*", use = [ "open" ] },
        { mime = "application/pdf", use = [ "open" ] },
        # Office documents - OnlyOffice
        { mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document", use = [ "office" ] },
        { mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", use = [ "office" ] },
        { mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation", use = [ "office" ] },
        { mime = "application/msword", use = [ "office" ] },
        { mime = "application/vnd.ms-excel", use = [ "office" ] },
        { mime = "application/vnd.ms-powerpoint", use = [ "office" ] },
        { mime = "application/vnd.oasis.opendocument.text", use = [ "office" ] },
        { mime = "application/vnd.oasis.opendocument.spreadsheet", use = [ "office" ] },
        { mime = "application/vnd.oasis.opendocument.presentation", use = [ "office" ] }
      ]

      [plugin]
      previewers = [
        { url = "*/", run = "folder", sync = true },
        { url = "*.md", run = "glow" },
        { mime = "text/*", run = "code" },
        { mime = "*/xml", run = "code" },
        { mime = "*/javascript", run = "code" },
        { mime = "*/x-wine-extension-ini", run = "code" },
        { mime = "image/*", run = "image" },
        { mime = "video/*", run = "video" },
        { mime = "application/pdf", run = "pdf" },
        { mime = "application/json", run = "json" }
      ]

      tmtheme = "~/.config/yazi/Kanagawa.tmTheme"

      [which]
      cols = 2
      separator = " → "
      separator_style = { fg = "accent" }
      mask = { bg = "bg0" }
      rest = { fg = "fg3" }
      cand = { fg = "accent" }
      desc = { fg = "fg2" }
    '';
  };
}
