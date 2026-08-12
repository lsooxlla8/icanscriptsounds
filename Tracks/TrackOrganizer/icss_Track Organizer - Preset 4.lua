-- @description icss_Track Organizer - Preset 4 - Podcast
-- @noindex
-- @author icanseesounds
-- @version 2.1.0
-- @about
--   Runs Track Organizer with Podcast, the fourth factory preset.

local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[\\/])") or ""
_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = "04 Podcast.ini"
local ok, message = pcall(dofile, directory .. "icss_Track Organizer.lua")
_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = nil
if not ok then
  error(message, 0)
end
