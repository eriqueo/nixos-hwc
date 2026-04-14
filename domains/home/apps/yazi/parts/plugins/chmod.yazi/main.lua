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

  local cmd = Command("chmod")
  if h.cha.is_dir then cmd = cmd:arg("-R") end
  local output, err = cmd
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
