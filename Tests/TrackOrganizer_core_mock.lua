-- @noindex

local core_path = assert(arg[1], "Core script path is required")
local config_path = assert(arg[2], "Config path is required")
local Core = dofile(core_path)

local config, errors, validation = Core.load_config(config_path)
assert(config, table.concat(errors or {}, "\n"))
assert(validation.ok)
assert(#validation.errors == 0)
assert(#validation.warnings == 0)
local semantic_validation = Core.validate(config, { semantic = true })
assert(semantic_validation.ok)
assert(#semantic_validation.warnings == 0)

local flexible_list = Core.split_list("snare fill, snr fill; sd fill")
assert(#flexible_list == 3)
assert(flexible_list[1] == "snare fill")
assert(flexible_list[2] == "snr fill")
assert(flexible_list[3] == "sd fill")

assert(#config.modifiers == 3)
local intro_info = Core.name_sort_info("Opening Bass")
local normal_info = Core.name_sort_info("Bass")
local outro_info = Core.name_sort_info("Ending Bass")
assert(Core.name_boundary_rank(intro_info, config) <
  Core.name_boundary_rank(normal_info, config))
assert(Core.name_boundary_rank(outro_info, config) >
  Core.name_boundary_rank(normal_info, config))
assert(Core.main_name_rank(Core.name_sort_info("Main Bass"), config) <
  Core.main_name_rank(normal_info, config))

local virtual_node = Core.copy_table(config.nodes_by_id["drums.metal"])
virtual_node.container = "order"
virtual_node.folder = ""
assert(Core.is_order_group_node(virtual_node))
assert(Core.is_layout_node(virtual_node))
assert(not Core.is_folder_node(virtual_node))

local preset_files = {
  "05 Audiobook.ini",
  "01 Music Mixing.ini",
  "notes.txt",
  "02 Film Post.ini",
}
local presets = Core.list_presets("/presets/", function(_, index)
  return preset_files[index + 1]
end)
assert(#presets == 3)
assert(presets[1].filename == "01 Music Mixing.ini")
assert(presets[1].name == "Music Mixing")
assert(presets[2].slot == 2)
assert(Core.find_preset(presets, "05 Audiobook.ini") == presets[3])

config.nodes_by_id["drums.kick"].patterns[#config.nodes_by_id["drums.kick"].patterns + 1] =
  "lua:["
validation = Core.validate(config)
assert(not validation.ok, "Invalid Lua patterns must fail validation")

config = assert(Core.load_config(config_path))
for _, node in pairs(config.nodes_by_id) do
  node.patterns = {}
end
config.nodes_by_id["drums.kick"].patterns = { "exact kick" }
assert(Core.classify(config, "EXACT KICK").winner.node.id == "drums.kick")
assert(not Core.classify(config, "different track").winner)

config.nodes_by_id["drums.kick"].patterns = { "lua:%D+" }
assert(Core.classify(config, "ABC").winner.node.id == "drums.kick")
assert(not Core.classify(config, "123").winner)

config = assert(Core.load_config(config_path))
local homogeneous = Core.classify_atomic_folder(config, "Imported Folder", {
  { name = "Kick In" },
  { name = "Snare Top" },
})
assert(homogeneous.winner)
assert(homogeneous.winner.category.id == "drums")
assert(homogeneous.winner.node.id == "drums")

local mixed = Core.classify_atomic_folder(config, "Imported Folder", {
  { name = "Kick In" },
  { name = "Lead Vox" },
})
assert(not mixed.winner)
assert(mixed.atomic_reason == "mixed_categories")

local partially_unknown = Core.classify_atomic_folder(config, "Imported Folder", {
  { name = "Kick In" },
  { name = "Audio 37" },
})
assert(not partially_unknown.winner)
assert(partially_unknown.atomic_reason == "unclassified_child")

local copied = Core.copy_table(config)
assert(copied.nodes_by_id.drums.category == copied.nodes_by_id.drums)

local self_move_ok = Core.move_after(config, "guitars.guitar", "guitars.guitar")
assert(not self_move_ok, "A self move must be rejected")

local temporary_path = "/tmp/icss-track-order-test.ini"
local ok, message = Core.save_config(config, temporary_path)
assert(ok, message)
config.settings.unknown_folder_name = "OTHER TEST"
ok, message = Core.save_config(config, temporary_path)
assert(ok, message)
ok, message = Core.restore_backup(temporary_path)
assert(ok, message)
local restored = assert(Core.load_config(temporary_path))
assert(restored.settings.unknown_folder_name == "OTHER")

local main_file = assert(io.open(temporary_path, "rb"))
local main_before_invalid_restore = main_file:read("*a")
main_file:close()
local backup_file = assert(io.open(temporary_path .. ".bak", "wb"))
backup_file:write("[settings]\nthis is not valid\n")
backup_file:close()
ok = Core.restore_backup(temporary_path)
assert(not ok, "An invalid backup must not be restored")
main_file = assert(io.open(temporary_path, "rb"))
assert(main_file:read("*a") == main_before_invalid_restore)
main_file:close()

print("Track Organizer Core mock passed")
