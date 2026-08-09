-- @description Smart Freeze Toggle
-- @author icanseesounds
-- @version 2.1.0
-- @changelog
--   Set silence 66 dB below the loudest pre-tail 50 ms RMS window
-- @about
--   Toggles the freeze state of every selected track.
--
--   * Unfrozen track: measures the real frozen output, then freezes natively
--     with five seconds of confirmed silence after the audible tail.
--   * Frozen track: unfreezes one freeze layer.
--   * Mixed multi-track selections are processed independently.
--
--   Requires the free SWS/S&M extension.

local SCRIPT_NAME = "Smart Freeze Toggle"
local CMD_FREEZE_TO_STEREO = 41223
local CMD_UNFREEZE_TRACKS = 41644

local POST_TAIL_SILENCE_SECONDS = 5.0
local INITIAL_FREEZE_TAIL_SECONDS = 20.0
local RELATIVE_SILENCE_THRESHOLD_DB = -66.0
local FALLBACK_SILENCE_THRESHOLD_DB = -80.0
local ANALYSIS_SAMPLE_RATE = 44100
local ANALYSIS_CHANNELS = 2
local ANALYSIS_BLOCK_FRAMES = 2205
local RENDER_TAIL_CONFIG_KEY = "rendertail"

local RELATIVE_SILENCE_RATIO =
  10 ^ (RELATIVE_SILENCE_THRESHOLD_DB / 20)
local FALLBACK_SILENCE_THRESHOLD =
  10 ^ (FALLBACK_SILENCE_THRESHOLD_DB / 20)

local function show_message(message)
  reaper.ShowMessageBox(message, SCRIPT_NAME, 0)
end

local function track_name(track)
  local _, name = reaper.GetTrackName(track)
  if name == "" then
    local number = math.floor(
      reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    )
    return "Track " .. tostring(number)
  end
  return name
end

local function collect_selected_tracks()
  local tracks = {}
  for index = 0, reaper.CountSelectedTracks(0) - 1 do
    tracks[#tracks + 1] = reaper.GetSelectedTrack(0, index)
  end
  return tracks
end

local function restore_track_selection(tracks)
  reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
  for _, track in ipairs(tracks) do
    if reaper.ValidatePtr2(0, track, "MediaTrack*") then
      reaper.SetTrackSelected(track, true)
    end
  end
end

local function get_track_item_end(track)
  local item_count = reaper.CountTrackMediaItems(track)
  if item_count == 0 then
    return nil
  end

  local material_end
  for index = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, index)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_length
    material_end = math.max(material_end or item_end, item_end)
  end
  return material_end
end

local function get_track_item_start(track)
  local item_count = reaper.CountTrackMediaItems(track)
  if item_count == 0 then
    return nil
  end

  local material_start
  for index = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, index)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    material_start = math.min(
      material_start or item_start,
      item_start
    )
  end
  return material_start
end

local function get_material_end(track, visited)
  visited = visited or {}
  if visited[track] then
    return nil
  end
  visited[track] = true

  local material_end = get_track_item_end(track)

  -- Include ordinary receives and sidechain sources.
  for receive_index = 0, reaper.GetTrackNumSends(track, -1) - 1 do
    local source_track = reaper.GetTrackSendInfo_Value(
      track,
      -1,
      receive_index,
      "P_SRCTRACK"
    )
    if source_track
        and reaper.ValidatePtr2(0, source_track, "MediaTrack*") then
      local source_end = get_material_end(source_track, visited)
      if source_end then
        material_end = math.max(material_end or source_end, source_end)
      end
    end
  end

  -- Parent routing is not always exposed as an ordinary receive.
  local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  if folder_depth > 0 then
    local track_number = math.floor(
      reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    )
    local depth = folder_depth
    local index = track_number
    while index < reaper.CountTracks(0) and depth > 0 do
      local child = reaper.GetTrack(0, index)
      local child_end = get_material_end(child, visited)
      if child_end then
        material_end = math.max(material_end or child_end, child_end)
      end
      depth = depth
        + reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
      index = index + 1
    end
  end

  return material_end
end

