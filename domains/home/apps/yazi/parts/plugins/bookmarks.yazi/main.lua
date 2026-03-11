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
  d = "~/Downloads",
}

local function setup()
  -- No setup needed
end

local function entry(_, job)
  local key = job.args[1]
  if not key then
    ya.notify {
      title = "Bookmarks",
      content = "h=home c=config n=nixos i=inbox w=work p=personal t=tech m=media v=vaults d=downloads",
      level = "info",
      timeout = 5
    }
    return
  end

  local path = bookmarks[key]
  if not path then
    ya.notify {
      title = "Bookmarks",
      content = "Unknown bookmark: " .. key,
      level = "warn",
      timeout = 2
    }
    return
  end

  -- Use ya.emit (new API) instead of ya.manager_emit
  ya.emit("cd", { ya.expand(path) })
end

return {
  setup = setup,
  entry = entry,
}
