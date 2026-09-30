--- @since 26.5.6
--- @sync entry
local M = {}

local snapshot = ya.sync(function(state)
  return { store = state.store, entries = state.entries, cursor = state.cursor,
    focused = state.focused, cwd = tostring(cx.active.current.cwd) }
end)

local update = ya.sync(function(state, entries, cursor, focused)
  if entries then state.entries = entries end
  state.cursor = math.max(1, math.min(cursor or state.cursor, #state.entries))
  if focused ~= nil then state.focused = focused end
  ui.render()
end)

local function notify(message)
  ya.notify { title = "Favorites", content = message, level = "warn", timeout = 5 }
end

local function store(action, path, name)
  local opts = snapshot().store
  local output, err = Command(opts.python)
    :arg({ opts.helper, opts.path, opts.defaults, action, path or "", name or "" })
    :stdout(Command.PIPED):stderr(Command.PIPED):output()
  if not output then notify("Cannot run the favorites store: " .. tostring(err)); return end
  local response = ya.json_decode(output.stdout)
  if not response or not response.ok or not output.status.success then
    notify(response and response.error or "Cannot read favorites. Inspect the Yazi log.")
    return
  end
  update(response.favorites)
  return response.favorites
end

local function active_index(entries, cwd)
  local best, length = nil, 0
  for i, entry in ipairs(entries) do
    local path = entry.path
    if (cwd == path or cwd:sub(1, #path + 1) == path .. "/") and #path > length then
      best, length = i, #path
    end
  end
  return best
end

local function open(index)
  local entry = snapshot().entries[index]
  if not entry then return end
  local cha = fs.cha(Url(entry.path), true)
  if not cha or not cha.is_dir then
    notify("Favorite unavailable: " .. entry.name .. ". Restore its folder or remove the favorite.")
    return
  end
  update(nil, index)
  ya.emit("cd", { entry.path, raw = true })
end

local function move(step, jump)
  local state = snapshot()
  if #state.entries == 0 then return end
  local origin = jump and active_index(state.entries, state.cwd) or state.cursor
  origin = origin or (step > 0 and 0 or #state.entries + 1)
  local index = ((origin - 1 + step) % #state.entries) + 1
  update(nil, index)
  if jump then open(index) end
end

local function edit(action)
  local state = snapshot()
  local entry = state.entries[state.cursor]
  if action ~= "add" and not entry then return end
  local path = action == "add" and state.cwd or entry.path
  if action == "remove" then
    local accepted = ya.confirm {
      pos = { "center", w = 50, h = 8 }, title = ui.Line("Remove favorite?"),
      body = ui.Text("Remove " .. entry.name .. " from favorites?\nThe folder and its files stay in place."),
    }
    if accepted then store("remove", path) end
    return
  end
  local suggested = action == "rename" and entry.name or path:match("([^/]+)/*$") or path
  local name, event = ya.input {
    title = action == "rename" and "Rename favorite:" or "Add current folder to favorites:",
    value = suggested, pos = { "center", w = 50 },
  }
  if event == 1 and name and name:match("%S") then store(action, path, name) end
end

function M:setup(opts)
  self.store, self.entries = opts.store, opts.favorites or {}
  self.cursor, self.focused = 1, false
  local state = self
  -- Permanent by design: use the Parent Lua seam; keep Tab/full-border layout,
  -- file-manager state and preview rendering. Tested with Yazi 26.5.6.
  Parent.redraw = function(panel)
    local area = panel._area
    if area.w < 1 or area.h < 1 then return {} end
    local active = active_index(state.entries, tostring(panel._tab.current.cwd))
    local visible = math.max(0, area.h - 2)
    local origin = math.max(1, math.min(state.cursor - visible + 1, #state.entries - visible + 1))
    local lines = { ui.Line(state.focused and "favorites *" or "favorites"):style(th.tabs.active) }
    for i = origin, math.min(#state.entries, origin + visible - 1) do
      local line = ui.Line((i == active and "● " or "  ") .. state.entries[i].name)
      if state.focused and i == state.cursor then line:style(th.tabs.active)
      elseif i == active then line:style(th.tabs.inactive) end
      line:truncate { max = area.w, ellipsis = "…" }
      lines[#lines + 1] = line
    end
    if #state.entries == 0 and visible > 0 then lines[#lines + 1] = ui.Line("a: add folder") end
    return {
      ui.Text(lines):area(area),
      ui.Text(state.focused and "a add r rename d remove" or "Alt+h focus")
        :area(ui.Rect { x = area.x, y = area.bottom - 1, w = area.w, h = 1 }):style(th.which.desc),
    }
  end
  Parent.click = function(panel, event, up)
    if up or not event.is_left then return end
    local visible = math.max(0, panel._area.h - 2)
    local origin = math.max(1, math.min(state.cursor - visible + 1, #state.entries - visible + 1))
    local index = event.y - panel._area.y - 1 + origin
    if state.entries[index] and event.y < panel._area.bottom - 1 then
      state.cursor = index
      ui.render()
      if not state.focused then ya.async(function() open(index) end) end
    end
  end
  Parent.scroll = function(_, _, step)
    if #state.entries == 0 then return end
    state.cursor = ((state.cursor - 1 + step) % #state.entries) + 1
    ui.render()
  end
  -- File-selection markers for the parent must not draw over favorites.
  Markers.build = function(panel)
    panel._children = { Marker:new(panel._chunks[2], panel._tab.current) }
  end
  ya.emit("plugin", { "bookmarks", "load" })
end

function M:entry(job)
  local action = job.args[1] or "focus"
  if action == "load" then ya.async(function() store("load") end)
  elseif action == "focus" then
    self.cursor = active_index(self.entries, tostring(cx.active.current.cwd)) or self.cursor
    self.focused = true
    ui.render()
    ya.async(function() store("load") end)
  elseif action == "close" then self.focused = false; ui.render()
  elseif action == "next" or action == "previous" then
    local step = action == "next" and 1 or -1
    if self.focused then
      if #self.entries > 0 then self.cursor = ((self.cursor - 1 + step) % #self.entries) + 1 end
      ui.render()
    else ya.async(function() if store("load") then move(step, true) end end) end
  elseif action == "open-at" then
    local index = tonumber(job.args[2])
    ya.async(function() open(index) end)
  elseif action == "add" or action == "rename" or action == "remove" then
    ya.async(function() edit(action) end)
  elseif action == "route" then
    local command, args = job.args[2], {}
    for key, value in pairs(job.args) do
      if type(key) == "number" and key >= 3 then args[key - 2] = value
      elseif type(key) == "string" then args[key] = value end
    end
    if self.focused then
      if command == "arrow" then
        local count = args[1]
        if count == "top" then self.cursor = 1
        elseif count == "bot" then self.cursor = math.max(1, #self.entries)
        else
          local step = tonumber(count) or (tostring(count):sub(1, 1) == "-" and -5 or 5)
          self.cursor = math.max(1, math.min(self.cursor + step, #self.entries))
        end
      elseif command == "open" or command == "enter" then
        local index = self.cursor
        self.focused = false
        ya.async(function() open(index) end)
      elseif command == "leave" or command == "escape" or command == "quit" then self.focused = false
      elseif command == "create" then ya.async(function() edit("add") end)
      elseif command == "rename" then ya.async(function() edit("rename") end)
      elseif command == "remove" and not args.permanently then ya.async(function() edit("remove") end)
      else notify("Favorites have focus. Use Enter to open a folder or Alt+l to return to files.") end
      ui.render()
    elseif command == "select-down" then ya.emit("toggle", {}); ya.emit("arrow", { 1 })
    elseif command == "select-up" then ya.emit("arrow", { -1 }); ya.emit("toggle", {})
    elseif command == "paste-into" then ya.emit("enter", {}); ya.emit("paste", {}); ya.emit("leave", {})
    else ya.emit(command, args) end
  else notify("Unknown favorites action: " .. tostring(action)) end
end

return M
