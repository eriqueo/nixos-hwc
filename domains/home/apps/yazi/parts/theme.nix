# domains/home/apps/yazi/parts/theme.nix
{
  # Main theme file with Kanagawa color palette
  "yazi/theme.toml" = {
    text = ''
      # Kanagawa theme for Yazi
      # Color palette based on rebelot/kanagawa.nvim
      
      [mgr]
      marker_copied = { fg = "#98bb6c", bg = "#98bb6c" }
      marker_cut = { fg = "#e46876", bg = "#e46876" }
      marker_marked = { fg = "#957fb8", bg = "#957fb8" }
      marker_selected = { fg = "#ffa066", bg = "#ffa066" }

      cwd = { fg = "#e6c384" }
      hovered = { reversed = true }
      preview_hovered = { reversed = true }

      find_keyword = { fg = "#ffa066", bg = "#1f1f28" }
      find_position = {}

      count_copied = { fg = "#1f1f28", bg = "#98bb6c" }
      count_cut = { fg = "#1f1f28", bg = "#e46876" }
      count_selected = { fg = "#1f1f28", bg = "#ffa066" }

      border_symbol = "│"
      border_style = { fg = "#dcd7ba" }

      [tabs]
      active = { fg = "#1f1f28", bg = "#7e9cd8" }
      inactive = { fg = "#7e9cd8", bg = "#2a2a37" }

      [mode]
      normal_main = { fg = "#1f1f28", bg = "#7e9cd8" }
      select_main = { fg = "#1f1f28", bg = "#957fb8" }
      unset_main = { fg = "#1f1f28", bg = "#e6c384" }

      [status]
      overall = { fg = "#c8c093", bg = "#16161d" }
      perm_type = { fg = "#98bb6c" }
      perm_read = { fg = "#e6c384" }
      perm_write = { fg = "#ff5d62" }
      perm_exec = { fg = "#7aa89f" }
      perm_sep = { fg = "#957fb8" }

      [filetype]
      rules = [
        { mime = "image/*", fg = "#e6c384" },
        { mime = "{audio,video}/*", fg = "#957fb8" },
        { mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "#e46876" },
        { mime = "application/{pdf,doc,rtf,vnd.*}", fg = "#6a9589" },
        { name = "*.nix", fg = "#7e9cd8" },
        { name = "*.{py,js,json,toml,yaml,yml}", fg = "#e6c384" },
        { name = "*.rs", fg = "#ffa066" },
        { name = "*.ts", fg = "#7e9cd8" },
        { name = "*.md", fg = "#98bb6c" },
        { name = "*.lua", fg = "#7e9cd8" },
        { name = "*.sh", fg = "#98bb6c" },
        { name = "*.{c,cpp,h,go}", fg = "#7aa89f" },
        { name = "*", is = "orphan", fg = "#c34043" },
        { name = "*", is = "exec", fg = "#76946a" },
        { name = "*/", fg = "#7e9cd8" },
        { name = "*", fg = "#dcd7ba" },
      ]
    '';
  };

  # Kanagawa tmTheme for syntax highlighting in previews
  "yazi/Kanagawa.tmTheme" = {
    text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>name</key>
          <string>Kanagawa</string>
          <key>settings</key>
          <array>
            <dict>
              <key>settings</key>
              <dict>
                <key>background</key>
                <string>#1F1F28</string>
                <key>caret</key>
                <string>#C8C093</string>
                <key>foreground</key>
                <string>#DCD7BA</string>
                <key>invisibles</key>
                <string>#54546D</string>
                <key>lineHighlight</key>
                <string>#2D4F67</string>
                <key>selection</key>
                <string>#2D4F67</string>
              </dict>
            </dict>
            <dict>
              <key>name</key><string>Comment</string>
              <key>scope</key><string>comment</string>
              <key>settings</key><dict><key>foreground</key><string>#727169</string></dict>
            </dict>
            <dict>
              <key>name</key><string>String</string>
              <key>scope</key><string>string</string>
              <key>settings</key><dict><key>foreground</key><string>#98BB6C</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Number</string>
              <key>scope</key><string>constant.numeric</string>
              <key>settings</key><dict><key>foreground</key><string>#D27E99</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Built-in constant</string>
              <key>scope</key><string>constant.language</string>
              <key>settings</key><dict><key>foreground</key><string>#FFA066</string></dict>
            </dict>
            <dict>
              <key>name</key><string>User-defined constant</string>
              <key>scope</key><string>constant.character, constant.other</string>
              <key>settings</key><dict><key>foreground</key><string>#E6C384</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Keyword</string>
              <key>scope</key><string>keyword</string>
              <key>settings</key><dict><key>foreground</key><string>#E46876</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Storage</string>
              <key>scope</key><string>storage</string>
              <key>settings</key><dict><key>foreground</key><string>#957FB8</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Function name</string>
              <key>scope</key><string>entity.name.function</string>
              <key>settings</key><dict><key>foreground</key><string>#7E9CD8</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Class name</string>
              <key>scope</key><string>entity.name.class</string>
              <key>settings</key><dict><key>foreground</key><string>#7AA89F</string></dict>
            </dict>
            <dict>
              <key>name</key><string>Invalid</string>
              <key>scope</key><string>invalid</string>
              <key>settings</key><dict><key>foreground</key><string>#FF5D62</string></dict>
            </dict>
          </array>
        </dict>
      </plist>
    '';
  };
}
