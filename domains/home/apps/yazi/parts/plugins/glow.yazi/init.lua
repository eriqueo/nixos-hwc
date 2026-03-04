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
