-- @noindex

local script_path = assert(arg[1], "Organizer script path is required")
local core_path = assert(arg[2], "Core script path is required")
local auto_adjust_closures = arg[3] == "auto"
local requested_preset_slot = tonumber(arg[4])
local requested_preset_file = arg[5]

local real_dofile = dofile
local Core = real_dofile(core_path)

local config = {
  settings = {
    create_folders = true,
    move_existing_folders = true,
    unknown_tracks = "folder",
    unknown_folder_name = "OTHER",
    subfolder_min_tracks = 3,
    numbered_family_min_tracks = 3,
    case_sensitive = false,
    preserve_relative_order = true,
    intro_first = true,
    outro_last = true,
    main_first = true,
    group_similar_names = true,
    natural_name_sort = true,
    dry_run = false,
    debug = false,
  },
  modifiers = {
    {
      id = "intro",
      name = "Intro / Opening",
      placement = "first",
      order = 10,
      enabled = true,
      patterns = { "intro", "opening" },
      excludes = {},
    },
    {
      id = "main",
      name = "Main before base",
      placement = "family_first",
      order = 20,
      enabled = true,
      patterns = { "main" },
      excludes = {},
    },
    {
      id = "outro",
      name = "Outro / Ending",
      placement = "last",
      order = 30,
      enabled = true,
      patterns = { "outro" },
      excludes = {},
    },
  },
  categories = {
    {
      id = "drums",
      name = "DRUMS",
      folder = "DRUMS",
      order = 10,
      priority = 0,
      enabled = true,
      patterns = {},
      excludes = {},
    },
    {
      id = "bass",
      name = "BASS",
      folder = "BASS",
      order = 20,
      priority = 0,
      enabled = true,
      patterns = {},
      excludes = {},
    },
    {
      id = "guitars",
      name = "GUITARS",
      folder = "GUITARS",
      order = 30,
      priority = 0,
      enabled = true,
      patterns = {},
      excludes = {},
    },
    {
      id = "flat",
      name = "FLAT ORDER",
      folder = "",
      container = "order",
      order = 40,
      priority = 0,
      enabled = true,
      patterns = {},
      excludes = {},
    },
    {
      id = "other",
      name = "OTHER",
      folder = "OTHER",
      order = 9999,
      priority = -1000,
      enabled = true,
      special = true,
      patterns = {},
      excludes = {},
    },
  },
  rules = {
    {
      id = "drums.kick",
      name = "Kick",
      folder = "KICK",
      parent = "drums",
      order = 10,
      priority = 100,
      enabled = true,
      patterns = { "kick" },
      excludes = {},
    },
    {
      id = "drums.snare",
      name = "Snare",
      folder = "SNARE",
      parent = "drums",
      order = 20,
      priority = 100,
      enabled = true,
      patterns = { "snare" },
      excludes = {},
    },
    {
      id = "drums.metal",
      name = "Metal",
      folder = "METAL",
      parent = "drums",
      order = 30,
      priority = 100,
      enabled = true,
      patterns = { "hat" },
      excludes = {},
    },
    {
      id = "bass.main",
      name = "Bass",
      folder = "BASS",
      parent = "bass",
      order = 10,
      priority = 100,
      enabled = true,
      patterns = { "bass" },
      excludes = { "bass guitar", "bass gtr", "bass guit" },
    },
    {
      id = "guitars.guitar",
      name = "Guitars",
      folder = "GUITARS",
      parent = "guitars",
      order = 10,
      priority = 100,
      enabled = true,
      patterns = { "guitar", "gtr", "guit" },
      excludes = { "bass guitar", "bass gtr", "bass guit" },
    },
    {
      id = "guitars.guitar.lead",
      name = "Lead Guitar",
      folder = "",
      parent = "guitars.guitar",
      order = 10,
      priority = 195,
      enabled = true,
      patterns = { "lead guitar", "lead gtr" },
      excludes = {},
    },
    {
      id = "guitars.bass_guitars",
      name = "Bass Guitars",
      folder = "BASS GUITARS",
      parent = "guitars",
      order = 20,
      priority = 0,
      enabled = true,
      patterns = {},
      excludes = {},
    },
    {
      id = "guitars.bass_guitar",
      name = "Bass Guitar",
      folder = "",
      parent = "guitars.bass_guitars",
      order = 10,
      priority = 230,
      enabled = true,
      patterns = { "bass guitar", "bass gtr", "bass guit", "bass guitar di" },
      excludes = {},
    },
    {
      id = "flat.first",
      name = "Flat First",
      folder = "",
      parent = "flat",
      order = 10,
      priority = 180,
      enabled = true,
      patterns = { "flat first" },
      excludes = {},
    },
    {
      id = "flat.second",
      name = "Flat Second",
      folder = "",
      parent = "flat",
      order = 20,
      priority = 180,
      enabled = true,
      patterns = { "flat second" },
      excludes = {},
    },
  },
}
Core.rebuild(config)
local loaded_config_path
Core.load_config = function(path)
  loaded_config_path = path
  return config, {}
