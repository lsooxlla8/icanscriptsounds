-- @noindex

for _, path in ipairs(arg) do
  local chunk, error_message = loadfile(path)
  assert(chunk, path .. ": " .. tostring(error_message))
end

print("Track Organizer Lua syntax passed")