local function analyse_frozen_tail(track, material_end)
  local frozen_start = get_track_item_start(track)
  local frozen_end = get_track_item_end(track)
  if not frozen_start or not frozen_end or frozen_end <= material_end then
    return nil, "The frozen track contains no analysable tail."
  end

  local accessor = reaper.CreateTrackAudioAccessor(track)
  if not accessor then
    return nil, "REAPER could not create an audio accessor for the frozen track."
  end

  local buffer = reaper.new_array(
    ANALYSIS_BLOCK_FRAMES * ANALYSIS_CHANNELS
  )
  local function read_block_rms(position, range_end)
    local remaining_frames = math.ceil(
      (range_end - position) * ANALYSIS_SAMPLE_RATE
    )
    local frame_count = math.min(
      ANALYSIS_BLOCK_FRAMES,
      remaining_frames
    )
    buffer.clear()

    local available = reaper.GetAudioAccessorSamples(
      accessor,
      ANALYSIS_SAMPLE_RATE,
      ANALYSIS_CHANNELS,
      position,
      frame_count,
      buffer
    )
    if available < 0 then
      return nil, nil
    end

    local sum_squares = 0
    for frame = 0, frame_count - 1 do
      local sample_offset = frame * ANALYSIS_CHANNELS
      for channel = 1, ANALYSIS_CHANNELS do
        local sample = buffer[sample_offset + channel]
        sum_squares = sum_squares + sample * sample
      end
    end

    local block_duration = frame_count / ANALYSIS_SAMPLE_RATE
    local sample_count = frame_count * ANALYSIS_CHANNELS
    local rms = math.sqrt(sum_squares / sample_count)
    return rms, block_duration
  end

  local position = frozen_start
  local reference_rms = 0
  while position < material_end do
    local rms, block_duration = read_block_rms(position, material_end)
    if not rms then
      reaper.DestroyAudioAccessor(accessor)
      return nil, "REAPER could not read the pre-tail reference audio."
    end
    reference_rms = math.max(reference_rms, rms)
    position = position + block_duration
  end

  local silence_threshold = FALLBACK_SILENCE_THRESHOLD
  if reference_rms > 0 then
    silence_threshold = reference_rms * RELATIVE_SILENCE_RATIO
  end

  position = material_end
  local last_audible
  while position < frozen_end do
    local rms, block_duration = read_block_rms(position, frozen_end)
    if not rms then
      reaper.DestroyAudioAccessor(accessor)
      return nil, "REAPER could not read the complete frozen tail."
    end
    if rms >= silence_threshold then
      last_audible = position + block_duration
    end

    position = position + block_duration
  end

  reaper.DestroyAudioAccessor(accessor)

  local audible_end = last_audible or material_end
  local desired_end =
    audible_end + POST_TAIL_SILENCE_SECONDS
  local has_confirmed_silence =
    frozen_end - audible_end >= POST_TAIL_SILENCE_SECONDS

  return {
    frozen_end = frozen_end,
    audible_end = audible_end,
    desired_end = desired_end,
    has_confirmed_silence = has_confirmed_silence,
    reference_rms = reference_rms,
    silence_threshold = silence_threshold,
  }
end

local selected_tracks = collect_selected_tracks()
if #selected_tracks == 0 then
  show_message("Select at least one track.")
  return
end

if not reaper.SNM_GetIntConfigVar or not reaper.SNM_SetIntConfigVar then
  show_message(
    "Smart Freeze Toggle requires the free SWS/S&M extension.\n\n"
    .. "Install SWS, restart REAPER, and run the script again."
  )
  return
end

local original_render_tail = reaper.SNM_GetIntConfigVar(
  RENDER_TAIL_CONFIG_KEY,
  -1
)
if original_render_tail < 0 then
  show_message("Could not read REAPER's freeze-tail preference.")
  return
end

local current_tail = original_render_tail
local warnings = {}
local fallback_notices = {}

local function set_render_tail(milliseconds)
  if current_tail ~= milliseconds then
    reaper.SNM_SetIntConfigVar(RENDER_TAIL_CONFIG_KEY, milliseconds)
    current_tail = milliseconds
  end
end

