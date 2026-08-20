-- @description Prepare Selected Items for Mastering
-- @author icanseesounds
-- @version 1.4.0
-- @changelog
--   Support MIDI, generated-source, and empty selected items
-- @about
--   Prepares selected items for batch mastering.
--
--   * Orders standalone tracks and folder groups from top to bottom.
--   * Aligns selected items in the same nearest folder at one start position.
--   * Places each following block immediately after the longest item before it.
--   * Treats multiple selected items on one track as one continuous block.
--   * Creates one selected region and render-matrix entry per selected track.
--   * Renders every selected track separately through its routing and master.
--   * Preserves multichannel sources and enables multichannel peak meters.
--   * Renames regions and item tracks from the best available item name.
--   * Deletes existing regions before creating the current region set.
--   * Separates overlapping folder regions into ruler lanes.
--   * Colors tracks with global and per-folder gradients.
--   * Gives each region the custom color of its source track.
--
--   Requires REAPER 7.78 or later.

local SCRIPT_NAME = "Prepare Selected Items for Mastering"
local UNDO_DESCRIPTION = "Prepare selected items for mastering"

local RENDER_MATRIX_FLAG = 8
local RENDER_VIA_MASTER_FLAG = 128
local EMBED_METADATA_FLAG = 512
local MULTICHANNEL_TRACKS_FLAG = 4
local DISABLE_POSTPROCESSING_FLAG = 262144

local WAV_24_BIT_BWF_CONFIG = "ZXZhdxgAAQ=="
local MAX_RULER_LANES = 48
local CUSTOM_COLOR_FLAG = 0x1000000

local function has_flag(value, flag)
  return math.floor(value / flag) % 2 == 1
end

local function add_flag(value, flag)
  if has_flag(value, flag) then
    return value
  end
  return value + flag
end

local function show_error(message)
  reaper.ShowMessageBox(message, SCRIPT_NAME, 0)
end

local function clean_filename(path)
  local filename = path:match("([^/\\]+)$") or path
  local name = filename:gsub("%.[^%.]+$", "")
  name = name:gsub("%s+", " ")
  name = name:match("^%s*(.-)%s*$") or ""
  return name
end

local function clean_name(value)
  value = tostring(value or "")
  value = value:gsub("%s+", " ")
  return value:match("^%s*(.-)%s*$") or ""
end

local function get_track_name(track)
  local _, name = reaper.GetTrackName(track)
  return clean_name(name)
end

local function get_item_name(item, take, source, track, item_number)
  if source then
    local source_path = reaper.GetMediaSourceFileName(source)
    if source_path and source_path ~= "" then
      local source_name = clean_filename(source_path)
      if source_name ~= "" then
        return source_name
      end
    end
  end

  if take then
    local _, take_name = reaper.GetSetMediaItemTakeInfo_String(
      take,
      "P_NAME",
      "",
      false
    )
    take_name = clean_name(take_name)
    if take_name ~= "" then
      return take_name
    end
  end

  local _, item_notes = reaper.GetSetMediaItemInfo_String(
    item,
    "P_NOTES",
    "",
    false
  )
  item_notes = clean_name(item_notes)
  if item_notes ~= "" then
    return item_notes
  end

  local track_name = get_track_name(track)
  if track_name ~= "" then
    return track_name
  end

  return "Item " .. tostring(item_number)
end

local function get_root_source(take)
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    return nil
  end

  local visited = {}
  while source and not visited[source] do
    visited[source] = true
    local parent = reaper.GetMediaSourceParent(source)
    if not parent then
      break
    end
    source = parent
  end

  return source
end

local function copy_array(values)
  local result = {}
  for index, value in ipairs(values) do
    result[index] = value
  end
  return result
end

