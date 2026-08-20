-- @noindex

local script_to_test = assert(arg[1], "Pass the script path to test")
local scenario = assert(arg[2], "Pass the test scenario")

local tracks
local next_guid

local function make_item(track, position, length, selected)
  local item = {
    track = track,
    position = position,
    length = length,
    selected = selected or false,
    top = 0,
    height = 1,
  }
  track.items[#track.items + 1] = item
  return item
end

local function make_track(razor_edits)
  local track = {
    items = {},
    selected = false,
    razor_edits = razor_edits or "",
    height = 0,
    solo = 0,
  }
  tracks[#tracks + 1] = track
  return track
end

local function find_item_index(track, item)
  for index, candidate in ipairs(track.items) do
    if candidate == item then
      return index
    end
  end
  return nil
end

local function copy_track(source)
  local duplicate = make_track(source.razor_edits)
  duplicate.selected = true
  duplicate.height = source.height
  duplicate.solo = source.solo

  for _, item in ipairs(source.items) do
    make_item(duplicate, item.position, item.length, item.selected)
  end

  return duplicate
end

local function reset()
  tracks = {}
  next_guid = 0
end

reaper = {}

function reaper.CountTracks()
  return #tracks
end

function reaper.GetTrack(_, index)
  return tracks[index + 1]
end

function reaper.GetMediaTrackInfo_Value(track, parameter)
  if parameter == "IP_TRACKNUMBER" then
    return assert(find_item_index({ items = tracks }, track))
  elseif parameter == "I_SELECTED" then
    return track.selected and 1 or 0
  elseif parameter == "I_SOLO" then
    return track.solo
  elseif parameter == "I_HEIGHTOVERRIDE" then
    return track.height
  end
  return 0
end

function reaper.SetMediaTrackInfo_Value(track, parameter, value)
  if parameter == "I_SELECTED" then
    track.selected = value == 1
  elseif parameter == "I_SOLO" then
    track.solo = value
  elseif parameter == "I_HEIGHTOVERRIDE" then
    track.height = value
  end
end

function reaper.CountTrackMediaItems(track)
  return #track.items
end

function reaper.GetTrackMediaItem(track, index)
  return track.items[index + 1]
end

function reaper.DeleteTrackMediaItem(track, item)
  local index = find_item_index(track, item)
  if index then
    table.remove(track.items, index)
    return true
  end
  return false
end

function reaper.GetSetMediaTrackInfo_String(track, parameter, value, set_new)
  if set_new then
    if parameter == "P_RAZOREDITS" or parameter == "P_RAZOREDITS_EXT" then
      track.razor_edits = value
    end
    return true, value
  end

  if parameter == "P_RAZOREDITS_EXT" then
    return true, track.razor_edits
  end
  return true, ""
end

function reaper.GetMediaItemInfo_Value(item, parameter)
  if parameter == "D_POSITION" then
    return item.position
  elseif parameter == "D_LENGTH" then
    return item.length
  elseif parameter == "F_FREEMODE_Y" then
    return item.top
  elseif parameter == "F_FREEMODE_H" then
    return item.height
  elseif parameter == "B_UISEL" then
    return item.selected and 1 or 0
  end
  return 0
end

function reaper.SetMediaItemInfo_Value(item, parameter, value)
  if parameter == "D_POSITION" then
    item.position = value
  elseif parameter == "D_LENGTH" then
    item.length = value
  elseif parameter == "B_UISEL" then
    item.selected = value == 1
  end
end

function reaper.CountSelectedMediaItems()
  local count = 0
  for _, track in ipairs(tracks) do
    for _, item in ipairs(track.items) do
      if item.selected then
        count = count + 1
      end
    end
  end
  return count
end

function reaper.GetSelectedMediaItem(_, requested_index)
  local index = 0
  for _, track in ipairs(tracks) do
    for _, item in ipairs(track.items) do
      if item.selected then
        if index == requested_index then
          return item
        end
        index = index + 1
      end
    end
  end
  return nil
end

function reaper.GetMediaItemTrack(item)
  return item.track
end

function reaper.Main_OnCommand(command)
  assert(command == 40062, "Unexpected command")
  local source_index
  for index, track in ipairs(tracks) do
    if track.selected then
      source_index = index
      break
    end
  end
  assert(source_index, "No source track selected")

  local duplicate = copy_track(tracks[source_index])
  table.remove(tracks, #tracks)
  table.insert(tracks, source_index + 1, duplicate)
end

function reaper.GetItemStateChunk(item)
  return true, string.format(
    "<ITEM\nPOSITION %.12f\nLENGTH %.12f\nIGUID {OLD}\nGUID {TAKE}\n>",
    item.position,
    item.length
  )
end

function reaper.AddMediaItemToTrack(track)
  return make_item(track, 0, 0, false)
end

function reaper.SetItemStateChunk(item, chunk)
  item.position = assert(tonumber(chunk:match("POSITION ([^\n]+)")))
  item.length = assert(tonumber(chunk:match("LENGTH ([^\n]+)")))
  return true
end

function reaper.genGuid()
  next_guid = next_guid + 1
  return "{GUID" .. tostring(next_guid) .. "}"
end

function reaper.SplitMediaItem(item, position)
  local item_end = item.position + item.length
  if position <= item.position or position >= item_end then
    return nil
  end

  local right = make_item(
    item.track,
    position,
    item_end - position,
    item.selected
  )
  item.length = position - item.position
  return right
end

function reaper.MoveMediaItemToTrack(item, destination_track)
  local source_track = item.track
  local index = find_item_index(source_track, item)
  assert(index, "Moved item is missing from source track")
  table.remove(source_track.items, index)
  destination_track.items[#destination_track.items + 1] = item
  item.track = destination_track
  return true
end

function reaper.Undo_BeginBlock2() end
function reaper.Undo_EndBlock2() end
function reaper.PreventUIRefresh() end
function reaper.UpdateArrange() end
function reaper.TrackList_AdjustWindows() end

local function assert_close(actual, expected, message)
  assert(math.abs(actual - expected) < 0.000001, message)
end

local function run_selected_test(expected_operation, expected_position)
  reset()
  local source = make_track()
  local selected = make_item(source, 10, 2, true)
  make_item(source, 20, 3, false)

  dofile(script_to_test)

  assert(#tracks == 2, "Expected one duplicated track")
  local destination = tracks[2]
  assert(#destination.items == 1, "Destination should contain one item")
  assert_close(destination.items[1].position, expected_position, "Wrong position")
  assert(destination.height == 1, "Destination should use minimum height")

  if expected_operation == "move" then
    assert(#source.items == 1, "Moved item remained on source track")
    assert(destination.items[1] == selected, "Original item was not moved")
  else
    assert(#source.items == 2, "Copy operation changed source material")
    assert(destination.items[1] ~= selected, "Copy operation moved original item")
  end
end

local function run_razor_test(expected_operation, expected_position)
  reset()
  local source = make_track('7 9 "" 0 1')
  make_item(source, 5, 10, false)
  make_item(source, 30, 2, true)

  dofile(script_to_test)

  assert(#tracks == 2, "Expected one duplicated track")
  local destination = tracks[2]
  assert(#destination.items == 1, "Destination should contain Razor material")
  assert_close(destination.items[1].position, expected_position, "Wrong Razor position")
  assert_close(destination.items[1].length, 2, "Wrong Razor length")
  assert(destination.razor_edits == "", "Destination Razor Edits were not cleared")

  if expected_operation == "move" then
    assert(#source.items == 3, "Source item was not split around moved range")
  else
    assert(#source.items == 2, "Razor copy changed source material")
  end
end

if scenario == "copy_zero_selected" then
  run_selected_test("copy", 0)
elseif scenario == "copy_selected" then
  run_selected_test("copy", 10)
elseif scenario == "move_selected" then
  run_selected_test("move", 10)
elseif scenario == "copy_zero_razor" then
  run_razor_test("copy", 0)
elseif scenario == "move_razor" then
  run_razor_test("move", 7)
else
  error("Unknown scenario: " .. scenario)
end

print("PASS " .. scenario)