local function native_freeze(track, tail_seconds, previous_freeze_count)
  set_render_tail(math.ceil(tail_seconds * 1000))
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(CMD_FREEZE_TO_STEREO, 0)
  return reaper.GetMediaTrackInfo_Value(
    track,
    "I_FREEZECOUNT"
  ) > previous_freeze_count
end

local function native_unfreeze(track, expected_freeze_count)
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(CMD_UNFREEZE_TRACKS, 0)
  return reaper.GetMediaTrackInfo_Value(
    track,
    "I_FREEZECOUNT"
  ) < expected_freeze_count
end

local function smart_freeze(track)
  local material_end = get_material_end(track)
  if not material_end then
    return false,
      "The track and its upstream routing contain no media items."
  end

  local original_freeze_count = reaper.GetMediaTrackInfo_Value(
    track,
    "I_FREEZECOUNT"
  )
  local tail_seconds = INITIAL_FREEZE_TAIL_SECONDS

  while true do
    if not native_freeze(
        track,
        tail_seconds,
        original_freeze_count
    ) then
      return false, "REAPER did not complete the freeze."
    end

    local analysis, analysis_error =
      analyse_frozen_tail(track, material_end)
    if not analysis then
      fallback_notices[#fallback_notices + 1] = string.format(
        "%s: %s The %.0f-second frozen tail was kept unchanged.",
        track_name(track),
        tostring(analysis_error),
        tail_seconds
      )
      return true
    end

    if analysis.has_confirmed_silence then
      local measured_tail = math.max(
        POST_TAIL_SILENCE_SECONDS,
        analysis.desired_end - material_end
      )
      local current_freeze_count =
        reaper.GetMediaTrackInfo_Value(track, "I_FREEZECOUNT")

      if not native_unfreeze(track, current_freeze_count) then
        return false,
          "The measurement freeze succeeded, but REAPER could not "
          .. "unfreeze it for the final pass."
      end

      if not native_freeze(
          track,
          measured_tail,
          original_freeze_count
      ) then
        return false,
          "REAPER did not complete the final measured freeze."
      end
      return true
    end

    local current_freeze_count =
      reaper.GetMediaTrackInfo_Value(track, "I_FREEZECOUNT")
    if not native_unfreeze(track, current_freeze_count) then
      return false,
        "The first freeze was too short, and REAPER could not "
        .. "unfreeze it for an extended retry."
    end

    tail_seconds = tail_seconds * 2
  end
end

reaper.Undo_BeginBlock2(0)
reaper.PreventUIRefresh(1)

local overall_ok, overall_error = xpcall(function()
  for _, track in ipairs(selected_tracks) do
    if reaper.ValidatePtr2(0, track, "MediaTrack*") then
      reaper.SetOnlyTrackSelected(track)
      local freeze_count = reaper.GetMediaTrackInfo_Value(
        track,
        "I_FREEZECOUNT"
      )

      if freeze_count > 0 then
        reaper.Main_OnCommand(CMD_UNFREEZE_TRACKS, 0)
        if reaper.GetMediaTrackInfo_Value(
            track,
            "I_FREEZECOUNT"
          ) >= freeze_count then
          warnings[#warnings + 1] =
            track_name(track) .. ": REAPER did not complete the unfreeze."
        end
      else
        local frozen, freeze_error = smart_freeze(track)
        if not frozen then
          warnings[#warnings + 1] =
            track_name(track) .. ": " .. tostring(freeze_error)
        end
      end
    end
  end
end, debug.traceback)

set_render_tail(original_render_tail)
restore_track_selection(selected_tracks)
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock2(0, SCRIPT_NAME, -1)

if not overall_ok then
  warnings[#warnings + 1] =
    "Unexpected error:\n" .. tostring(overall_error)
end

if #warnings > 0 then
  show_message(
    "Some operations could not be completed:\n\n• "
    .. table.concat(warnings, "\n\n• ")
  )
end

if #fallback_notices > 0 then
  show_message(
    "Some tracks were frozen with an untrimmed fallback tail:\n\n• "
    .. table.concat(fallback_notices, "\n\n• ")
  )
end
