-- @description Duplicate to New Copy of a Track
-- @noindex
-- @author icanseesounds
-- @version 1.0.0
-- @changelog
--   Initial version
-- @about
--   Duplicates source tracks without their media items and copies the selected
--   material to the new tracks at its original timeline position.
--
--   * Razor Edits take priority over selected media items.
--   * Media-item Razor Edits copy only the material inside their boundaries.
--   * Envelope Razor Edits are ignored.
--   * Selected items are copied in full when no Razor Edit exists.
--   * Source material remains unchanged.
--   * New tracks keep the source track settings and use minimum height.

_G.ICSS_NEW_TRACK_COPY_OPTIONS = {
  operation = "copy",
  move_to_zero = false,
  undo_description = "Duplicate to new copy of a track",
}

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_directory = script_path:match("^(.*[/\\])") or ""
local success, message = pcall(
  dofile,
  script_directory ..
    "icss_Duplicate to New Copy of a Track and Move to 0.00.lua"
)
_G.ICSS_NEW_TRACK_COPY_OPTIONS = nil
if not success then
  error(message, 0)
end
