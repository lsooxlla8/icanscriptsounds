-- @noindex

local script_path = assert(arg[1], "Script path is required")

local tracks = {
  { name = "Audio Track", channels = 2 },
  { name = "MIDI Track", channels = 2 },
  { name = "Empty Track", channels = 2 },
  { name = "Generator Track", channels = 2 },
}
local sources = {
  audio = { path = "/Audio/Kick.wav", channels = 2 },
  midi = { path = "", channels = 0 },
  generated = { path = "", channels = 0 },
}
local takes = {
  audio = { name = "", source = sources.audio },
  midi = { name = "MIDI Phrase", source = sources.midi },
  generated = { name = "", source = sources.generated },
}
local items = {
  { track = tracks[1], take = takes.audio, notes = "", position = 0, length = 1 },
  { track = tracks[2], take = takes.midi, notes = "", position = 0, length = 2 },
  { track = tracks[3], take = nil, notes = "Empty Guide", position = 0, length = 3 },
  { track = tracks[4], take = takes.generated, notes = "", position = 0, length = 4 },
}
local master = { name = "MASTER", channels = 2 }
local project_info = {
  RULER_LANE_COUNT = 4,
  RULER_HEIGHT = 120,
}
local regions = {}
local errors = {}

reaper = {
  CountSelectedMediaItems = function()
    return #items
  end,
  GetSelectedMediaItem = function(_, index)
    return items[index + 1]
  end,
  GetMediaItemTrack = function(item)
    return item.track
  end,
  GetActiveTake = function(item)
    return item.take
  end,
  GetMediaItemTake_Source = function(take)
    return take.source
  end,
  GetMediaSourceParent = function()
    return nil
  end,
  GetMediaSourceFileName = function(source)
    return source.path
  end,
  GetMediaSourceNumChannels = function(source)
    return source.channels
  end,
  GetSetMediaItemTakeInfo_String = function(take)
    return true, take.name
  end,
  GetSetMediaItemInfo_String = function(item)
    return true, item.notes
  end,
  GetMediaItemInfo_Value = function(item, key)
    if key == "D_POSITION" then
      return item.position
    elseif key == "D_LENGTH" then
      return item.length
    elseif key == "C_LOCK" then
      return 0
    end
    return 0
  end,
  SetMediaItemPosition = function(item, position)
    item.position = position
  end,
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
    if key == "I_NCHAN" then
      return track.channels
    elseif key == "I_FOLDERDEPTH" then
      return 0
    elseif key == "I_CUSTOMCOLOR" then
      return track.color or 0
    elseif key == "I_VUMODE" then
      return track.vu_mode or 0
    end
    return 0
  end,
  SetMediaTrackInfo_Value = function(track, key, value)
    if key == "I_NCHAN" then
      track.channels = value
    elseif key == "I_CUSTOMCOLOR" then
      track.color = value
    elseif key == "I_VUMODE" then
      track.vu_mode = value
    end
  end,
  GetSetMediaTrackInfo_String = function(track, _, value, set_value)
    if set_value then
      track.name = value
    end
    return true, track.name
  end,
  GetMasterTrack = function()
    return master
  end,
  ColorToNative = function(red, green, blue)
    return red + green * 256 + blue * 65536
  end,
  GetNumRegionsOrMarkers = function()
    return 0
  end,
  GetRegionOrMarker = function()
    return nil
  end,
  DeleteProjectMarkerByIndex = function()
    return true
  end,
  AddRegionOrMarker = function(_, _, start_position, end_position, name)
    local id = #regions + 1
    regions[id] = {
      id = id,
      start_position = start_position,
      end_position = end_position,
      name = name,
    }
    return id
  end,
  GetRegionOrMarkerInfo_Value = function(_, region, key)
    if key == "I_NUMBER" then
      return region
    end
    return 0
  end,
  SetRegionOrMarkerInfo_Value = function()
    return true
  end,
  SetRegionRenderMatrix = function()
    return true
  end,
  GetSetProjectInfo = function(_, key, value, set_value)
    if key:match("^RULER_LANE_VISIBLE:") then
      return 1
    elseif key:match("^RULER_LANE_HIDDEN:") then
      return 0
    end
    if set_value then
      project_info[key] = value
    end
    return project_info[key] or 0
  end,
  GetSetProjectInfo_String = function()
    return true, ""
  end,
  Resample_EnumModes = function(mode)
    return mode == 7 and "r8brain-free" or "Other"
  end,
  set_config_var_string = function()
    return 1
  end,
  UpdateTimeline = function() end,
  UpdateArrange = function() end,
  TrackList_AdjustWindows = function() end,
  PreventUIRefresh = function() end,
  Undo_BeginBlock2 = function() end,
  Undo_EndBlock2 = function() end,
  ShowMessageBox = function(message)
    errors[#errors + 1] = message
  end,
}

dofile(script_path)

assert(#errors == 0, errors[1])
assert(#regions == 4, "Expected one region per selected item track")
assert(tracks[1].name == "Kick", "File-backed item must use its filename")
assert(tracks[2].name == "MIDI Phrase", "MIDI item must use its take name")
assert(tracks[3].name == "Empty Guide", "Empty item must use its notes")
assert(
  tracks[4].name == "Generator Track",
  "Generated item must fall back to its track name"
)

print("Prepare Selected Items for Mastering mock passed")
