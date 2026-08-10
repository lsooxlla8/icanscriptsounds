-- @description Add Volume Adjustment Automation
-- @author icanseesounds
-- @version 1.0.0
-- @changelog
--   Initial version
-- @about
--   Adds JS: Volume Adjustment to the selected track.
--
--   * Sets Adjustment to 0 dB.
--   * Shows the Adjustment automation envelope.
--   * Leaves the plug-in window closed.

local FX_NAME = "JS: Volume Adjustment"
local ADJUSTMENT_PARAM_NAME = "Adjustment (dB)"
local ADJUSTMENT_VALUE_DB = 0.0
local UNDO_DESCRIPTION = "Add Volume Adjustment automation"

local function get_selected_track_including_master()
  local master_track = reaper.GetMasterTrack(0)
  if reaper.IsTrackSelected(master_track) then
    return master_track
  end

  return reaper.GetSelectedTrack(0, 0)
end

local function find_parameter(track, fx_index, parameter_name)
  for param_index = 0, reaper.TrackFX_GetNumParams(track, fx_index) - 1 do
    local retval, name = reaper.TrackFX_GetParamName(
      track,
      fx_index,
      param_index
    )

    if retval and name == parameter_name then
      return param_index
    end
  end

  return -1
end

local function show_envelope(envelope)
  reaper.GetSetEnvelopeInfo_String(envelope, "ACTIVE", "1", true)
  reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "1", true)
end

local function close_fx_window(track, fx_index)
  reaper.TrackFX_SetOpen(track, fx_index, false)
  reaper.TrackFX_Show(track, fx_index, 2)
  reaper.TrackFX_Show(track, fx_index, 0)
end

local function show_error(message)
  reaper.ShowMessageBox(message, "Add Volume Adjustment Automation", 0)
end

local function main()
  local selected_track = get_selected_track_including_master()
  if not selected_track then
    show_error("Select a track.")
    return
  end

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)

  local fx_index = reaper.TrackFX_AddByName(
    selected_track,
    FX_NAME,
    false,
    -1
  )

  if fx_index < 0 then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("Could not add JS: Volume Adjustment.")
    return
  end

  local adjustment_param = find_parameter(
    selected_track,
    fx_index,
    ADJUSTMENT_PARAM_NAME
  )

  if adjustment_param < 0 then
    reaper.TrackFX_Delete(selected_track, fx_index)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("Could not find the Adjustment parameter.")
    return
  end

  reaper.TrackFX_SetParam(
    selected_track,
    fx_index,
    adjustment_param,
    ADJUSTMENT_VALUE_DB
  )

  local envelope = reaper.GetFXEnvelope(
    selected_track,
    fx_index,
    adjustment_param,
    true
  )

  if not envelope then
    reaper.TrackFX_Delete(selected_track, fx_index)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
    show_error("Could not create the Adjustment automation envelope.")
    return
  end

  show_envelope(envelope)
  close_fx_window(selected_track, fx_index)

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(0, UNDO_DESCRIPTION, -1)
end

main()