local function collect_track_metadata()
  local metadata = {}
  local folder_stack = {}
  local ordered_tracks = {}

  for index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, index)
    local folder_depth = math.floor(
      reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    )

    metadata[track] = {
      index = index,
      is_folder = folder_depth > 0,
      parents = copy_array(folder_stack),
      descendants = {},
    }
    ordered_tracks[#ordered_tracks + 1] = track

    if folder_depth > 0 then
      for _ = 1, folder_depth do
        folder_stack[#folder_stack + 1] = track
      end
    elseif folder_depth < 0 then
      for _ = 1, -folder_depth do
        folder_stack[#folder_stack] = nil
      end
    end
  end

  for _, track in ipairs(ordered_tracks) do
    for _, parent_track in ipairs(metadata[track].parents) do
      local parent_metadata = metadata[parent_track]
      parent_metadata.descendants[#parent_metadata.descendants + 1] = track
    end
  end

  metadata.ordered_tracks = ordered_tracks

  return metadata
end

local function hsv_to_rgb(hue, saturation, value)
  hue = hue % 1
  local sector = math.floor(hue * 6)
  local fraction = hue * 6 - sector
  local p = value * (1 - saturation)
  local q = value * (1 - fraction * saturation)
  local t = value * (1 - (1 - fraction) * saturation)

  local red
  local green
  local blue

  if sector == 0 then
    red, green, blue = value, t, p
  elseif sector == 1 then
    red, green, blue = q, value, p
  elseif sector == 2 then
    red, green, blue = p, value, t
  elseif sector == 3 then
    red, green, blue = p, q, value
  elseif sector == 4 then
    red, green, blue = t, p, value
  else
    red, green, blue = value, p, q
  end

  return math.floor(red * 255 + 0.5),
    math.floor(green * 255 + 0.5),
    math.floor(blue * 255 + 0.5)
end

local function set_track_hsv_color(track, hue, saturation)
  local red, green, blue = hsv_to_rgb(hue, saturation, 1)
  local color = reaper.ColorToNative(red, green, blue)
    + CUSTOM_COLOR_FLAG
  reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", color)
end

local function color_all_tracks(track_metadata)
  local tracks = track_metadata.ordered_tracks
  local track_count = #tracks

  for index, track in ipairs(tracks) do
    local hue = 0
    if track_count > 1 then
      hue = (index - 1) / (track_count - 1)
    end
    track_metadata[track].global_hue = hue
    set_track_hsv_color(track, hue, 1)
  end

  -- Outer folders are colored first. A nested folder then replaces the colors
  -- in its own subtree with a separate saturation gradient.
  for _, folder_track in ipairs(tracks) do
    local folder_metadata = track_metadata[folder_track]
    if folder_metadata.is_folder then
      local folder_tracks = { folder_track }
      for _, descendant in ipairs(folder_metadata.descendants) do
        folder_tracks[#folder_tracks + 1] = descendant
      end

      for index, track in ipairs(folder_tracks) do
        local saturation = 1
        if #folder_tracks > 1 then
          saturation = 1 - (index - 1) / (#folder_tracks - 1)
        end
        set_track_hsv_color(
          track,
          folder_metadata.global_hue,
          saturation
        )
      end
    end
  end
end

local function allocate_unique_name(base_name, used_names)
  local name = base_name
  local number = 2

  while used_names[name] do
    name = base_name .. " " .. tostring(number)
    number = number + 1
  end

  used_names[name] = true
  return name
end

local function collect_selected_items(track_metadata)
  local item_count = reaper.CountSelectedMediaItems(0)
  if item_count == 0 then
    return nil, "Select at least one item."
  end

  local items = {}
  local blocks_by_track = {}
  local anchor_position

  for index = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, index)
    local track = reaper.GetMediaItemTrack(item)
    local metadata = track_metadata[track]

    if not metadata then
      return nil, "Could not resolve a selected item's track."
    end

    local lock_flags = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
    if has_flag(lock_flags, 1) then
      return nil, "Unlock all selected items before running the script."
    end

    local take = reaper.GetActiveTake(item)
    local source = take and get_root_source(take) or nil
    local base_name = get_item_name(
      item,
      take,
      source,
      track,
      index + 1
    )

    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if length <= 0 then
      return nil, "Every selected item must have a positive length."
    end

    local source_channels = source and math.max(
      0,
      math.floor(tonumber(reaper.GetMediaSourceNumChannels(source)) or 0)
    ) or 0

    local track_channels = math.floor(
      reaper.GetMediaTrackInfo_Value(track, "I_NCHAN")
    )
    local block = blocks_by_track[track]
    if not block then
      local nearest_parent = metadata.parents[#metadata.parents]
      local group_key = track
      if not metadata.is_folder and nearest_parent then
        group_key = nearest_parent
      end

      block = {
        selected_items = {},
        track = track,
        track_index = metadata.index,
        parents = metadata.parents,
        group_key = group_key,
        position = position,
        end_position = position + length,
        naming_position = position,
        base_name = base_name,
        render_channels = math.max(
          2,
          source_channels,
          track_channels
        ),
      }
      blocks_by_track[track] = block
      items[#items + 1] = block
    else
      block.position = math.min(block.position, position)
      block.end_position = math.max(
        block.end_position,
        position + length
      )
      block.render_channels = math.max(
        block.render_channels,
        source_channels,
        track_channels
      )

      if position < block.naming_position then
        block.naming_position = position
        block.base_name = base_name
      end
    end

    block.selected_items[#block.selected_items + 1] = {
      item = item,
      position = position,
    }

    anchor_position = math.min(anchor_position or position, position)
  end

  for _, block in ipairs(items) do
    block.length = block.end_position - block.position
  end

  table.sort(items, function(left, right)
    return left.track_index < right.track_index
  end)

  return items, nil, anchor_position
end

local function move_track_block(block, new_position)
  for _, selected_item in ipairs(block.selected_items) do
    reaper.SetMediaItemPosition(
      selected_item.item,
      new_position + selected_item.position - block.position,
      false
    )
  end
end

local function build_groups(items)
  local groups_by_key = {}
  local groups = {}

  for _, item_data in ipairs(items) do
    local group = groups_by_key[item_data.group_key]
    if not group then
      group = {
        items = {},
        first_track_index = item_data.track_index,
        length = 0,
      }
      groups_by_key[item_data.group_key] = group
      groups[#groups + 1] = group
    end

    group.items[#group.items + 1] = item_data
    group.first_track_index = math.min(
      group.first_track_index,
      item_data.track_index
    )
    group.length = math.max(group.length, item_data.length)
  end

  table.sort(groups, function(left, right)
    return left.first_track_index < right.first_track_index
  end)

  return groups
end

local function get_required_ruler_lane_count(groups)
  local required_lane_count = 1

  for _, group in ipairs(groups) do
    required_lane_count = math.max(
      required_lane_count,
      #group.items
    )
  end

  return required_lane_count
end

local function ensure_ruler_lane_count(required_lane_count)
  local current_lane_count = math.floor(
    reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
  )

  if current_lane_count < required_lane_count then
    reaper.GetSetProjectInfo(
      0,
      "RULER_LANE_COUNT",
      required_lane_count,
      true
    )
  end

  local updated_lane_count = math.floor(
    reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
  )
  if updated_lane_count < required_lane_count then
    return false
  end

  for lane_index = 0, required_lane_count - 1 do
    reaper.GetSetProjectInfo(
      0,
      "RULER_LANE_HIDDEN:" .. tostring(lane_index),
      0,
      true
    )
  end

  local function count_visible_lanes()
    local visible_lane_count = 0
    for lane_index = 0, required_lane_count - 1 do
      local is_visible = reaper.GetSetProjectInfo(
        0,
        "RULER_LANE_VISIBLE:" .. tostring(lane_index),
        0,
        false
      )
      if is_visible > 0.5 then
        visible_lane_count = visible_lane_count + 1
      end
    end
    return visible_lane_count
  end

  local visible_lane_count = count_visible_lanes()
  local ruler_height = math.floor(
    reaper.GetSetProjectInfo(0, "RULER_HEIGHT", 0, false)
  )

  for _ = 1, required_lane_count do
    if visible_lane_count >= required_lane_count then
      return true
    end

    local pixels_per_visible_lane = math.max(
      24,
      math.ceil(ruler_height / math.max(1, visible_lane_count))
    )
    ruler_height = ruler_height
      + pixels_per_visible_lane
        * (required_lane_count - visible_lane_count)

    reaper.GetSetProjectInfo(
      0,
      "RULER_HEIGHT",
      ruler_height,
      true
    )
    reaper.UpdateTimeline()
    visible_lane_count = count_visible_lanes()
  end

  return visible_lane_count >= required_lane_count
end

local function set_multichannel_peak_meter(track)
  local vu_mode = math.floor(
    reaper.GetMediaTrackInfo_Value(track, "I_VUMODE")
  )
  local display_mode = math.floor(vu_mode / 2) % 16 * 2
  reaper.SetMediaTrackInfo_Value(
    track,
    "I_VUMODE",
    vu_mode - display_mode + 2
  )
end

local function even_channel_count(channel_count)
  return math.max(2, math.ceil(channel_count / 2) * 2)
end

local function ensure_track_channels(track, render_channels, is_master)
  local required_channels = even_channel_count(render_channels)
  local current_channels = math.floor(
    reaper.GetMediaTrackInfo_Value(track, "I_NCHAN")
  )

  if current_channels < required_channels then
    reaper.SetMediaTrackInfo_Value(
      track,
      "I_NCHAN",
      required_channels
    )
    current_channels = required_channels
  end

  if render_channels > 2 or current_channels > 2 then
    set_multichannel_peak_meter(track)
  end

  if not is_master and render_channels > 2 then
    reaper.SetMediaTrackInfo_Value(track, "C_MAINSEND_NCH", 0)
  end
end

local function get_maximum_master_channels(items)
  local maximum_channels = 2

  for _, item_data in ipairs(items) do
    maximum_channels = math.max(
      maximum_channels,
      item_data.render_channels
    )

    for _, parent_track in ipairs(item_data.parents) do
      maximum_channels = math.max(
        maximum_channels,
        math.floor(
          reaper.GetMediaTrackInfo_Value(parent_track, "I_NCHAN")
        )
      )
    end
  end

  return even_channel_count(maximum_channels)
end

local function configure_master_channels(master_track, channel_count)
  reaper.SetMediaTrackInfo_Value(
    master_track,
    "I_NCHAN",
    channel_count
  )

  if channel_count > 2 then
    set_multichannel_peak_meter(master_track)
  end
end

local function delete_all_regions()
  for index = reaper.GetNumRegionsOrMarkers(0) - 1, 0, -1 do
    local region_or_marker = reaper.GetRegionOrMarker(0, index, "")
    if region_or_marker
        and reaper.GetRegionOrMarkerInfo_Value(
          0,
          region_or_marker,
          "B_ISREGION"
        ) > 0.5 then
      if not reaper.DeleteProjectMarkerByIndex(0, index) then
        return false
      end
    end
  end

  return true
end

local function find_r8brain_resample_mode()
  for mode = 0, 128 do
    local name = reaper.Resample_EnumModes(mode)
    if name and name:lower():find("r8brain", 1, true) then
      return mode
    end
  end

  return nil
end

local function configure_render_settings(resample_mode)
  local render_settings = RENDER_MATRIX_FLAG
    + RENDER_VIA_MASTER_FLAG
    + EMBED_METADATA_FLAG
    + MULTICHANNEL_TRACKS_FLAG

  reaper.GetSetProjectInfo(
    0,
    "RENDER_SETTINGS",
    render_settings,
    true
  )
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 5, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_TAILFLAG", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_DITHER", 0, true)

  local normalize_settings = math.floor(
    reaper.GetSetProjectInfo(0, "RENDER_NORMALIZE", 0, false)
  )
  normalize_settings = add_flag(
    normalize_settings,
    DISABLE_POSTPROCESSING_FLAG
  )
  reaper.GetSetProjectInfo(
    0,
    "RENDER_NORMALIZE",
    normalize_settings,
    true
  )

  reaper.GetSetProjectInfo_String(
    0,
    "RENDER_PATTERN",
    "$region",
    true
  )
  reaper.GetSetProjectInfo_String(
    0,
    "RENDER_FORMAT",
    WAV_24_BIT_BWF_CONFIG,
    true
  )
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT2", "", true)
  local resample_result = reaper.set_config_var_string(
    "projrenderresample",
    tostring(resample_mode),
    0
  )
  return resample_result ~= 0
end

local function main()
  if not reaper.AddRegionOrMarker
      or not reaper.DeleteProjectMarkerByIndex
      or not reaper.GetRegionOrMarker
      or not reaper.SetRegionOrMarkerInfo_Value
      or not reaper.ColorToNative
      or not reaper.Resample_EnumModes
      or not reaper.UpdateTimeline
      or not reaper.set_config_var_string then
    show_error("This script requires REAPER 7.78 or later.")
    return
  end

  local track_metadata = collect_track_metadata()
  local items, error_message, anchor_position =
    collect_selected_items(track_metadata)
  if not items then
    show_error(error_message)
    return
  end

  local resample_mode = find_r8brain_resample_mode()
  if not resample_mode then
    show_error("REAPER could not find the r8brain-free resample mode.")
    return
  end

  local used_names = {}
  for _, item_data in ipairs(items) do
    item_data.name = allocate_unique_name(
      item_data.base_name,
      used_names
    )
  end

  local groups = build_groups(items)
  local required_lane_count = get_required_ruler_lane_count(groups)
  if required_lane_count > MAX_RULER_LANES then
    show_error(
      "This selection needs " .. tostring(required_lane_count)
        .. " ruler lanes, but REAPER supports up to "
        .. tostring(MAX_RULER_LANES) .. "."
    )
    return
  end

  local position = anchor_position
  for _, group in ipairs(groups) do
    group.position = position
    position = position + group.length
  end

  reaper.Undo_BeginBlock2(0)

  if not delete_all_regions() then
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("REAPER could not delete the existing project regions.")
    return
  end

  color_all_tracks(track_metadata)

  if not ensure_ruler_lane_count(required_lane_count) then
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("REAPER could not display the required ruler lanes.")
    return
  end

  reaper.PreventUIRefresh(1)

  local master_track = reaper.GetMasterTrack(0)
  configure_master_channels(
    master_track,
    get_maximum_master_channels(items)
  )

  for _, group in ipairs(groups) do
    for lane_index, item_data in ipairs(group.items) do
      move_track_block(item_data, group.position)

      reaper.GetSetMediaTrackInfo_String(
        item_data.track,
        "P_NAME",
        item_data.name,
        true
      )

      ensure_track_channels(
        item_data.track,
        item_data.render_channels,
        false
      )
      for _, parent_track in ipairs(item_data.parents) do
        ensure_track_channels(
          parent_track,
          item_data.render_channels,
          false
        )
      end
      local region = reaper.AddRegionOrMarker(
        0,
        true,
        group.position,
        group.position + item_data.length,
        item_data.name,
        -1,
        math.floor(
          reaper.GetMediaTrackInfo_Value(
            item_data.track,
            "I_CUSTOMCOLOR"
          )
        )
      )

      if not region then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
        show_error("REAPER could not create a project region.")
        return
      end

      reaper.SetRegionOrMarkerInfo_Value(0, region, "B_UISEL", 1)
      reaper.SetRegionOrMarkerInfo_Value(
        0,
        region,
        "I_LANENUMBER",
        lane_index - 1
      )

      local region_number = math.floor(
        reaper.GetRegionOrMarkerInfo_Value(0, region, "I_NUMBER")
      )
      reaper.SetRegionRenderMatrix(
        0,
        region_number,
        item_data.track,
        item_data.render_channels * 2
      )
    end
  end

  if not configure_render_settings(resample_mode) then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("REAPER could not set the r8brain-free resample mode.")
    return
  end

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
end

main()
