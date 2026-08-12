-- @description icss_Track Organizer - Preset 2 - Film Post
-- @noindex
-- @author icanseesounds
-- @version 2.1.0
-- @about
--   Runs Track Organizer with Film Post, the second factory preset.

local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[\\/])") or ""
_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = "02 Film Post.ini"
local ok, message = pcall(dofile, directory .. "icss_Track Organizer.lua")
_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = nil
if not ok then
  error(message, 0)
end
