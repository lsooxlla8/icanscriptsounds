local core_path = assert(arg[1], "Core path is required")
local config_path = assert(arg[2], "Config path is required")
local track_name = assert(arg[3], "Track name is required")
local expected_rule = arg[4]
local Core = dofile(core_path)
local config, errors = Core.load_config(config_path)
assert(config, table.concat(errors or {}, "\n"))
local result = Core.classify(config, track_name)
assert(result.winner, "No rule matched " .. track_name)
if expected_rule then
  assert(
    result.winner.node.id == expected_rule,
    track_name .. " matched " .. result.winner.node.id
      .. " instead of " .. expected_rule
  )
end
print(track_name .. " -> " .. Core.path_names(result.winner.node))
