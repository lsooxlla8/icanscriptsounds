-- @description New Track Copies
-- @author icanseesounds
-- @version 1.0.0
-- @changelog
--   Initial version
-- @provides
--   [main] icss_Duplicate to New Copy of a Track.lua
--   [main] icss_Move to New Copy of a Track.lua
-- @about
--   Provides three actions for placing selected material on new copies of its
--   source tracks.
--
--   * Duplicate to New Copy of a Track and Move to 0.00 copies the material
--     and shifts the result so its earliest point is at 0.00.
--   * Duplicate to New Copy of a Track copies the material at its original
--     timeline position.
--   * Move to New Copy of a Track moves the original material at its original
--     timeline position.
--
--   Razor Edits take priority over selected media items. Media-item Razor
--   Edits process only material inside their boundaries; envelope Razor Edits
--   are ignored. Without Razor Edits, selected items are processed in full.
--
--   * New tracks keep the source track settings and use minimum height.

local options = rawget(_G, "ICSS_NEW_TRACK_COPY_OPTIONS") or {
  operation = "copy",
  move_to_zero = true,
  undo_description =
    "Duplicate to new copy of a track and move to 0.00",
}
_G.ICSS_NEW_TRACK_COPY_OPTIONS = nil

local PROJECT = 0
local EPSILON = 0.0000001
local DUPLICATE_TRACKS_COMMAND = 40062

local function get_track_number(track)
  return math.floor(
    reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  )
end

local function add_unique_track(tracks, seen_tracks, track)
  if track and not seen_tracks[track] then
    seen_tracks[track] = true
    tracks[#tracks + 1] = track
  end
end

local function clear_track_items(track)
  for index = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, index)
    reaper.DeleteTrackMediaItem(track, item)
  end
end

local function clear_track_razor_edits(track)
  reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
  reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS_EXT", "", true)
end

local function get_razor_areas(track)
  local areas = {}
  local _, extended = reaper.GetSetMediaTrackInfo_String(
    track,
    "P_RAZOREDITS_EXT",
    "",
    false
  )

  if extended and extended ~= "" then
    local pattern = '([%+%-%.%deE]+)%s+([%+%-%.%deE]+)%s+' ..
      '"(.-)"%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)'

    for start_text, end_text, guid, top_text, bottom_text in
      extended:gmatch(pattern)
    do
      local start_position = tonumber(start_text)
      local end_position = tonumber(end_text)

      if start_position and end_position then
        areas[#areas + 1] = {
          start_position = start_position,
          end_position = end_position,
          guid = guid,
          top = tonumber(top_text) or 0,
          bottom = tonumber(bottom_text) or 1,
        }
      end
    end

    if #areas > 0 then
      return areas
    end
  end

  local _, legacy = reaper.GetSetMediaTrackInfo_String(
    track,
    "P_RAZOREDITS",
    "",
    false
  )

  if legacy and legacy ~= "" then
    local pattern = '([%+%-%.%deE]+)%s+([%+%-%.%deE]+)%s+"(.-)"'

    for start_text, end_text, guid in legacy:gmatch(pattern) do
      local start_position = tonumber(start_text)
      local end_position = tonumber(end_text)

      if start_position and end_position then
        areas[#areas + 1] = {
          start_position = start_position,
          end_position = end_position,
          guid = guid,
          top = 0,
          bottom = 1,
        }
      end
    end
  end

  return areas
end

local function item_intersects_area(item, area)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_length

  if item_end <= area.start_position + EPSILON or
      item_start >= area.end_position - EPSILON then
    return false
  end

  local item_top = reaper.GetMediaItemInfo_Value(item, "F_FREEMODE_Y")
  local item_height = reaper.GetMediaItemInfo_Value(item, "F_FREEMODE_H")

  if item_height <= 0 then
    item_top = 0
    item_height = 1
  end

  local item_bottom = item_top + item_height
  return item_bottom > area.top + EPSILON and
    item_top < area.bottom - EPSILON
end

