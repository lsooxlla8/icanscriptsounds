local core_path = assert(arg[1], "Core path is required")
local Core = dofile(core_path)

for index = 2, #arg do
  local path = arg[index]
  local config, errors = Core.load_config(path)
  assert(config, path .. ":\n" .. table.concat(errors or {}, "\n"))
  local validation = Core.validate(config, { semantic = true })
  assert(validation.ok, path .. ":\n" .. Core.validation_summary(validation))
  print(
    path .. ": valid, " .. tostring(#validation.warnings) .. " warning(s)"
  )
  for _, warning in ipairs(validation.warnings) do
    print("  " .. warning)
  end
end
