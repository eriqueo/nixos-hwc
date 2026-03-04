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

local function entry(_, job)
  local key = job.args[1]
  if not key then
    ya.notify {
      title = "Bookmarks",
      content = "Available: (home) (config) (nixos) (inbox) (work) (personal) t(tech) m(media) v(vaults)",
      level = "info",
      timeout = 5
    }
    return
  end

  local path = bookmarks[key]
  if not path then
    ya.notify {
      title = "Bookmarks",
      content = "Unknown: " .. key,
      level = "warn",
      timeout = 2
    }
    return
  end

  -- Expand ~ and cd --
  local expanded = ya.expand(path)  
  ya.manager_emit("cd", { expanded })
end

return {
  setup = setup,
  entry = entry,
}
