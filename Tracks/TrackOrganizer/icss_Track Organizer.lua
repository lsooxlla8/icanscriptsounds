-- @description icss_Track Organizer
-- @author icanseesounds
-- @version 2.1.0
-- @changelog
--   Add five presets, direct actions, ordering rules, and virtual order groups
--   Add named actions and recoverable deletion for user-created presets
--   Improve repeat-run folder safety, natural sorting, and Rule Manager usability
--   Use the current Music Mixing rule library as the factory default
-- @provides
--   [main] icss_Track Organizer Rule Manager.lua
--   [main] icss_Track Organizer - Preset 1.lua
--   [main] icss_Track Organizer - Preset 2.lua
--   [main] icss_Track Organizer - Preset 3.lua
--   [main] icss_Track Organizer - Preset 4.lua
--   [main] icss_Track Organizer - Preset 5.lua
--   [nomain] TrackOrganizer_Core.lua
--   [nomain] track-order.ini > Factory Presets/01 Music Mixing.ini
--   [nomain] Factory Presets/02 Film Post.ini
--   [nomain] Factory Presets/03 Sound Design.ini
--   [nomain] Factory Presets/04 Podcast.ini
--   [nomain] Factory Presets/05 Audiobook.ini
--   [nomain] README.md
-- @about
--   Classifies and orders tracks from the active preset, creates category
--   folders, and places every unclassified track in OTHER at the end.
--   Existing user folders are moved only as balanced atomic subtrees.
--   Set dry_run=true in the active preset for a console-only preview.

local function script_directory()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*[\\/])") or ""
end

local DIRECTORY = script_directory()
local CORE_PATH = DIRECTORY .. "TrackOrganizer_Core.lua"
local LEGACY_CONFIG_PATH = DIRECTORY .. "track-order.ini"
local PRESETS_DIRECTORY = DIRECTORY .. "Presets/"
local FACTORY_PRESETS_DIRECTORY = DIRECTORY .. "Factory Presets/"
local FOLDER_TAG = "P_EXT:ICSS_TRACK_ORGANIZER_FOLDER"
local PRESET_STATE_SECTION = "ICSS_TRACK_ORGANIZER"
local PRESET_STATE_KEY = "PRESET_FILE"
local LEGACY_PRESET_FILENAMES = {
  ["02 Audiobook.ini"] = "05 Audiobook.ini",
  ["03 Podcast.ini"] = "04 Podcast.ini",
  ["04 Film Post.ini"] = "02 Film Post.ini",
  ["05 Sound Design.ini"] = "03 Sound Design.ini",
}
local FACTORY_PRESET_FILES = {
  "01 Music Mixing.ini",
  "02 Film Post.ini",
  "03 Sound Design.ini",
  "04 Podcast.ini",
  "05 Audiobook.ini",
}

local function current_preset_filename(filename)
  return LEGACY_PRESET_FILENAMES[filename] or filename
end

local core_file = io.open(CORE_PATH, "r")
if not core_file then
  reaper.ShowMessageBox(
    "TrackOrganizer_Core.lua must be next to icss_Track Organizer.lua.",
    "icss_Track Organizer",
    0
  )
  return
end
core_file:close()
local Core = dofile(CORE_PATH)

local presets_ready, presets_error = Core.ensure_presets(
  FACTORY_PRESETS_DIRECTORY,
  PRESETS_DIRECTORY,
  FACTORY_PRESET_FILES,
  function(path)
    return reaper.RecursiveCreateDirectory(path, 0)
  end
)
if not presets_ready then
  reaper.ShowMessageBox(
    "Track Organizer could not prepare its presets:\n\n" .. tostring(presets_error),
    "icss_Track Organizer",
    0
  )
  return
end

local function enumerate_preset(directory, index)
  if not reaper.EnumerateFiles then
    return nil
  end
  return reaper.EnumerateFiles(directory, index)
end

local function selected_config_path()
  local presets = Core.list_presets(PRESETS_DIRECTORY, enumerate_preset)
  local requested_filename = rawget(
    _G,
    "ICSS_TRACK_ORGANIZER_PRESET_FILE"
  )
  local requested_slot = tonumber(
    rawget(_G, "ICSS_TRACK_ORGANIZER_PRESET_SLOT")
  )
  if not requested_filename and requested_slot and presets[requested_slot] then
    requested_filename = presets[requested_slot].filename
  elseif reaper.GetProjExtState then
    local _, stored = reaper.GetProjExtState(
      0,
      PRESET_STATE_SECTION,
      PRESET_STATE_KEY
    )
    requested_filename = stored ~= ""
      and current_preset_filename(stored)
      or nil
  end
  if not requested_filename and reaper.GetExtState then
    local stored = reaper.GetExtState(
      PRESET_STATE_SECTION,
      "DEFAULT_PRESET_FILE"
    )
    requested_filename = stored ~= ""
      and current_preset_filename(stored)
      or nil
  end
  local preset = Core.find_preset(presets, requested_filename)
    or presets[1]
  if preset then
    if reaper.SetProjExtState then
      reaper.SetProjExtState(
        0,
        PRESET_STATE_SECTION,
        PRESET_STATE_KEY,
        preset.filename
      )
    end
    return preset.path, preset
  end
  return LEGACY_CONFIG_PATH, {
    filename = "track-order.ini",
    name = "Legacy Track Order",
  }
