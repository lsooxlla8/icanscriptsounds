-- @description Freeze Toggles
-- @author icanseesounds
-- @version 3.0.0
-- @changelog
--   Bundle Freeze Toggle and Smart Freeze Toggle as one ReaPack package
-- @provides
--   [main] icss_Smart Freeze Toggle.lua
-- @about
--   Provides two actions that toggle every selected track independently.
--
--   * Freeze Toggle freezes an unfrozen track to stereo or unfreezes one
--     freeze layer from a frozen track.
--   * Smart Freeze Toggle measures a safe post-FX tail before freezing an
--     unfrozen track, or unfreezes one freeze layer from a frozen track.
--
--   Smart Freeze Toggle requires the free SWS/S&M extension.

local CMD_FREEZE_TO_STEREO = 41223
local CMD_UNFREEZE_TRACKS = 41644

local selected_count = reaper.CountSelectedTracks(0)

if selected_count == 0 then
  reaper.ShowMessageBox(
    "Select at least one track.",
    "Freeze Toggle",
    0
  )
  return
end

-- Keep the original selection. Processing tracks one at a time also makes a
-- mixed selection safe: frozen tracks are unfrozen, while unfrozen tracks are
-- frozen instead of adding another freeze layer to every selected track.
local selected_tracks = {}
for index = 0, selected_count - 1 do
  selected_tracks[#selected_tracks + 1] = reaper.GetSelectedTrack(0, index)
end

for _, track in ipairs(selected_tracks) do
  reaper.SetOnlyTrackSelected(track)

  local freeze_count = reaper.GetMediaTrackInfo_Value(track, "I_FREEZECOUNT")
  if freeze_count > 0 then
    reaper.Main_OnCommand(CMD_UNFREEZE_TRACKS, 0)
  else
    reaper.Main_OnCommand(CMD_FREEZE_TO_STEREO, 0)
  end
end

-- Restore the selection the user had before running the script.
reaper.SetOnlyTrackSelected(selected_tracks[1])
for index = 2, #selected_tracks do
  reaper.SetTrackSelected(selected_tracks[index], true)
end

reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
