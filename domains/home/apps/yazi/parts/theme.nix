# domains/home/apps/yazi/parts/theme.nix
# Yazi theme adapter - Consumes config.hwc.home.theme.colors
# Generates comprehensive Yazi theme with all UI sections

{ config, ... }:

let
  # Consume global theme colors
  c = config.hwc.home.theme.colors or {};

  # Helper to format hex colors for Yazi
  hex = color: "#${color}";
in
{
  # Main theme file with comprehensive UI coverage
  "yazi/theme.toml" = {
    text = ''
      # Yazi Theme - Auto-generated from ${c.name or "unknown"} palette
      # Color palette tokens from domains/home/theme/palettes/

      [mgr]
      # File markers
      marker_copied = { fg = "${hex c.success}", bg = "${hex c.success}" }
      marker_cut = { fg = "${hex c.error}", bg = "${hex c.error}" }
      marker_marked = { fg = "${hex c.marked}", bg = "${hex c.marked}" }
      marker_selected = { fg = "${hex c.selection}", bg = "${hex c.selection}" }

      # Current working directory
      cwd = { fg = "${hex c.warning}" }

      # Hovered items
      hovered = { reversed = true }
      preview_hovered = { reversed = true }

      # Find/search
      find_keyword = { fg = "${hex c.warning}", bg = "${hex c.bg1}" }
      find_position = {}

      # Counters
      count_copied = { fg = "${hex c.bg1}", bg = "${hex c.success}" }
      count_cut = { fg = "${hex c.bg1}", bg = "${hex c.error}" }
      count_selected = { fg = "${hex c.bg1}", bg = "${hex c.selection}" }

      # Borders
      border_symbol = "│"
      border_style = { fg = "${hex c.border}" }

      [tabs]
      # Active tab
      active = { fg = "${hex c.bg1}", bg = "${hex c.accent}" }
      # Inactive tab
      inactive = { fg = "${hex c.accent}", bg = "${hex c.bg2}" }

      # Tab separators (using Unicode powerline symbols)
      sep_inner = { open = "", close = "" }
      sep_outer = { open = "", close = "" }

      [mode]
      # Normal mode
      normal_main = { fg = "${hex c.bg1}", bg = "${hex c.accent}" }
      normal_alt = { fg = "${hex c.accent}", bg = "${hex c.bg2}" }

      # Select mode
      select_main = { fg = "${hex c.bg1}", bg = "${hex c.marked}" }
      select_alt = { fg = "${hex c.marked}", bg = "${hex c.bg2}" }

      # Unset mode
      unset_main = { fg = "${hex c.bg1}", bg = "${hex c.warning}" }
      unset_alt = { fg = "${hex c.warning}", bg = "${hex c.bg2}" }

      [status]
      # Status bar separators
      sep_left = { open = "", close = "" }
      sep_right = { open = "", close = "" }

      # Overall status bar
      overall = { fg = "${hex c.fg2}", bg = "${hex c.bg0}" }

      # Progress indicators
      progress_label = { fg = "${hex c.accent}", bold = true }
      progress_normal = { fg = "${hex c.bg2}", bg = "${hex c.bg1}" }
      progress_error = { fg = "${hex c.bg2}", bg = "${hex c.bg1}" }

      # Permissions display
      perm_type = { fg = "${hex c.success}" }
      perm_read = { fg = "${hex c.warning}" }
      perm_write = { fg = "${hex c.error}" }
      perm_exec = { fg = "${hex c.info}" }
      perm_sep = { fg = "${hex c.marked}" }

      [pick]
      # File picker
      border = { fg = "${hex c.accent}" }
      active = { fg = "${hex c.marked}", bold = true }
      inactive = {}

      [input]
      # Input dialogs
      border = { fg = "${hex c.accent}" }
      title = {}
      value = {}
      selected = { reversed = true }

      [completion]
      # Command completion
      border = { fg = "${hex c.accent}" }
      active = { reversed = true }
      inactive = {}

      [tasks]
      # Background tasks
      border = { fg = "${hex c.accent}" }
      title = {}
      hovered = { fg = "${hex c.marked}" }

      [which]
      # Which-key style helper
      cols = 2
      separator = " - "
      separator_style = { fg = "${hex c.separator}" }
      mask = { bg = "${hex c.bg0}" }
      rest = { fg = "${hex c.fg3}" }
      cand = { fg = "${hex c.accent}" }
      desc = { fg = "${hex c.fg2}" }

      [help]
      # Help screen
      on = { fg = "${hex c.success}" }
      run = { fg = "${hex c.marked}" }
      desc = {}
      hovered = { reversed = true, bold = true }
      footer = { fg = "${hex c.bg1}", bg = "${hex c.fg0}" }

      [notify]
      # Notifications
      title_info = { fg = "${hex c.success}" }
      title_warn = { fg = "${hex c.warning}" }
      title_error = { fg = "${hex c.error}" }

      [filetype]
      # File type colorization rules
      rules = [
        # Images
        { mime = "image/*", fg = "${hex c.fileImage}" },

        # Media (audio/video)
        { mime = "{audio,video}/*", fg = "${hex c.fileMedia}" },

        # Archives
        { mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "${hex c.fileArchive}" },

        # Documents
        { mime = "application/{pdf,doc,rtf,vnd.*}", fg = "${hex c.fileDocument}" },

        # Code files (specific extensions)
        { name = "*.nix", fg = "${hex c.fileCode}" },
        { name = "*.{py,js,json,toml,yaml,yml}", fg = "${hex c.fileCode}" },
        { name = "*.rs", fg = "${hex c.fileCode}" },
        { name = "*.ts", fg = "${hex c.fileCode}" },
        { name = "*.md", fg = "${hex c.fileDocument}" },
        { name = "*.lua", fg = "${hex c.fileCode}" },
        { name = "*.sh", fg = "${hex c.fileExec}" },
        { name = "*.{c,cpp,h,go}", fg = "${hex c.fileCode}" },

        # Broken links
        { name = "*", is = "orphan", fg = "${hex c.fileOrphan}" },

        # Executables
        { name = "*", is = "exec", fg = "${hex c.fileExec}" },

        # Directories
        { name = "*/", fg = "${hex c.fileDir}" },

        # Fallback for regular files
        { name = "*", fg = "${hex c.fg1}" },
      ]
    '';
  };

  # Syntax highlighting theme for file previews
  "yazi/Kanagawa.tmTheme" = {
    text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>name</key>
          <string>${c.name or "Custom"} Theme</string>
          <key>settings</key>
          <array>
            <dict>
              <key>settings</key>
              <dict>
                <key>background</key>
                <string>${hex c.bg1}</string>
                <key>caret</key>
                <string>${hex c.caret}</string>
                <key>foreground</key>
                <string>${hex c.fg1}</string>
                <key>invisibles</key>
                <string>${hex c.fg3}</string>
                <key>lineHighlight</key>
                <string>${hex c.bg2}</string>
                <key>selection</key>
                <string>${hex c.selectionBg}</string>
              </dict>
            </dict>
            <dict>
              <key>name</key><string>Comment</string>
              <key>scope</key><string>comment</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.fg3}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>String</string>
              <key>scope</key><string>string</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.success}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Number</string>
              <key>scope</key><string>constant.numeric</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.marked}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Built-in constant</string>
              <key>scope</key><string>constant.language</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.warning}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>User-defined constant</string>
              <key>scope</key><string>constant.character, constant.other</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.warning}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Keyword</string>
              <key>scope</key><string>keyword</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.error}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Storage</string>
              <key>scope</key><string>storage</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.marked}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Function name</string>
              <key>scope</key><string>entity.name.function</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.accent}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Class name</string>
              <key>scope</key><string>entity.name.class</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.info}</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Invalid</string>
              <key>scope</key><string>invalid</string>
              <key>settings</key><dict><key>foreground</key><string>${hex c.errorBright}</string></dict>
            </dict>
          </array>
        </dict>
      </plist>
    '';
  };
}