end

local CONFIG_PATH, ACTIVE_PRESET = selected_config_path()

local function show_error(message)
  reaper.ShowMessageBox(message, "icss_Track Organizer", 0)
end

local function track_name(track)
  local _, name = reaper.GetTrackName(track)
  return name or ""
end

local function all_tracks()
  local tracks = {}
  for index = 0, reaper.CountTracks(0) - 1 do
    tracks[#tracks + 1] = reaper.GetTrack(0, index)
  end
  return tracks
end

local function folder_depth(track)
  return math.floor(
    reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") + 0.5
  )
end

local function set_folder_depth(track, value)
  reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", value)
end

local function managed_folder_id(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(
    track,
    FOLDER_TAG,
    "",
    false
  )
  return value ~= "" and value or nil
end

local function set_managed_folder_id(track, id)
  reaper.GetSetMediaTrackInfo_String(track, FOLDER_TAG, id or "", true)
end

local content_free_folder_track

local function snapshot_selection()
  local selection = {}
  for index = 0, reaper.CountSelectedTracks(0) - 1 do
    selection[#selection + 1] = reaper.GetSelectedTrack(0, index)
  end
  return selection
end

local function restore_selection(selection)
  reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
  for _, track in ipairs(selection) do
    if reaper.ValidatePtr2(0, track, "MediaTrack*") then
      reaper.SetTrackSelected(track, true)
    end
  end
end

local function find_subtree_end(tracks, start_index)
  local balance = folder_depth(tracks[start_index])
  if balance <= 0 then
    return start_index
  end
  for index = start_index + 1, #tracks do
    balance = balance + folder_depth(tracks[index])
    if balance <= 0 then
      return index
    end
  end
  return nil
end

local function find_subtree_end_in_depths(depths, start_index)
  local balance = depths[start_index]
  if balance <= 0 then
    return start_index
  end
  for index = start_index + 1, #depths do
    balance = balance + depths[index]
    if balance <= 0 then
      return index
    end
  end
  return nil
end

local function unwrap_managed_folders(config)
  local tracks = all_tracks()
  local managed = {}
  local original_depths = {}
  local original_balance = 0
  for index, track in ipairs(tracks) do
    original_depths[index] = folder_depth(track)
    original_balance = original_balance + original_depths[index]
  end
  if original_balance ~= 0 then
    error(
      "The project starts with an unbalanced folder-depth sum of "
      .. original_balance .. "."
    )
  end

  local reserved_ids = {}
  for _, track in ipairs(tracks) do
    local id = managed_folder_id(track)
    local node = id and config.nodes_by_id[id]
    if node and Core.is_folder_node(node) then
      reserved_ids[id] = true
    end
  end

  -- Recover organizer wrappers whose tag was cleared by an older migration.
  -- A name is adoptable only when it identifies exactly one configured folder.
  local adoptable_by_name = {}
  local function register_adoptable(node)
    if node.special or not Core.is_folder_node(node) then
      return
    end
    local name = node.folder ~= "" and node.folder or node.name
    local normalized = Core.normalize(name, config.settings.case_sensitive)
    if adoptable_by_name[normalized] then
      adoptable_by_name[normalized] = false
    else
      adoptable_by_name[normalized] = node
    end
  end
  for _, category in ipairs(config.categories) do
    register_adoptable(category)
  end
  for _, rule in ipairs(config.rules) do
    register_adoptable(rule)
  end

  local function winner_uses_folder(track, folder_node)
    local result = Core.classify(config, track_name(track))
    if not result.winner then
      return false
    end
    for _, node in ipairs(result.winner.node.path or {}) do
      if node.id == folder_node.id then
        return true
      end
    end
    return false
  end

  local function can_adopt_untagged_folder(index, track, folder_node)
    if original_depths[index] ~= 1
      or reserved_ids[folder_node.id]
      or not content_free_folder_track(track)
    then
      return false
    end
    local end_index = find_subtree_end_in_depths(original_depths, index)
    if not end_index or end_index <= index then
      return false
    end
    local matched = 0
    for child_index = index + 1, end_index do
      local child = tracks[child_index]
      if managed_folder_id(child) == nil then
        if not winner_uses_folder(child, folder_node) then
          return false
        end
        matched = matched + 1
      end
    end
    return matched > 0
  end

  local records = {}
  for index, track in ipairs(tracks) do
    local original_depth = original_depths[index]
    local id = managed_folder_id(track)
    if not id and original_depth == 1 then
      local normalized = Core.normalize(
        track_name(track),
        config.settings.case_sensitive
      )
      local candidate = adoptable_by_name[normalized]
      if candidate and can_adopt_untagged_folder(index, track, candidate) then
        id = candidate.id
        set_managed_folder_id(track, id)
        reserved_ids[id] = true
      end
    end
    local node = id and config.nodes_by_id[id]
    local dynamic_folder = id and id:match("^dynamic:")
    local retired_folder = false
    if id and not dynamic_folder
      and (not node or not Core.is_folder_node(node))
    then
      local normalized = Core.normalize(
        track_name(track),
        config.settings.case_sensitive
      )
      local replacement = adoptable_by_name[normalized]
      if replacement
        and can_adopt_untagged_folder(index, track, replacement)
      then
        id = replacement.id
        node = replacement
        set_managed_folder_id(track, id)
        reserved_ids[id] = true
      else
        -- The wrapper is preserved as an ordinary track. Only its obsolete tag
        -- and folder boundary are removed so it cannot trap later siblings.
        retired_folder = true
        set_managed_folder_id(track, "")
        id = nil
      end
    end

    if id and managed[id] then
      -- Preserve duplicate tagged tracks as ordinary user tracks. Only the
      -- first tagged folder for a category is reused as the managed wrapper.
      set_managed_folder_id(track, "")
      id = nil
    end

    if id then
      if original_depth < 0 or original_depth > 1 then
        error(
          "Managed folder '" .. track_name(track)
          .. "' has I_FOLDERDEPTH=" .. original_depth
          .. "; expected 0 or 1."
        )
      end
      managed[id] = track
      records[#records + 1] = {
        track = track,
        index = index,
        depth = original_depth,
      }
    elseif retired_folder then
      if original_depth < 0 or original_depth > 1 then
        error(
          "Retired managed folder '" .. track_name(track)
          .. "' has I_FOLDERDEPTH=" .. original_depth
          .. "; expected 0 or 1."
        )
      end
      records[#records + 1] = {
        track = track,
        index = index,
        depth = original_depth,
        retired = true,
      }
    end
  end

  -- Remove every organizer-created wrapper while preserving all tracks. Using
  -- the original depth snapshot makes nested managed folders safe to unwrap.
  for _, record in ipairs(records) do
    if record.depth > 0 then
        local end_index = find_subtree_end_in_depths(
          original_depths,
          record.index
        )
        if not end_index then
          error(
            "Managed folder '" .. track_name(record.track)
            .. "' is not balanced."
          )
        end
        local end_track = tracks[end_index]
        local end_depth_before = folder_depth(end_track)
        set_folder_depth(
          record.track,
          folder_depth(record.track) - 1
        )

        -- REAPER sometimes moves one folder-closing level to the subtree end
        -- automatically when an opener is removed. Only apply the matching
        -- close adjustment ourselves when REAPER left it unchanged.
        if folder_depth(end_track) == end_depth_before then
          set_folder_depth(end_track, end_depth_before + 1)
        end
    end
  end

  return managed
end

local function build_atomic_units(managed)
  local tracks = all_tracks()
  local managed_tracks = {}
  for _, track in pairs(managed) do
    managed_tracks[track] = true
  end

  local units = {}
  local index = 1
  while index <= #tracks do
    local track = tracks[index]
    if managed_tracks[track] then
      index = index + 1
    else
      local end_index = index
      if folder_depth(track) > 0 then
        end_index = find_subtree_end(tracks, index)
        if not end_index then
          error("Existing folder '" .. track_name(track) .. "' is not balanced.")
        end
      end
      local unit_tracks = {}
      for child_index = index, end_index do
        unit_tracks[#unit_tracks + 1] = tracks[child_index]
      end
      units[#units + 1] = {
        tracks = unit_tracks,
        root = track,
        original_index = index,
        is_folder = folder_depth(track) > 0,
      }
      index = end_index + 1
    end
  end
  return units
end

local function classify_unit(config, unit)
  if not unit.is_folder then
    return Core.classify(config, track_name(unit.root))
  end

  local descendants = {}
  for index = 2, #unit.tracks do
    local track = unit.tracks[index]
    descendants[#descendants + 1] = {
      name = track_name(track),
      is_container = folder_depth(track) > 0,
    }
  end
  return Core.classify_atomic_folder(
    config,
    track_name(unit.root),
    descendants
  )
end

local function best_category_anchor(unit)
  local best
  for _, match in ipairs(unit.classification.matches) do
    if match.category.id == unit.category_id and (
      not best or Core.compare_nodes(match.node, best)
    ) then
      best = match.node
    end
  end
  return best
end

local function common_family_core(units)
  local first_tokens = units[1].name_info.stem_tokens
  for length = #first_tokens, 1, -1 do
    for start_index = 1, #first_tokens - length + 1 do
      local candidate = {}
      for offset = 0, length - 1 do
        candidate[#candidate + 1] = first_tokens[start_index + offset]
      end
      local shared = true
      for unit_index = 2, #units do
        if not Core.sequence_position(
          units[unit_index].name_info.stem_tokens,
          candidate
        ) then
          shared = false
          break
        end
      end
      if shared then
        return candidate
      end
    end
  end

  local shortest = first_tokens
  for unit_index = 2, #units do
    local candidate = units[unit_index].name_info.stem_tokens
    if #candidate < #shortest then
      shortest = candidate
    end
  end
  return shortest
end

local function family_relation_rank(info, core_tokens)
  local position = Core.sequence_position(info.stem_tokens, core_tokens)
  if not position then
    return 3
  end
  if position == 1 and #info.stem_tokens == #core_tokens then
    return 0
  end
  if position == 1 then
    return 1
  end
  return 2
end

local function winning_pattern_tokens(unit, config)
  local winner = unit.classification and unit.classification.winner
  if not winner or (winner.kind ~= "phrase" and winner.kind ~= "exact") then
    return nil
  end
  local body = winner.pattern or ""
  if winner.kind == "exact" then
    body = body:gsub("^exact:", "")
  end
  return Core.name_sort_info(
    body,
    config.settings.case_sensitive
  ).stem_tokens
end

local function node_less(first, second)
  if first and second and first.id ~= second.id then
    if Core.compare_nodes(first, second) then
      return true
    end
    if Core.compare_nodes(second, first) then
      return false
    end
  elseif first and not second then
    return true
  elseif second and not first then
    return false
  end
  return nil
end

local function sort_group(config, group)
  for _, unit in ipairs(group) do
    unit.name_info = Core.name_sort_info(
      track_name(unit.root),
      config.settings.case_sensitive
    )
    unit.boundary_rank = Core.name_boundary_rank(
      unit.name_info,
      config
    )
    unit.main_rank = Core.main_name_rank(
      unit.name_info,
      config
    )
    unit.anchor_node = best_category_anchor(unit)
    local pattern_tokens = winning_pattern_tokens(unit, config)
    unit.rule_relation_rank = pattern_tokens
      and family_relation_rank(unit.name_info, pattern_tokens)
      or 3
  end

  local parents = {}
  for index = 1, #group do
    parents[index] = index
  end
  local function find(index)
    while parents[index] ~= index do
      parents[index] = parents[parents[index]]
      index = parents[index]
    end
    return index
  end
  local function union(first, second)
    local first_root = find(first)
    local second_root = find(second)
    if first_root ~= second_root then
      parents[second_root] = first_root
    end
  end

  if config.settings.group_similar_names then
    for first = 1, #group - 1 do
      for second = first + 1, #group do
        local first_anchor = group[first].anchor_node
        local second_anchor = group[second].anchor_node
        local same_rule = first_anchor and second_anchor
          and first_anchor.id == second_anchor.id
        if group[first].boundary_rank == group[second].boundary_rank
          and (
            same_rule
            or Core.names_similar(
              group[first].name_info,
              group[second].name_info
            )
          )
        then
          union(first, second)
        end
      end
    end
  end

  local families_by_root = {}
  local families = {}
  for index, unit in ipairs(group) do
    local root = find(index)
    local family = families_by_root[root]
    if not family then
      family = {
        units = {},
        boundary_rank = unit.boundary_rank,
        original_index = unit.original_index,
        anchor_node = unit.anchor_node,
      }
      families_by_root[root] = family
      families[#families + 1] = family
    end
    family.units[#family.units + 1] = unit
    family.original_index = math.min(
      family.original_index,
      unit.original_index
    )
    if unit.anchor_node and (
      not family.anchor_node
      or Core.compare_nodes(unit.anchor_node, family.anchor_node)
    ) then
      family.anchor_node = unit.anchor_node
    end
  end

  for _, family in ipairs(families) do
    family.core_tokens = common_family_core(family.units)
    family.core_info = {
      stem_tokens = family.core_tokens,
      trailing_number = nil,
    }
    table.sort(family.units, function(first, second)
      if first.main_rank ~= second.main_rank then
        return first.main_rank < second.main_rank
      end
      local same_rule = first.anchor_node and second.anchor_node
        and first.anchor_node.id == second.anchor_node.id
      local by_node = node_less(first.anchor_node, second.anchor_node)
      if by_node ~= nil then
        return by_node
      end
      if same_rule then
        if first.rule_relation_rank ~= second.rule_relation_rank then
          return first.rule_relation_rank < second.rule_relation_rank
        end
        local first_number = first.name_info.trailing_number
        local second_number = second.name_info.trailing_number
        if first_number ~= second_number then
          if first_number == nil then
            return true
          elseif second_number == nil then
            return false
          end
          return first_number < second_number
        end
        -- Different visible names on the same rule are synonyms, not a hidden
        -- alphabetical hierarchy. Preserve their project order when neither
        -- has a distinguishing final number.
        return first.original_index < second.original_index
      end
      local first_relation = family_relation_rank(
        first.name_info,
        family.core_tokens
      )
      local second_relation = family_relation_rank(
        second.name_info,
        family.core_tokens
      )
      if first_relation ~= second_relation then
        return first_relation < second_relation
      end

      local first_winner = first.classification.winner
      local second_winner = second.classification.winner
      by_node = node_less(
        first_winner and first_winner.node,
        second_winner and second_winner.node
      )
      if by_node ~= nil then
        return by_node
      end
      if config.settings.natural_name_sort then
        if Core.compare_name_info(first.name_info, second.name_info) then
          return true
        end
        if Core.compare_name_info(second.name_info, first.name_info) then
          return false
        end
      end
      return first.original_index < second.original_index
    end)
  end

  table.sort(families, function(first, second)
    if first.boundary_rank ~= second.boundary_rank then
      return first.boundary_rank < second.boundary_rank
    end
    local by_node = node_less(first.anchor_node, second.anchor_node)
    if by_node ~= nil then
      return by_node
    end
    if config.settings.preserve_relative_order then
      return first.original_index < second.original_index
    end
    if config.settings.natural_name_sort then
      if Core.compare_name_info(first.core_info, second.core_info) then
        return true
      end
      if Core.compare_name_info(second.core_info, first.core_info) then
        return false
      end
    end
    return first.original_index < second.original_index
  end)

  local sorted = {}
  for _, family in ipairs(families) do
    for _, unit in ipairs(family.units) do
      sorted[#sorted + 1] = unit
    end
  end
  for index, unit in ipairs(sorted) do
    group[index] = unit
  end
end

local function classify_units(config, units)
  local groups = {}
  for _, category in ipairs(config.categories) do
    groups[category.id] = {}
  end

  for _, unit in ipairs(units) do
    unit.classification = classify_unit(config, unit)
    local category_id = unit.classification.winner
      and unit.classification.winner.category.id
      or "other"
    unit.category_id = category_id
    groups[category_id] = groups[category_id] or {}
    groups[category_id][#groups[category_id] + 1] = unit
  end

  return groups
end

local function create_folder(node, config)
  local index = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  local name = node.id == "other"
    and config.settings.unknown_folder_name
    or (node.folder ~= "" and node.folder or node.name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_managed_folder_id(track, node.id)
  set_folder_depth(track, 0)
  return track
end

local function numbered_family_folder_name(units)
  local preferred
  for _, unit in ipairs(units) do
    local name = track_name(unit.root):match("^%s*(.-)%s*$")
    if unit.name_info.trailing_number == nil then
      preferred = name
      break
    end
    preferred = preferred or name:gsub("[%s_%-]*%d+%s*$", "")
  end
  return preferred and preferred:match("^%s*(.-)%s*$") or "NUMBERED"
end

local function build_folder_records(config, groups, managed)
  local records = {}
  for _, category in ipairs(config.categories) do
    records[category.id] = {
      node = category,
      units = {},
      children = {},
      total_units = 0,
    }
  end
  for _, rule in ipairs(config.rules) do
    if Core.is_layout_node(rule) then
      records[rule.id] = {
        node = rule,
        units = {},
        children = {},
        total_units = 0,
      }
    end
  end

  for _, record in pairs(records) do
    if record.node.kind == "rule" then
      local parent_record
      local path = record.node.path or {}
      for index = #path - 1, 1, -1 do
        local ancestor = path[index]
        if records[ancestor.id] then
          parent_record = records[ancestor.id]
          break
        end
      end
      if not parent_record then
        error("Folder rule '" .. record.node.id .. "' has no folder parent.")
      end
      record.parent_record = parent_record
      parent_record.children[#parent_record.children + 1] = record
    end
  end

  for _, category in ipairs(config.categories) do
    for _, unit in ipairs(groups[category.id] or {}) do
      local record = records[category.id]
      if unit.classification.winner then
        for _, node in ipairs(unit.classification.winner.node.path or {}) do
          if records[node.id] then
            record = records[node.id]
          end
        end
      end
      record.units[#record.units + 1] = unit
    end
  end

  local function count_units(record)
    local total = #record.units
    for _, child in ipairs(record.children) do
      total = total + count_units(child)
    end
    record.total_units = total
    return total
  end
  for _, category in ipairs(config.categories) do
    count_units(records[category.id])
  end

  local minimum = tonumber(config.settings.subfolder_min_tracks) or 3
  for _, record in pairs(records) do
    record.active = record.node.kind == "category"
      or Core.is_order_group_node(record.node)
      or (
        Core.is_folder_node(record.node)
        and (
          not config.settings.create_folders
          or record.total_units >= minimum
          or managed[record.node.id] ~= nil
        )
      )
    record.units = {}
  end

  -- Reassign tracks after the threshold decision. Tracks from an inactive
  -- configured subfolder bubble up to the nearest active folder ancestor.
  for _, category in ipairs(config.categories) do
    for _, unit in ipairs(groups[category.id] or {}) do
      local record = records[category.id]
      if unit.classification.winner then
        for _, node in ipairs(unit.classification.winner.node.path or {}) do
          local candidate = records[node.id]
          if candidate and candidate.active then
            record = candidate
          end
        end
      end
      record.units[#record.units + 1] = unit
    end
  end

  local numbered_minimum = tonumber(
    config.settings.numbered_family_min_tracks
  ) or 3
  local function add_numbered_families(record)
    sort_group(config, record.units)
    local families = {}
    for _, unit in ipairs(record.units) do
      local stem = unit.name_info.stem
      if stem ~= "" then
        local family = families[stem]
        if not family then
          family = { units = {}, has_number = false }
          families[stem] = family
        end
        family.units[#family.units + 1] = unit
        family.has_number = family.has_number
          or unit.name_info.trailing_number ~= nil
      end
    end

    local moved = {}
    for stem, family in pairs(families) do
      if #family.units >= numbered_minimum and family.has_number then
        local folder_name = numbered_family_folder_name(family.units)
        local id = "dynamic:" .. record.node.id .. ":" .. Core.slug(stem)
        local anchor
        for _, unit in ipairs(family.units) do
          moved[unit] = true
          local winner = unit.classification.winner
          local node = winner and winner.node
          if node and (not anchor or Core.compare_nodes(node, anchor)) then
            anchor = node
          end
        end
        local dynamic = {
          node = {
            kind = "dynamic",
            id = id,
            name = folder_name,
            folder = folder_name,
          },
          anchor_node = anchor,
          boundary_rank = family.units[1].boundary_rank,
          name_info = Core.name_sort_info(
            folder_name,
            config.settings.case_sensitive
          ),
          units = family.units,
          children = {},
          total_units = #family.units,
          active = true,
          dynamic = true,
        }
        records[id] = dynamic
        record.children[#record.children + 1] = dynamic
      end
    end
    if next(moved) then
      local remaining = {}
      for _, unit in ipairs(record.units) do
        if not moved[unit] then
          remaining[#remaining + 1] = unit
        end
      end
      record.units = remaining
    end
    for _, child in ipairs(record.children) do
      if not child.dynamic then
        add_numbered_families(child)
      end
    end
  end
  if config.settings.create_folders then
    for _, category in ipairs(config.categories) do
      add_numbered_families(records[category.id])
    end
  end

  -- A configured wrapper must contain at least two immediate elements after
  -- numbered families have become folders of their own. For example, Hat,
  -- Hat 2, Hat 3 count as one HAT element, so METAL is not created around it.
  -- Existing managed wrappers are retained because Organizer never deletes
  -- tracks that already exist in the project.
  local minimum_elements = tonumber(
    config.settings.subfolder_min_elements
  ) or 2
  local function collapse_small_children(parent)
    local kept = {}
    for _, child in ipairs(parent.children) do
      if not child.dynamic then
        collapse_small_children(child)
      end
      local direct_elements = #child.units
      for _, grandchild in ipairs(child.children) do
        if grandchild.active then
          direct_elements = direct_elements + 1
        end
      end
      local collapse = config.settings.create_folders
        and not child.dynamic
        and child.node.kind == "rule"
        and Core.is_folder_node(child.node)
        and child.active
        and not managed[child.node.id]
        and direct_elements < minimum_elements
      if collapse or not child.active then
        child.active = false
        for _, unit in ipairs(child.units) do
          parent.units[#parent.units + 1] = unit
        end
        for _, grandchild in ipairs(child.children) do
          grandchild.parent_record = parent
          kept[#kept + 1] = grandchild
        end
        child.units = {}
        child.children = {}
      else
        kept[#kept + 1] = child
      end
    end
    parent.children = kept
  end
  for _, category in ipairs(config.categories) do
    collapse_small_children(records[category.id])
  end

  local function finalize(record)
    sort_group(config, record.units)
    table.sort(record.children, function(first, second)
      local first_node = first.anchor_node or first.node
      local second_node = second.anchor_node or second.node
      local by_node = node_less(first_node, second_node)
      if by_node ~= nil then
        return by_node
      end
      return first.node.id < second.node.id
    end)
    local total = #record.units
    for _, child in ipairs(record.children) do
      total = total + finalize(child)
    end
    record.total_units = total
    return total
  end
  for _, category in ipairs(config.categories) do
    finalize(records[category.id])
  end
  return records
end

local function entry_less(first, second)
  -- Unit order has already been resolved by sort_group(), including visible
  -- rule synonyms and natural number suffixes. Do not alphabetize it again
  -- while interleaving child folders.
  if first.kind == "unit" and second.kind == "unit" then
    return first.sequence < second.sequence
  end
  local first_boundary = first.kind == "unit"
    and (first.unit.boundary_rank or 0)
    or (first.record.boundary_rank or 0)
  local second_boundary = second.kind == "unit"
    and (second.unit.boundary_rank or 0)
    or (second.record.boundary_rank or 0)
  if first_boundary ~= second_boundary then
    return first_boundary < second_boundary
  end
  local first_node = first.kind == "folder"
    and (first.record.anchor_node or first.record.node)
    or (first.unit.classification.winner
      and first.unit.classification.winner.node)
  local second_node = second.kind == "folder"
    and (second.record.anchor_node or second.record.node)
    or (second.unit.classification.winner
      and second.unit.classification.winner.node)
  local by_node = node_less(first_node, second_node)
  if by_node ~= nil then
    return by_node
  end
  local first_info = first.kind == "unit"
    and first.unit.name_info
    or first.record.name_info
  local second_info = second.kind == "unit"
    and second.unit.name_info
    or second.record.name_info
  if first_info and second_info then
    if Core.compare_name_info(first_info, second_info) then
      return true
    end
    if Core.compare_name_info(second_info, first_info) then
      return false
    end
  end
  if first.kind ~= second.kind then
    return first.kind == "folder"
  end
  return first.sequence < second.sequence
end

local function select_block(block)
  reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
  for _, track in ipairs(block) do
    reaper.SetTrackSelected(track, true)
  end
end

local function move_blocks_to_end(blocks)
  for _, block in ipairs(blocks) do
    select_block(block)
    reaper.ReorderSelectedTracks(reaper.CountTracks(0), 0)
  end
end

local function validate_folder_depths()
  local running = 0
  local tracks = all_tracks()
  for index, track in ipairs(tracks) do
    running = running + folder_depth(track)
    if running < 0 and index < #tracks then
      return false, "Folder depth closes below project root at track " .. index .. "."
    end
  end
  if running ~= 0 then
    return false, "Final folder depth balance is " .. running .. " instead of 0."
  end
  return true
end

content_free_folder_track = function(track)
  if not reaper.CountTrackMediaItems or not reaper.TrackFX_GetCount
    or not reaper.CountTrackEnvelopes or not reaper.GetTrackNumSends
  then
    return false
  end
  if reaper.CountTrackMediaItems(track) > 0
    or reaper.TrackFX_GetCount(track) > 0
    or reaper.CountTrackEnvelopes(track) > 0
  then
    return false
  end
  if reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(track) > 0 then
    return false
  end
  for _, category in ipairs({ -1, 0, 1 }) do
    if reaper.GetTrackNumSends(track, category) > 0 then
      return false
    end
  end
  return true
end

local function dry_run(config)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg(
    "icss_Track Organizer - DRY RUN\nPreset: "
    .. tostring(ACTIVE_PRESET.name)
    .. " (" .. tostring(ACTIVE_PRESET.filename) .. ")\n\n"
  )
  local managed = {}
  for index, track in ipairs(all_tracks()) do
    local id = managed_folder_id(track)
    local node = id and config.nodes_by_id[id]
    if id and (id:match("^dynamic:") or Core.is_folder_node(node)) then
      managed[id .. ":" .. tostring(index)] = track
    end
  end
  local units = build_atomic_units(managed)
  for _, unit in ipairs(units) do
    local name = track_name(unit.root)
    local result = classify_unit(config, unit)
    reaper.ShowConsoleMsg(
      (unit.is_folder and "Existing folder: \"" or "Track: \"")
      .. name .. "\"\n"
    )
    if result.winner then
      reaper.ShowConsoleMsg(
        "-> " .. Core.path_names(result.winner.node, " / ") .. "\n"
      )
      reaper.ShowConsoleMsg(
        "-> order " .. Core.order_string(result.winner.node)
        .. ", priority " .. result.winner.priority
        .. ", pattern \"" .. result.winner.pattern .. "\"\n"
      )
    else
      reaper.ShowConsoleMsg("-> OTHER\n")
    end
    if unit.is_folder then
      reaper.ShowConsoleMsg("   Folder remains intact.\n")
    end
    if config.settings.debug and #result.matches > 1 then
      reaper.ShowConsoleMsg("   Other matches:\n")
      for match_index = 2, #result.matches do
        local match = result.matches[match_index]
        reaper.ShowConsoleMsg(
          "   - " .. Core.path_names(match.node)
          .. " via \"" .. match.pattern .. "\"\n"
        )
      end
    end
    reaper.ShowConsoleMsg("\n")
  end
end

local function organize(config)
  local selection = snapshot_selection()
  local managed = unwrap_managed_folders(config)
  local units = build_atomic_units(managed)
  local groups = classify_units(config, units)
  local records = build_folder_records(config, groups, managed)
  local orphaned_dynamic = {}
  for id, track in pairs(managed) do
    if id:match("^dynamic:") and not records[id] then
      orphaned_dynamic[#orphaned_dynamic + 1] = { id = id, track = track }
    end
  end
  if #orphaned_dynamic > 0 then
    local other = records.other
    for index, orphan in ipairs(orphaned_dynamic) do
      managed[orphan.id] = nil
      set_managed_folder_id(orphan.track, "")
      other.units[#other.units + 1] = {
        tracks = { orphan.track },
        root = orphan.track,
        original_index = reaper.CountTracks(0) + index,
        is_folder = false,
        category_id = "other",
        classification = {
          winner = nil,
          matches = {},
        },
      }
    end
    sort_group(config, other.units)
    other.total_units = other.total_units + #orphaned_dynamic
  end
  local blocks = {}
  local folder_records = {}

  local function emit_record(record)
    local node = record.node
    local needs_folder = record.total_units > 0
      and record.active
      and config.settings.create_folders
      and Core.is_folder_node(node)
    local folder = managed[node.id]
    if needs_folder and not folder then
      folder = create_folder(node, config)
      managed[node.id] = folder
    end
    if folder then
      blocks[#blocks + 1] = { folder }
    end

    local entries = {}
    for index, unit in ipairs(record.units) do
      entries[#entries + 1] = {
        kind = "unit",
        unit = unit,
        sequence = index,
      }
    end
    for index, child in ipairs(record.children) do
      if child.total_units > 0 or managed[child.node.id] then
        entries[#entries + 1] = {
          kind = "folder",
          record = child,
          sequence = #record.units + index,
        }
      end
    end
    table.sort(entries, entry_less)

    local last_track = folder
    for _, entry in ipairs(entries) do
      if entry.kind == "unit" then
        blocks[#blocks + 1] = entry.unit.tracks
        last_track = entry.unit.tracks[#entry.unit.tracks]
      else
        local child_last = emit_record(entry.record)
        last_track = child_last or last_track
      end
    end

    if needs_folder and folder and last_track and last_track ~= folder then
      folder_records[#folder_records + 1] = {
        folder = folder,
        last_track = last_track,
      }
    end
    return last_track
  end

  for _, category in ipairs(config.categories) do
    emit_record(records[category.id])
  end

  move_blocks_to_end(blocks)

  for _, record in ipairs(folder_records) do
    set_folder_depth(record.folder, 1)
    set_folder_depth(
      record.last_track,
      folder_depth(record.last_track) - 1
    )
  end

  local valid, folder_error = validate_folder_depths()
  if not valid then
    error(folder_error)
  end

  restore_selection(selection)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local config, config_errors = Core.load_config(CONFIG_PATH)
if not config then
  show_error(table.concat(config_errors or { "Unknown config error." }, "\n"))
  return
end

if config.settings.unknown_tracks ~= "folder" then
  show_error(
    "This version requires unknown_tracks=folder so unclassified tracks "
    .. "always end inside OTHER."
  )
  return
end

if config.settings.dry_run then
  dry_run(config)
  return
end

if reaper.CountTracks(0) == 0 then
  show_error("The project has no tracks to organize.")
  return
end

reaper.Undo_BeginBlock2(0)
reaper.PreventUIRefresh(1)
local ok, error_message = xpcall(function()
  organize(config)
end, debug.traceback)
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock2(0, "icss_Track Organizer", -1)

if not ok then
  reaper.Undo_DoUndo2(0)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  show_error(
    "Organizer stopped and rolled back the project:\n\n"
    .. tostring(error_message)
  )
end
