local function entry(self, args)
  ya.manager_emit("filter", { smart = true })
end

return { entry = entry }