local function get_item_ranges(item, areas)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end = item_start +
    reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local ranges = {}

  for _, area in ipairs(areas) do
    if item_intersects_area(item, area) then
      ranges[#ranges + 1] = {
        start_position = math.max(item_start, area.start_position),
        end_position = math.min(item_end, area.end_position),
      }
    end
  end

  table.sort(ranges, function(first, second)
    return first.start_position < second.start_position
  end)

  local merged_ranges = {}
  for _, range in ipairs(ranges) do
    local previous = merged_ranges[#merged_ranges]

    if previous and range.start_position <=
        previous.end_position + EPSILON then
      previous.end_position = math.max(
        previous.end_position,
        range.end_position
      )
    else
      merged_ranges[#merged_ranges + 1] = range
    end
  end

  return merged_ranges
end

local function regenerate_item_guids(chunk)
  if not reaper.genGuid then
    return chunk
  end

  chunk = chunk:gsub(
    "([\r\n]%s*IGUID%s+)%b{}",
    function(prefix)
      return prefix .. reaper.genGuid()
    end
  )

  return chunk:gsub(
    "([\r\n]%s*GUID%s+)%b{}",
    function(prefix)
      return prefix .. reaper.genGuid()
    end
  )
end

local function clone_item(source_item, destination_track)
  local success, chunk = reaper.GetItemStateChunk(source_item, "", false)
  if not success then
    return nil
  end

  local new_item = reaper.AddMediaItemToTrack(destination_track)
  if not new_item then
    return nil
  end

  chunk = regenerate_item_guids(chunk)
  if not reaper.SetItemStateChunk(new_item, chunk, false) then
    reaper.DeleteTrackMediaItem(destination_track, new_item)
    return nil
  end

  return new_item
end


local function crop_item_to_range(
    item,
    track,
    range_start,
    range_end
)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end = item_start +
    reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  if range_end < item_end - EPSILON then
    local right = reaper.SplitMediaItem(item, range_end)
    if not right then
      reaper.DeleteTrackMediaItem(track, item)
      return nil
    end
    reaper.DeleteTrackMediaItem(track, right)
  end

  if range_start > item_start + EPSILON then
    local middle = reaper.SplitMediaItem(item, range_start)
    if not middle then
      reaper.DeleteTrackMediaItem(track, item)
      return nil
    end
    reaper.DeleteTrackMediaItem(track, item)
    item = middle
  end

  return item
end

local function move_item_range(
    item,
    destination_track,
    range_start,
    range_end
)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end = item_start +
    reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  if range_end < item_end - EPSILON and
      not reaper.SplitMediaItem(item, range_end) then
    return nil
  end

  local segment = item
  if range_start > item_start + EPSILON then
    segment = reaper.SplitMediaItem(item, range_start)
    if not segment then
      return nil
    end
  end

  if not reaper.MoveMediaItemToTrack(segment, destination_track) then
    return nil
  end

  return segment
end

local function deselect_all_tracks()
  for index = 0, reaper.CountTracks(PROJECT) - 1 do
    local track = reaper.GetTrack(PROJECT, index)
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 0)
  end
end

local function duplicate_empty_track(source_track)
  local source_number = get_track_number(source_track)
  local track_count_before = reaper.CountTracks(PROJECT)

  deselect_all_tracks()
  reaper.SetMediaTrackInfo_Value(source_track, "I_SELECTED", 1)
  reaper.Main_OnCommand(DUPLICATE_TRACKS_COMMAND, 0)

  if reaper.CountTracks(PROJECT) <= track_count_before then
    return nil
  end

  local duplicate = reaper.GetTrack(PROJECT, source_number)
  if not duplicate then
    return nil
  end

  clear_track_items(duplicate)
  clear_track_razor_edits(duplicate)
  reaper.SetMediaTrackInfo_Value(duplicate, "I_SOLO", 0)
  reaper.SetMediaTrackInfo_Value(duplicate, "B_HEIGHTLOCK", 0)
  reaper.SetMediaTrackInfo_Value(duplicate, "I_HEIGHTOVERRIDE", 1)
  return duplicate
end

local function collect_input()
  local razor_mode = false
  local razor_areas_by_track = {}
  local source_tracks = {}
  local seen_tracks = {}
  local selected_items = {}
  local global_start = math.huge

  for index = 0, reaper.CountTracks(PROJECT) - 1 do
    local track = reaper.GetTrack(PROJECT, index)
    if #get_razor_areas(track) > 0 then
      razor_mode = true
      break
    end
  end

  if razor_mode then
    for index = 0, reaper.CountTracks(PROJECT) - 1 do
      local track = reaper.GetTrack(PROJECT, index)
      local media_areas = {}

      for _, area in ipairs(get_razor_areas(track)) do
        if area.guid == "" then
          media_areas[#media_areas + 1] = area
          global_start = math.min(global_start, area.start_position)
        end
      end

      if #media_areas > 0 then
        add_unique_track(source_tracks, seen_tracks, track)
        razor_areas_by_track[track] = media_areas
      end
    end
  else
    for index = 0, reaper.CountSelectedMediaItems(PROJECT) - 1 do
      local item = reaper.GetSelectedMediaItem(PROJECT, index)
      local track = reaper.GetMediaItemTrack(item)
      selected_items[#selected_items + 1] = item
      add_unique_track(source_tracks, seen_tracks, track)
      global_start = math.min(
        global_start,
        reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      )
    end
  end

  return {
    razor_mode = razor_mode,
    razor_areas_by_track = razor_areas_by_track,
    source_tracks = source_tracks,
    selected_items = selected_items,
    global_start = global_start,
  }
end

local function process_razor_items(input, destination_by_source, new_items)
  for _, source_track in ipairs(input.source_tracks) do
    local destination_track = destination_by_source[source_track]
    local areas = input.razor_areas_by_track[source_track]

    if destination_track and areas then
      local source_items = {}
      for index = 0, reaper.CountTrackMediaItems(source_track) - 1 do
        source_items[#source_items + 1] =
          reaper.GetTrackMediaItem(source_track, index)
      end

      for _, source_item in ipairs(source_items) do
        local ranges = get_item_ranges(source_item, areas)

        for index = #ranges, 1, -1 do
          local range = ranges[index]
          local result

          if options.operation == "move" then
            result = move_item_range(
              source_item,
              destination_track,
              range.start_position,
              range.end_position
            )
          else
            result = clone_item(source_item, destination_track)
            if result then
              result = crop_item_to_range(
                result,
                destination_track,
                range.start_position,
                range.end_position
              )
            end
          end

          if result then
            new_items[#new_items + 1] = result
          end
        end
      end
    end
  end
end

local function process_selected_items(
    input,
    destination_by_source,
    new_items
)
  for _, source_item in ipairs(input.selected_items) do
    local source_track = reaper.GetMediaItemTrack(source_item)
    local destination_track = destination_by_source[source_track]
    local result

    if destination_track then
      if options.operation == "move" then
        if reaper.MoveMediaItemToTrack(source_item, destination_track) then
          result = source_item
        end
      else
        result = clone_item(source_item, destination_track)
      end
    end

    if result then
      new_items[#new_items + 1] = result
    end
  end
end

local function main()
  local input = collect_input()
  if #input.source_tracks == 0 or input.global_start == math.huge then
    return
  end

  reaper.Undo_BeginBlock2(PROJECT)
  reaper.PreventUIRefresh(1)

  table.sort(input.source_tracks, function(first, second)
    return get_track_number(first) > get_track_number(second)
  end)

  local destination_by_source = {}
  local destination_tracks = {}

  for _, source_track in ipairs(input.source_tracks) do
    local duplicate = duplicate_empty_track(source_track)
    if duplicate then
      destination_by_source[source_track] = duplicate
      destination_tracks[#destination_tracks + 1] = duplicate
    end
  end

  local new_items = {}
  if input.razor_mode then
    process_razor_items(input, destination_by_source, new_items)
  else
    process_selected_items(input, destination_by_source, new_items)
  end

  if options.move_to_zero then
    for _, item in ipairs(new_items) do
      local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      reaper.SetMediaItemInfo_Value(
        item,
        "D_POSITION",
        position - input.global_start
      )
    end
  end

  deselect_all_tracks()
  for _, track in ipairs(destination_tracks) do
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 1)
  end

  for _, item in ipairs(new_items) do
    reaper.SetMediaItemInfo_Value(item, "B_UISEL", 1)
  end

  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(PROJECT, options.undo_description, -1)
end

main()
