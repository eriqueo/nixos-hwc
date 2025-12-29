# domains/home/apps/yazi/parts/plugins.nix
{
  # Main init.lua to load all plugins
  "yazi/init.lua" = {
    text = ''
      require("full-border"):setup()
      require("bookmarks"):setup()
      require("glow")
      require("smart_filter")
      require("chmod")
    '';
  };

  # ========================================================================
  # CORRECTED: Renamed the plugin file from 'init.lua' to 'main.lua'
  # to match Yazi's expected plugin structure.
  # ========================================================================
  "yazi/plugins/full-border.yazi/main.lua" = {
    text = ''
      --- @since 25.2.26
      local function setup(_, opts)
        local type = opts and opts.type or ui.Border.ROUNDED
        local old_build = Tab.build
        Tab.build = function(self, ...)
          local bar = function(c, x, y)
            if x <= 0 or x == self._area.w - 1 or th.mgr.border_symbol ~= "│" then
              return ui.Bar(ui.Edge.TOP)
            end
            return ui.Bar(ui.Edge.TOP)
              :area(
                ui.Rect { x = x, y = math.max(0, y), w = ya.clamp(0, self._area.w - x, 1), h = math.min(1, self._area.h) }
              )
              :symbol(c)
          end
          local c = self._chunks
          self._chunks = {
            c[1]:pad(ui.Pad.y(1)),
            c[2]:pad(ui.Pad(1, c[3].w > 0 and 0 or 1, 1, c[1].w > 0 and 0 or 1)),
            c[3]:pad(ui.Pad.y(1)),
          }
          local style = th.mgr.border_style
          self._base = ya.list_merge(self._base or {}, {
            ui.Border(ui.Edge.ALL):area(self._area):type(type):style(style),
            ui.Bar(ui.Edge.RIGHT):area(self._chunks[1]):style(style),
            ui.Bar(ui.Edge.LEFT):area(self._chunks[3]):style(style),
            bar("┬", c[1].right - 1, c[1].y),
            bar("┴", c[1].right - 1, c[1].bottom - 1),
            bar("┬", c[2].right, c[2].y),
            bar("┴", c[2].right, c[2].bottom - 1),
          })
          old_build(self, ...)
        end
      end
      return { setup = setup }
    '';
  };

  # ========================================================================
  # GLOW - Markdown previewer using glow
  # ========================================================================
  "yazi/plugins/glow.yazi/main.lua" = {
    text = ''
      local M = {}

      function M:peek(job)
        local child = Command("glow")
          :arg("-s"):arg("dark")
          :arg("-w"):arg(tostring(job.area.w))
          :arg(tostring(job.file.url))
          :stdout(Command.PIPED)
          :stderr(Command.PIPED)
          :spawn()

        if not child then
          return self:fallback_to_builtin(job)
        end

        local output, err = child:wait_with_output()
        if not output then
          return self:fallback_to_builtin(job)
        end

        return ui.Text.parse(output.stdout):area(job.area)
      end

      function M:seek(units)
        local h = cx.active.current.hovered
        if h and h.url then
          ya.manager_emit("peek", { math.max(0, cx.active.preview.skip + units), only_if = tostring(h.url) })
        end
      end

      function M:fallback_to_builtin(job)
        local cmd = "cat"
        local child = Command(cmd):args({ tostring(job.file.url) }):stdout(Command.PIPED):spawn()
        if not child then return {} end
        local output = child:wait_with_output()
        if not output then return {} end
        return ui.Text.parse(output.stdout):area(job.area)
      end

      return M
    '';
  };

  # ========================================================================
  # SMART-FILTER - Enhanced filtering with visual feedback
  # ========================================================================
  "yazi/plugins/smart_filter.yazi/main.lua" = {
    text = ''
      local function entry(self, args)
        ya.manager_emit("filter", { smart = true })
      end

      return { entry = entry }
    '';
  };

  # ========================================================================
  # CHMOD - Visual permission editor (upstream minimal, Command:arg)
  # ========================================================================
  "yazi/plugins/chmod.yazi/main.lua" = {
    text = ''
      local function entry(_)
        local h = cx.active.current.hovered
        if not h then
          ya.notify {
            title = "Chmod",
            content = "No file hovered",
            level = "warn",
            timeout = 3,
          }
          return
        end

        local value, event = ya.input {
          title = "Change permissions (octal, e.g., 755):",
          position = { "top-center", y = 2, w = 40 },
        }

        if event ~= 1 or not value or value == "" then
          return
        end

        local output, err = Command("chmod")
          :arg(value)
          :arg(tostring(h.url))
          :stdout(Command.PIPED)
          :stderr(Command.PIPED)
          :output()

        if output then
          ya.manager_emit("refresh", {})
          ya.notify {
            title = "Chmod",
            content = "Permissions changed to " .. value,
            level = "info",
            timeout = 2,
          }
        else
          ya.notify {
            title = "Chmod",
            content = "Failed: " .. tostring(err),
            level = "error",
            timeout = 3,
          }
        end
      end

      return { entry = entry }
    '';
  };

  # ========================================================================
  # BOOKMARKS - Quick directory bookmarks
  # ========================================================================
  "yazi/plugins/bookmarks.yazi/main.lua" = {
    text = ''
      local bookmarks = {
        h = "~",
        c = "~/.config",
        n = "~/.nixos",
        i = "~/000_inbox",
        w = "~/100_hwc",
        p = "~/200_personal",
        t = "~/300_tech",
        m = "~/500_media",
        v = "~/900_vaults",
      }

      local function setup()
        -- Setup is called from init.lua
      end

      local function entry(args)
        local key = args[1]
        if not key then
          ya.notify {
            title = "Bookmarks",
            content = "Available: h(home) c(config) n(nixos) i(inbox) w(work) p(personal) t(tech) m(media) v(vaults)",
            level = "info",
            timeout = 5
          }
          return
        end

        local path = bookmarks[key]
        if path then
          ya.manager_emit("cd", { path })
        else
          ya.notify {
            title = "Bookmarks",
            content = "Unknown bookmark: " .. key,
            level = "warn",
            timeout = 3
          }
        end
      end

      return {
        setup = setup,
        entry = entry,
      }
    '';
  };
}