end

io.open = function()
  return { close = function() end }
end
dofile = function(path)
  if path:match("TrackOrganizer_Core%.lua$") then
    return Core
  end
  return real_dofile(path)
end

local tracks = {}
local next_id = 1
local errors = {}
local delete_calls = 0

local function add_track(name, depth)
  local track = {
    id = next_id,
    name = name,
    depth = depth or 0,
    tag = "",
    selected = false,
    valid = true,
  }
  next_id = next_id + 1
  tracks[#tracks + 1] = track
  return track
end

local function selected_tracks()
  local result = {}
  for _, track in ipairs(tracks) do
    if track.selected then
      result[#result + 1] = track
    end
  end
  return result
end

reaper = {
  RecursiveCreateDirectory = function()
    return 1
  end,
  EnumerateFiles = requested_preset_slot and function(_, index)
    local names = {
      "01 Music Mixing.ini",
      "02 Film Post.ini",
      "03 Sound Design.ini",
      "04 Podcast.ini",
      "05 Audiobook.ini",
    }
    return names[index + 1]
  end or nil,
  CountTracks = function()
    return #tracks
  end,
  GetTrack = function(_, index)
    return tracks[index + 1]
  end,
  GetTrackName = function(track)
    return true, track.name
  end,
  GetMediaTrackInfo_Value = function(track, key)
    assert(key == "I_FOLDERDEPTH")
    return track.depth
  end,
  SetMediaTrackInfo_Value = function(track, key, value)
    assert(key == "I_FOLDERDEPTH")
    local end_track
    if auto_adjust_closures and track.depth > 0 and value == track.depth - 1 then
      local start_index
      for index, candidate in ipairs(tracks) do
        if candidate == track then
          start_index = index
          break
        end
      end
      local balance = track.depth
      for index = start_index + 1, #tracks do
        balance = balance + tracks[index].depth
        if balance <= 0 then
          end_track = tracks[index]
          break
        end
      end
    end
    track.depth = value
    if end_track then
      end_track.depth = end_track.depth + 1
    end
  end,
  GetSetMediaTrackInfo_String = function(track, key, value, set_value)
    if key == "P_NAME" then
      if set_value then
        track.name = value
      end
      return true, track.name
    end
    assert(key == "P_EXT:ICSS_TRACK_ORGANIZER_FOLDER")
    if set_value then
      track.tag = value
    end
    return true, track.tag
  end,
  CountSelectedTracks = function()
    return #selected_tracks()
  end,
  GetSelectedTrack = function(_, index)
    return selected_tracks()[index + 1]
  end,
  SetTrackSelected = function(track, selected)
    track.selected = selected
  end,
  ValidatePtr2 = function(_, track)
    return track.valid
  end,
  Main_OnCommand = function(command)
    assert(command == 40297)
    for _, track in ipairs(tracks) do
      track.selected = false
    end
  end,
  InsertTrackAtIndex = function(index)
    local track = {
      id = next_id,
      name = "",
      depth = 0,
      tag = "",
      selected = false,
      valid = true,
    }
    next_id = next_id + 1
    table.insert(tracks, index + 1, track)
  end,
  ReorderSelectedTracks = function(index)
    local selected = {}
    local remaining = {}
    for _, track in ipairs(tracks) do
      if track.selected then
        selected[#selected + 1] = track
      else
        remaining[#remaining + 1] = track
      end
    end
    tracks = remaining
    local insertion = math.min(index, #tracks) + 1
    for offset, track in ipairs(selected) do
      table.insert(tracks, insertion + offset - 1, track)
    end
  end,
  DeleteTrack = function(target)
    delete_calls = delete_calls + 1
    for index, track in ipairs(tracks) do
      if track == target then
        track.valid = false
        table.remove(tracks, index)
        return
      end
    end
  end,
  CountTrackMediaItems = function()
    return 0
  end,
  TrackFX_GetCount = function()
    return 0
  end,
  TrackFX_GetRecCount = function()
    return 0
  end,
  CountTrackEnvelopes = function()
    return 0
  end,
  GetTrackNumSends = function()
    return 0
  end,
  TrackList_AdjustWindows = function() end,
  UpdateArrange = function() end,
  Undo_BeginBlock2 = function() end,
  Undo_EndBlock2 = function() end,
  Undo_DoUndo2 = function() end,
  PreventUIRefresh = function() end,
  ShowMessageBox = function(message)
    errors[#errors + 1] = message
  end,
}

if requested_preset_file then
  _G.ICSS_TRACK_ORGANIZER_PRESET_FILE = requested_preset_file
elseif requested_preset_slot then
  _G.ICSS_TRACK_ORGANIZER_PRESET_SLOT = requested_preset_slot
end

local function depth_sum()
  local total = 0
  for _, track in ipairs(tracks) do
    total = total + track.depth
  end
  return total
end

local function run_organizer(label)
  local previous_errors = #errors
  real_dofile(script_path)
  assert(#errors == previous_errors, label .. ": " .. tostring(errors[#errors]))
  assert(depth_sum() == 0, label .. ": folder depth is unbalanced")
end

local function assert_ordered_before(first_name, second_name)
  local first_index
  local second_index
  for index, track in ipairs(tracks) do
    first_index = track.name == first_name and index or first_index
    second_index = track.name == second_name and index or second_index
  end
  local names = {}
  for _, track in ipairs(tracks) do
    names[#names + 1] = track.name
  end
  assert(
    first_index and second_index and first_index < second_index,
    tostring(first_name) .. " (" .. tostring(first_index) .. ") must precede "
      .. tostring(second_name) .. " (" .. tostring(second_index) .. "): "
      .. table.concat(names, " | ")
  )
end

local function assert_inside_managed_folder(track_name_value, folder_id)
  local folder_index
  local track_index
  for index, track in ipairs(tracks) do
    folder_index = track.tag == folder_id and index or folder_index
    track_index = track.name == track_name_value and index or track_index
  end
  assert(folder_index, "Missing managed folder " .. folder_id)
  assert(track_index, "Missing track " .. track_name_value)
  local balance = tracks[folder_index].depth
  local end_index
  for index = folder_index + 1, #tracks do
    balance = balance + tracks[index].depth
    if balance <= 0 then
      end_index = index
      break
    end
  end
  assert(
    end_index and track_index > folder_index and track_index <= end_index,
    track_name_value .. " is not inside " .. folder_id
  )
end

local function assert_managed_folders_are_siblings(first_id, second_id)
  local running_depth = 0
  local first_depth
  local second_depth
  local first_count = 0
  local second_count = 0
  for _, track in ipairs(tracks) do
    if track.tag == first_id then
      first_depth = running_depth
      first_count = first_count + 1
    elseif track.tag == second_id then
      second_depth = running_depth
      second_count = second_count + 1
    end
    running_depth = running_depth + track.depth
  end
  assert(first_count == 1, "Expected one managed folder " .. first_id)
  assert(second_count == 1, "Expected one managed folder " .. second_id)
  assert(
    first_depth == second_depth,
    first_id .. " and " .. second_id .. " are not sibling folders"
  )
end

local function assert_no_managed_folder(folder_id)
  for _, track in ipairs(tracks) do
    assert(track.tag ~= folder_id, "Unexpected managed folder " .. folder_id)
  end
end

local function assert_original_folder_contains(folder_name, child_names)
  local folder_index
  for index, track in ipairs(tracks) do
    if track.name == folder_name then
      folder_index = index
      break
    end
  end
  assert(folder_index, "Missing original folder " .. folder_name)
  assert(tracks[folder_index].depth > 0, folder_name .. " is no longer a folder")
  local balance = tracks[folder_index].depth
  local contained = {}
  for index = folder_index + 1, #tracks do
    contained[tracks[index].name] = true
    balance = balance + tracks[index].depth
    if balance <= 0 then
      break
    end
  end
  for _, child_name in ipairs(child_names) do
    assert(
      contained[child_name],
      child_name .. " was removed from existing folder " .. folder_name
    )
  end
end

add_track("Kick")
add_track("Kick Shuffle")
add_track("Kick Shuffle 2")
add_track("Snare")
add_track("Snare Delayed")
add_track("Snare Delayed 2")
add_track("Snare Fill")
add_track("Snare Fill 2")
add_track("Hat")
add_track("Hat 2")
add_track("Hat 3")
add_track("Main Bass")
add_track("Bass 2")
add_track("Guitar 2")
add_track("Lead Guitar")
add_track("gtr 4")
add_track("Guit 2")
add_track("Guit 3")
add_track("Guitar")
add_track("Bass Guitar DI")
add_track("Bass Guit")
add_track("Bass guit 2")
add_track("Flat Second")
add_track("Flat First")
add_track("Audio 37")
add_track("Audio 38")
add_track("Audio 39")
add_track("Imported Drum Folder", 1)
add_track("Kick Folder Child")
add_track("Snare Folder Child", -1)
add_track("Mixed Existing Folder", 1)
add_track("Kick Mixed Child")
add_track("Bass Guitar Mixed Child", -1)

run_organizer("initial run")
assert_inside_managed_folder("Audio 38", "dynamic:other:audio")
assert_no_managed_folder("drums.metal")
assert_inside_managed_folder("Hat 2", "dynamic:drums.metal:hat")
assert_inside_managed_folder("Guitar 2", "guitars.guitar")
assert_inside_managed_folder("Lead Guitar", "guitars.guitar")
assert_inside_managed_folder("Bass Guitar DI", "guitars.bass_guitars")
assert_inside_managed_folder("Bass Guit", "guitars.bass_guitars")
assert_inside_managed_folder("Bass guit 2", "guitars.bass_guitars")
assert_managed_folders_are_siblings("guitars.guitar", "guitars.bass_guitars")
assert_ordered_before("Kick", "Snare")
assert_ordered_before("Snare", "Snare Fill")
assert_ordered_before("Snare Fill", "Hat")
assert_ordered_before("Guitar", "Guit 2")
assert_ordered_before("Guit 2", "Guit 3")
assert_ordered_before("Guit 3", "gtr 4")
assert_no_managed_folder("flat")
assert_ordered_before("Flat First", "Flat Second")
assert_inside_managed_folder("Imported Drum Folder", "drums")
assert_original_folder_contains(
  "Imported Drum Folder",
  { "Kick Folder Child", "Snare Folder Child" }
)
assert_inside_managed_folder("Mixed Existing Folder", "other")
assert_original_folder_contains(
  "Mixed Existing Folder",
  { "Kick Mixed Child", "Bass Guitar Mixed Child" }
)

-- Simulate the upgrade from the old layout, where the physical BASS GUITARS
-- wrapper used the ID that is now the child Bass Guitar classification rule.
for _, track in ipairs(tracks) do
  if track.tag == "guitars.bass_guitars" then
    track.tag = "guitars.bass_guitar"
    break
  end
end
run_organizer("migrate retired bass-guitar wrapper")
assert_inside_managed_folder("Bass Guitar DI", "guitars.bass_guitars")
assert_managed_folders_are_siblings("guitars.guitar", "guitars.bass_guitars")

-- Simulate the already-corrupted intermediate state where that old version
-- cleared the wrapper tag completely but left the physical folder behind.
for _, track in ipairs(tracks) do
  if track.tag == "guitars.bass_guitars" then
    track.tag = ""
    break
  end
end
run_organizer("recover untagged bass-guitar wrapper")
assert_inside_managed_folder("Bass Guitar DI", "guitars.bass_guitars")
assert_managed_folders_are_siblings("guitars.guitar", "guitars.bass_guitars")

add_track("Intro Bass")
add_track("Opening Bass")
add_track("Kick Shuffle 3")
add_track("New Weird Track")
run_organizer("rerun after append")
assert_ordered_before("Intro Bass", "Main Bass")
assert_ordered_before("Opening Bass", "Main Bass")

add_track("Outro Bass")
add_track("Hat 4")
run_organizer("second rerun after append")
assert_ordered_before("Main Bass", "Outro Bass")

run_organizer("idempotent rerun")
assert(delete_calls == 0, "Organizer must never call DeleteTrack")

config.settings.numbered_family_min_tracks = 99
run_organizer("preserve obsolete dynamic folders")
assert(delete_calls == 0, "Obsolete dynamic folders must be preserved")

local placed_ok, placed_error = Core.move_after(
  config,
  "guitars.guitar",
  "guitars.bass_guitars"
)
assert(placed_ok, placed_error)
assert(config.nodes_by_id.guitars.children[1].id == "guitars.bass_guitars")
assert(config.nodes_by_id.guitars.children[2].id == "guitars.guitar")

local cycle_ok = Core.reparent_node(
  config,
  "guitars.guitar",
  "guitars.guitar.lead"
)
assert(not cycle_ok, "Moving a rule into its own child must be rejected")

local moved_ok, moved_error = Core.reparent_node(
  config,
  "guitars.guitar",
  "bass"
)
assert(moved_ok, moved_error)
assert(config.nodes_by_id["guitars.guitar"].parent == "bass")
assert(config.nodes_by_id["guitars.guitar.lead"].parent == "guitars.guitar")
assert(config.nodes_by_id["guitars.guitar.lead"].patterns[1] == "lead guitar")

if requested_preset_file then
  assert(
    loaded_config_path:match(requested_preset_file:gsub("([^%w])", "%%%1") .. "$"),
    "Named preset action selected the wrong config: " .. tostring(loaded_config_path)
  )
  _G.ICSS_TRACK_ORGANIZER_PRESET_FILE = nil
elseif requested_preset_slot then
  assert(
    loaded_config_path:match(
      string.format("%02d .+%%.ini$", requested_preset_slot)
    ),
    "Preset action selected the wrong config: " .. tostring(loaded_config_path)
  )
  _G.ICSS_TRACK_ORGANIZER_PRESET_SLOT = nil
end

print("Track Organizer rerun mock passed")
