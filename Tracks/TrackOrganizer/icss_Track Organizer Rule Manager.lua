-- @description icss_Track Organizer Rule Manager
-- @noindex
-- @author icanseesounds
-- @version 3.2.0
-- @changelog
--   Add recoverable deletion and named Action List actions for user presets
--   Reorder the five factory presets for music, post, and spoken-word work
--   Replace technical modifier placement text with a guided behavior menu
--   Add editable order modifiers, virtual order groups, and preset selection
--   Show folder-rule match names and explain rule-based sorting families
--   Run the deep conflict audit only when saving rules
--   Make Preview match Organizer's atomic existing-folder behavior
--   Refresh safely when the REAPER project changes behind the window
--   Prevent controls from overlapping in narrower windows
-- @about
--   Human-friendly editor for Track Organizer's track-order.ini.
--   Uses REAPER's built-in gfx window and requires no ReaImGui installation.

local function script_directory()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*[\\/])") or ""
end

local DIRECTORY = script_directory()
local CORE_PATH = DIRECTORY .. "TrackOrganizer_Core.lua"
local LEGACY_CONFIG_PATH = DIRECTORY .. "track-order.ini"
local PRESETS_DIRECTORY = DIRECTORY .. "Presets/"
local FACTORY_PRESETS_DIRECTORY = DIRECTORY .. "Factory Presets/"
local FOLDER_TAG = "P_EXT:ICSS_TRACK_ORGANIZER_FOLDER"
local PRESET_STATE_SECTION = "ICSS_TRACK_ORGANIZER"
local PRESET_STATE_KEY = "PRESET_FILE"
local WINDOW_TITLE = "Track Organizer Rules"
local WINDOW_WIDTH = 1320
local WINDOW_HEIGHT = 860
local FACTORY_PRESETS = {
  ["01 Music Mixing.ini"] = true,
  ["02 Film Post.ini"] = true,
  ["03 Sound Design.ini"] = true,
  ["04 Podcast.ini"] = true,
  ["05 Audiobook.ini"] = true,
}
local LEGACY_PRESET_FILENAMES = {
  ["02 Audiobook.ini"] = "05 Audiobook.ini",
  ["03 Podcast.ini"] = "04 Podcast.ini",
  ["04 Film Post.ini"] = "02 Film Post.ini",
  ["05 Sound Design.ini"] = "03 Sound Design.ini",
}
local FACTORY_PRESET_FILES = {
  "01 Music Mixing.ini",
  "02 Film Post.ini",
  "03 Sound Design.ini",
  "04 Podcast.ini",
  "05 Audiobook.ini",
}

local function current_preset_filename(filename)
  return LEGACY_PRESET_FILENAMES[filename] or filename
end

local function show_message(message, flags)
  return reaper.ShowMessageBox(
    tostring(message or ""),
    "Track Organizer Rules",
    flags or 0
  )
end

local core_file = io.open(CORE_PATH, "r")
if not core_file then
  show_message(
    "TrackOrganizer_Core.lua was not found.\n\n"
    .. "Keep it in the same folder as this script."
  )
  return
end
core_file:close()
local Core = dofile(CORE_PATH)

local presets_ready, presets_error = Core.ensure_presets(
  FACTORY_PRESETS_DIRECTORY,
  PRESETS_DIRECTORY,
  FACTORY_PRESET_FILES,
  function(path)
    return reaper.RecursiveCreateDirectory(path, 0)
  end
)
if not presets_ready then
  show_message(
    "Track Organizer could not prepare its presets:\n\n" .. tostring(presets_error)
  )
  return
end

local function enumerate_preset(directory, index)
  if not reaper.EnumerateFiles then
    return nil
  end
  return reaper.EnumerateFiles(directory, index)
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if not file then
    return false
  end
  file:close()
  return true
end

local function preset_action_path(preset)
  local base = tostring(preset.filename or "Preset"):gsub("%.ini$", "")
  return DIRECTORY .. "icss_Track Organizer - " .. base .. ".lua"
end

local function is_factory_filename(filename)
  return FACTORY_PRESETS[filename] == true
end

local function preset_action_source(preset)
  local description = "icss_Track Organizer - " .. tostring(preset.name)
  return table.concat({
    "-- @description " .. description,
    "-- @noindex",
    "-- @author icanseesounds",
    "-- @version 1.0.0",
    "-- @about",
    "--   Runs Track Organizer with this specific user preset.",
    "",
    "local source = debug.getinfo(1, \"S\").source:sub(2)",
    "local directory = source:match(\"^(.*[\\\\/])\") or \"\"",
    "_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = " .. string.format("%q", preset.filename),
    "local ok, message = pcall(dofile, directory .. \"icss_Track Organizer.lua\")",
    "_G.ICSS_TRACK_ORGANIZER_PRESET_FILE = nil",
    "if not ok then",
    "  error(message, 0)",
    "end",
    "",
  }, "\n")
end

local presets = {}
local active_preset
local active_config_path = LEGACY_CONFIG_PATH

local function install_preset_action(preset, quiet)
  if not preset or is_factory_filename(preset.filename) then
    return true
  end
  if not reaper.AddRemoveReaScript then
    if not quiet then
      show_message(
        "The preset was created, but this REAPER version cannot register "
        .. "its Action List action automatically."
      )
    end
    return false
  end
  local path = preset_action_path(preset)
  local temporary_path = path .. ".tmp"
  local file, open_error = io.open(temporary_path, "wb")
  if not file then
    if not quiet then
      show_message("Could not create the preset action:\n\n" .. tostring(open_error))
    end
    return false
  end
  file:write(preset_action_source(preset))
  file:close()
  os.remove(path)
  local renamed, rename_error = os.rename(temporary_path, path)
  if not renamed then
    os.remove(temporary_path)
    if not quiet then
      show_message("Could not install the preset action:\n\n" .. tostring(rename_error))
    end
    return false
  end
  local command_id = reaper.AddRemoveReaScript(true, 0, path, true)
  if not command_id or command_id == 0 then
    if not quiet then
      show_message(
        "The action file was created, but REAPER could not add it to the Action List."
      )
    end
    return false
  end
  return true
end

local function ensure_user_preset_actions()
  for _, preset in ipairs(presets) do
    if not is_factory_filename(preset.filename)
      and not file_exists(preset_action_path(preset))
    then
      install_preset_action(preset, true)
    end
  end
end

local function refresh_presets()
  presets = Core.list_presets(PRESETS_DIRECTORY, enumerate_preset)
end

local function remember_preset(preset)
  active_preset = preset
  active_config_path = preset and preset.path or LEGACY_CONFIG_PATH
  if preset and reaper.SetProjExtState then
    reaper.SetProjExtState(
      0,
      PRESET_STATE_SECTION,
      PRESET_STATE_KEY,
      preset.filename
    )
  end
end

local function choose_initial_preset()
  refresh_presets()
  ensure_user_preset_actions()
  local filename
  if reaper.GetProjExtState then
    local _, stored = reaper.GetProjExtState(
      0,
      PRESET_STATE_SECTION,
      PRESET_STATE_KEY
    )
    filename = stored ~= "" and current_preset_filename(stored) or nil
  end
  if not filename and reaper.GetExtState then
    local stored = reaper.GetExtState(
      PRESET_STATE_SECTION,
      "DEFAULT_PRESET_FILE"
    )
    filename = stored ~= "" and current_preset_filename(stored) or nil
  end
  remember_preset(Core.find_preset(presets, filename) or presets[1])
end

choose_initial_preset()

local COLORS = {
  background = { 0.075, 0.085, 0.10, 1 },
  panel = { 0.105, 0.12, 0.14, 1 },
  header = { 0.13, 0.15, 0.18, 1 },
  row = { 0.105, 0.12, 0.14, 1 },
  row_alt = { 0.12, 0.135, 0.16, 1 },
  group = { 0.08, 0.22, 0.31, 1 },
  other = { 0.22, 0.18, 0.10, 1 },
  selected = { 0.08, 0.40, 0.60, 1 },
  selected_soft = { 0.09, 0.27, 0.39, 1 },
  text = { 0.92, 0.94, 0.97, 1 },
  muted = { 0.62, 0.67, 0.72, 1 },
  line = { 0.22, 0.25, 0.29, 1 },
  accent = { 0.10, 0.64, 0.88, 1 },
  green = { 0.20, 0.75, 0.48, 1 },
  yellow = { 0.95, 0.70, 0.20, 1 },
  red = { 0.92, 0.32, 0.32, 1 },
  button = { 0.18, 0.21, 0.25, 1 },
  button_hover = { 0.24, 0.29, 0.34, 1 },
  button_disabled = { 0.12, 0.13, 0.15, 1 },
}

local config
local selected_id
local selected_modifier_id
local selected_project_key
local dirty = false
local status_message = ""
local status_error = false
local mode = "rules"
local rule_rows = {}
local modifier_rows = {}
local project_rows = {}
local unknown_rows = {}
local preview_rows = {}
local scroll = { rules = 0, modifiers = 0, unknown = 0, preview = 0 }
local collapsed = {}
local collapse_initialized = false
local previous_left = false
local previous_right = false
local last_clicked_id
local last_click_time = 0
local running = true
local project_state_change_count
local refresh_project
local set_status

local function set_color(color)
  gfx.set(color[1], color[2], color[3], color[4])
end

local function fill_rect(x, y, width, height, color)
  set_color(color)
  gfx.rect(x, y, width, height, true)
end

local function stroke_rect(x, y, width, height, color)
  set_color(color)
  gfx.rect(x, y, width, height, false)
end

local function draw_text(text, x, y, color, font)
  if font then
    gfx.setfont(font)
  end
  set_color(color or COLORS.text)
  gfx.x = x
  gfx.y = y
  gfx.drawstr(tostring(text or ""))
end

local function fit_text(text, width)
  text = tostring(text or "")
  if width <= 12 or gfx.measurestr(text) <= width then
    return text
  end
  local suffix = "..."
  local suffix_width = gfx.measurestr(suffix)
  while #text > 0 and gfx.measurestr(text) + suffix_width > width do
    text = text:sub(1, -2)
  end
  return text .. suffix
end

local function inside(x, y, width, height)
  return gfx.mouse_x >= x and gfx.mouse_x < x + width
    and gfx.mouse_y >= y and gfx.mouse_y < y + height
end

local function track_name(track)
  local _, name = reaper.GetTrackName(track)
  return name or ""
end

local function is_managed_folder(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(
    track,
    FOLDER_TAG,
    "",
    false
  )
  return value ~= ""
end

local function select_reaper_track(track)
  if not track then
    return
  end
  if reaper.ValidatePtr2
    and not reaper.ValidatePtr2(0, track, "MediaTrack*")
  then
    refresh_project()
    set_status("The project changed. The track list was refreshed.", false)
    return
  end
  reaper.SetOnlyTrackSelected(track)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

set_status = function(message, is_error)
  status_message = message or ""
  status_error = is_error or false
end

local function flatten_rules()
  rule_rows = {}
  local function visit(node, depth)
    rule_rows[#rule_rows + 1] = {
      node = node,
      depth = depth,
      key = node.id,
    }
    if not collapsed[node.id] then
      for _, child in ipairs(node.children or {}) do
        visit(child, depth + 1)
      end
    end
  end
  for _, category in ipairs(config.categories or {}) do
    visit(category, 0)
  end
end

refresh_project = function()
  project_rows = {}
  unknown_rows = {}
  preview_rows = {}
  local tracks = {}
  local depths = {}
  local managed = {}
  for index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, index)
    tracks[#tracks + 1] = track
    depths[#depths + 1] = reaper.GetMediaTrackInfo_Value(
      track,
      "I_FOLDERDEPTH"
    )
    managed[track] = is_managed_folder(track)
  end

  local index = 1
  while index <= #tracks do
    local track = tracks[index]
    if managed[track] then
      index = index + 1
    else
      local end_index = index
      if depths[index] > 0 then
        end_index = Core.find_subtree_end(depths, index)
        if not end_index then
          end_index = index
        end
      end
      local name = track_name(track)
      local result
      if end_index > index then
        local descendants = {}
        for child_index = index + 1, end_index do
          local child = tracks[child_index]
          if not managed[child] then
            descendants[#descendants + 1] = {
              name = track_name(child),
              is_container = depths[child_index] > 0,
            }
          end
        end
        result = Core.classify_atomic_folder(config, name, descendants)
      else
        result = Core.classify(config, name)
      end
      local row = {
        track = track,
        index = index,
        name = name,
        result = result,
        key = tostring(track),
        is_folder = end_index > index,
      }
      project_rows[#project_rows + 1] = row
      preview_rows[#preview_rows + 1] = row
      if not result.winner then
        unknown_rows[#unknown_rows + 1] = row
      end
      index = end_index + 1
    end
  end
  if reaper.GetProjectStateChangeCount then
    project_state_change_count = reaper.GetProjectStateChangeCount(0)
  end
end

local function load_config()
  local loaded, errors = Core.load_config(active_config_path)
  if not loaded then
    show_message(
      "The rules file could not be loaded:\n\n"
      .. table.concat(errors or { "Unknown error." }, "\n")
    )
    return false
  end
  config = loaded
  modifier_rows = config.modifiers or {}
  if not selected_modifier_id then
    selected_modifier_id = modifier_rows[1] and modifier_rows[1].id or nil
  end
  if not collapse_initialized then
    for _, category in ipairs(config.categories) do
      collapsed[category.id] = not category.special
    end
    collapse_initialized = true
  end
  if not selected_id or not config.nodes_by_id[selected_id] then
    selected_id = config.categories[1] and config.categories[1].id or nil
  end
  dirty = false
  flatten_rules()
  refresh_project()
  set_status("Rules loaded.", false)
  return true
end

local function mark_dirty(message)
  Core.rebuild(config)
  modifier_rows = config.modifiers or {}
  flatten_rules()
  refresh_project()
  dirty = true
  set_status(message or "Unsaved changes.", false)
end

if not load_config() then
  return
end

local function selected_node()
  return selected_id and config.nodes_by_id[selected_id] or nil
end

local function selected_project_row()
  local rows = mode == "unknown" and unknown_rows or preview_rows
  for _, row in ipairs(rows) do
    if row.key == selected_project_key then
      return row
    end
  end
  return nil
end

local function human_path(node)
  if not node then
    return "OTHER"
  end
  return Core.path_names(node, "  >  ")
end

local INPUT_SEPARATOR = "|"

local function split_input(value, count)
  local result = {}
  local start = 1
  for index = 1, count - 1 do
    local separator = value:find(INPUT_SEPARATOR, start, true)
    if not separator then
      return nil
    end
    result[index] = value:sub(start, separator - 1)
    start = separator + 1
  end
  result[count] = value:sub(start)
  return result
end

local function has_input_separator(...)
  for index = 1, select("#", ...) do
    if tostring(select(index, ...) or ""):find(INPUT_SEPARATOR, 1, true) then
      return true
    end
  end
  return false
end

local function ask_fields(title, captions, values)
  if has_input_separator(table.unpack(values)) then
    show_message(
      "The | character is reserved by this edit window.\n\n"
      .. "Replace it with a space, then try again."
    )
    return nil
  end
  local safe_captions = {}
  for index, caption in ipairs(captions) do
    -- GetUserInputs always uses commas between field captions. A comma inside
    -- one caption creates phantom labels and shifts every value to the wrong
    -- row, even when the returned values use a custom separator.
    safe_captions[index] = tostring(caption):gsub(",", " /")
  end
  local ok, returned = reaper.GetUserInputs(
    title,
    #values,
    table.concat(safe_captions, ",") .. ",separator=|,extrawidth=360",
    table.concat(values, INPUT_SEPARATOR)
  )
  if not ok then
    return nil
  end
  local fields = split_input(returned, #values)
  if not fields then
    show_message("Please do not use the | character in these fields.")
    return nil
  end
  return fields
end

local function automatic_priority(parent)
  local parent_priority = tonumber(parent and parent.priority) or 0
  local depth = tonumber(parent and parent.depth) or 0
  return math.max(parent_priority + 30, 100 + (depth + 1) * 30)
end

local function selected_modifier()
  for _, modifier in ipairs(config.modifiers or {}) do
    if modifier.id == selected_modifier_id then
      return modifier
    end
  end
  return nil
end

local function modifier_placement_label(placement)
  return placement == "first" and "Move to beginning"
    or placement == "family_first"
      and "Before same name without this word"
    or "Move to end"
end

local function choose_modifier_behavior(current)
  local choices = {
    {
      value = "first",
      label = "Move matching tracks to the beginning",
    },
    {
      value = "family_first",
      label = "Put before the same name without this word",
    },
    {
      value = "last",
      label = "Move matching tracks to the end",
    },
  }
  local menu = {}
  for _, choice in ipairs(choices) do
    menu[#menu + 1] = (choice.value == current and "!" or "")
      .. choice.label
  end
  gfx.x = math.max(0, gfx.mouse_x)
  gfx.y = math.max(0, gfx.mouse_y)
  local selected = gfx.showmenu(table.concat(menu, "|"))
  return choices[selected] and choices[selected].value or nil
end

local function edit_modifier_fields(modifier, title)
  local behavior = choose_modifier_behavior(modifier.placement)
  if not behavior then
    return false
  end
  local fields = ask_fields(
    title,
    {
      "Rule name",
      "When track name contains (separate with ;)",
      "Ignore names containing (optional)",
    },
    {
      modifier.name,
      Core.join_list(modifier.patterns),
      Core.join_list(modifier.excludes),
    }
  )
  if not fields then
    return false
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  if name == "" then
    show_message("Enter a rule name.")
    return false
  end
  modifier.name = name
  modifier.placement = behavior
  modifier.patterns = Core.split_list(fields[2])
  modifier.excludes = Core.split_list(fields[3])
  return true
end

local function new_modifier()
  local id = Core.unique_modifier_id(config, "new.order.rule")
  local modifier = Core.new_modifier(config, id, "New special order rule")
  if not edit_modifier_fields(modifier, "New special order rule") then
    Core.delete_modifier(config, modifier.id)
    return
  end
  local final_id = Core.unique_modifier_id(config, Core.slug(modifier.name))
  modifier.id = final_id
  Core.rebuild(config)
  selected_modifier_id = modifier.id
  mark_dirty("Special order rule created. Click Save when finished.")
end

local function edit_modifier()
  local modifier = selected_modifier()
  if not modifier then
    show_message("Choose a special order rule first.")
    return
  end
  if edit_modifier_fields(modifier, "Edit special order rule") then
    mark_dirty("Special order rule updated. Click Save when finished.")
  end
end

local function toggle_modifier()
  local modifier = selected_modifier()
  if not modifier then
    return
  end
  modifier.enabled = not modifier.enabled
  mark_dirty(modifier.enabled and "Special order rule enabled."
    or "Special order rule disabled.")
end

local function move_modifier(direction)
  local modifier = selected_modifier()
  if not modifier or not Core.move_modifier(config, modifier.id, direction) then
    set_status("That modifier is already at the edge.", false)
    return
  end
  mark_dirty("Special order rule order changed.")
end

local function remove_modifier()
  local modifier = selected_modifier()
  if not modifier then
    return
  end
  if #(config.modifiers or {}) <= 1 then
    show_message("Keep at least one modifier. You can turn it off instead.")
    return
  end
  local answer = show_message("Remove modifier \"" .. modifier.name .. "\"?", 4)
  if answer ~= 6 then
    return
  end
  Core.delete_modifier(config, modifier.id)
  selected_modifier_id = config.modifiers[1] and config.modifiers[1].id or nil
  mark_dirty("Order modifier removed. Click Save when finished.")
end

local function choose_main_group()
  local choices = {}
  local nodes = {}
  for _, category in ipairs(config.categories) do
    if not category.special then
      choices[#choices + 1] = category.name
      nodes[#nodes + 1] = category
    end
  end
  if #nodes == 0 then
    show_message("Create a main group first.")
    return nil
  end
  gfx.x = math.max(0, gfx.mouse_x)
  gfx.y = math.max(0, gfx.mouse_y)
  local choice = gfx.showmenu(table.concat(choices, "|"))
  return nodes[choice]
end

local function usable_parent()
  local node = selected_node()
  if node and not node.special then
    return node
  end
  return choose_main_group()
end

local function new_main_group(container)
  container = container == "order" and "order" or "folder"
  local fields = ask_fields(
    container == "order" and "New main order group" or "New main folder",
    container == "order"
      and { "Group name" }
      or { "Group name", "Folder track name" },
    container == "order"
      and { "NEW ORDER GROUP" }
      or { "NEW GROUP", "NEW GROUP" }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  local folder = container == "folder"
    and fields[2]:match("^%s*(.-)%s*$") or ""
  if name == "" then
    show_message("Enter a group name.")
    return
  end
  local id = Core.unique_id(config, Core.slug(name))
  local node = Core.new_category(config, id, name)
  node.container = container
  node.folder = container == "folder" and (folder ~= "" and folder or name) or ""
  local other = config.nodes_by_id.other
  if other then
    node.order = other.order - 1
  end
  selected_id = node.id
  Core.rebuild(config)
  Core.renumber_siblings(config, nil)
  mark_dirty(
    container == "order"
      and "Main order group created. It will not create a track."
      or "Main folder created. Click Save when finished."
  )
end

local function new_rule(parent, proposed_name, proposed_pattern, insert_after)
  parent = parent or usable_parent()
  if not parent or parent.special then
    return
  end
  local fields = ask_fields(
    "New rule inside " .. parent.name,
    { "Rule name", "Names or words (separate with ;)", "Do not match (optional)" },
    {
      proposed_name or "New Rule",
      proposed_pattern or "",
      "",
    }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  if name == "" then
    show_message("Enter a rule name.")
    return
  end
  local base = parent.id .. "." .. Core.slug(name)
  local id = Core.unique_id(config, base)
  local node = Core.new_rule(config, id, parent.id, name)
  node.patterns = Core.split_list(fields[2])
  node.excludes = Core.split_list(fields[3])
  node.priority = automatic_priority(parent)
  if insert_after then
    local moved, move_error = Core.move_after(config, node.id, insert_after.id)
    if not moved then
      show_message("The rule was created, but could not be placed below the selected row:\n\n"
        .. tostring(move_error))
    end
  end
  collapsed[parent.id] = false
  selected_id = node.id
  mark_dirty("Rule created. Click Save when finished.")
end

local function new_rule_below()
  local node = selected_node()
  if not node or node.kind ~= "rule" or node.special then
    show_message(
      "Choose an existing rule first.\n\n"
      .. "ADD BELOW creates a new rule beside it on the same level."
    )
    return
  end
  local parent = config.nodes_by_id[node.parent]
  if not parent then
    show_message("The selected rule has no valid parent.")
    return
  end
  new_rule(parent, nil, nil, node)
end

local function new_rule_inside()
  local node = selected_node()
  if not node or node.special then
    show_message(
      "Choose a main group, subfolder or rule first.\n\n"
      .. "ADD INSIDE creates a child rule inside it."
    )
    return
  end
  new_rule(node)
end

local function new_subfolder(parent)
  parent = parent or usable_parent()
  if not parent or parent.special then
    return
  end
  local fields = ask_fields(
    "New subfolder under " .. parent.name,
    { "Rule group name", "Folder track name" },
    { "New Subfolder", "NEW SUBFOLDER" }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  local folder = fields[2]:match("^%s*(.-)%s*$")
  if name == "" or folder == "" then
    show_message("Enter both a group name and a folder track name.")
    return
  end
  local base = parent.id .. "." .. Core.slug(name)
  local id = Core.unique_id(config, base)
  local node = Core.new_rule(config, id, parent.id, name)
  node.folder = folder
  node.container = "folder"
  node.priority = 0
  collapsed[parent.id] = false
  collapsed[node.id] = false
  selected_id = node.id
  mark_dirty("Subfolder created. Click Save when finished.")
end

local function new_order_group(parent)
  parent = parent or usable_parent()
  if not parent or parent.special then
    return
  end
  local fields = ask_fields(
    "New order group under " .. parent.name,
    {
      "Order group name",
      "Names in this group (optional; separate with ;)",
      "Do not match (optional)",
    },
    { "New Order Group", "", "" }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  if name == "" then
    show_message("Enter an order group name.")
    return
  end
  local base = parent.id .. "." .. Core.slug(name)
  local id = Core.unique_id(config, base)
  local node = Core.new_rule(config, id, parent.id, name)
  node.container = "order"
  node.patterns = Core.split_list(fields[2])
  node.excludes = Core.split_list(fields[3])
  node.priority = 0
  collapsed[parent.id] = false
  collapsed[node.id] = false
  selected_id = node.id
  mark_dirty("Order group created. It will organize tracks without creating a folder.")
end

local function add_selected_track_as_rule(parent)
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    show_message(
      "Select a track in REAPER first.\n\n"
      .. "Then select the destination group in this window and try again."
    )
    return
  end
  parent = parent or usable_parent()
  if not parent then
    return
  end
  local name = track_name(track)
  new_rule(parent, name, Core.normalize(name, config.settings.case_sensitive))
end

local function edit_selected()
  local node = selected_node()
  if not node then
    show_message("Choose a row first.")
    return
  end
  if node.special then
    local fields = ask_fields(
      "Rename the OTHER folder",
      { "Folder track name" },
      { config.settings.unknown_folder_name or node.folder or node.name }
    )
    if fields and fields[1]:match("%S") then
      config.settings.unknown_folder_name = fields[1]:match("^%s*(.-)%s*$")
      node.name = config.settings.unknown_folder_name
      node.folder = config.settings.unknown_folder_name
      mark_dirty("OTHER folder renamed. Click Save when finished.")
    end
    return
  end
  if node.kind == "category" then
    local fields = ask_fields(
      "Edit main group",
      {
        "Group name",
        "Type: folder or order",
        "Folder track name (folder type only)",
      },
      {
        node.name,
        Core.is_order_group_node(node) and "order" or "folder",
        node.folder ~= "" and node.folder or node.name,
      }
    )
    if not fields then
      return
    end
    local name = fields[1]:match("^%s*(.-)%s*$")
    if name == "" then
      show_message("Enter a group name.")
      return
    end
    local container = fields[2]:match("^%s*(.-)%s*$"):lower()
    if container ~= "folder" and container ~= "order" then
      show_message("Type must be folder or order.")
      return
    end
    node.name = name
    node.container = container
    node.folder = container == "folder"
      and fields[3]:match("^%s*(.-)%s*$") or ""
    if container == "folder" and node.folder == "" then
      node.folder = name
    end
  elseif Core.is_folder_node(node) then
    local fields = ask_fields(
      "Edit subfolder",
      {
        "Rule group name",
        "Folder track name",
        "Names in this sorting family (optional; separate with ;)",
        "Do not match (optional)",
      },
      {
        node.name,
        node.folder,
        Core.join_list(node.patterns),
        Core.join_list(node.excludes),
      }
    )
    if not fields then
      return
    end
    local name = fields[1]:match("^%s*(.-)%s*$")
    local folder = fields[2]:match("^%s*(.-)%s*$")
    if name == "" or folder == "" then
      show_message("Enter both a group name and a folder track name.")
      return
    end
    node.name = name
    node.folder = folder
    node.patterns = Core.split_list(fields[3])
    node.excludes = Core.split_list(fields[4])
  elseif Core.is_order_group_node(node) then
    local fields = ask_fields(
      "Edit order group",
      {
        "Order group name",
        "Names in this group (optional; separate with ;)",
        "Do not match (optional)",
      },
      {
        node.name,
        Core.join_list(node.patterns),
        Core.join_list(node.excludes),
      }
    )
    if not fields then
      return
    end
    local name = fields[1]:match("^%s*(.-)%s*$")
    if name == "" then
      show_message("Enter an order group name.")
      return
    end
    node.name = name
    node.patterns = Core.split_list(fields[2])
    node.excludes = Core.split_list(fields[3])
  else
    local fields = ask_fields(
      "Edit rule",
      {
        "Rule name",
        "Names in this sorting family (separate with ;)",
        "Do not match (optional)",
      },
      {
        node.name,
        Core.join_list(node.patterns),
        Core.join_list(node.excludes),
      }
    )
    if not fields then
      return
    end
    local name = fields[1]:match("^%s*(.-)%s*$")
    if name == "" then
      show_message("Enter a rule name.")
      return
    end
    node.name = name
    node.patterns = Core.split_list(fields[2])
    node.excludes = Core.split_list(fields[3])
  end
  mark_dirty("Rule updated. Click Save when finished.")
end

local function delete_selected()
  local node = selected_node()
  if not node then
    show_message("Choose a row first.")
    return
  end
  if node.special then
    show_message("OTHER is required and cannot be removed.")
    return
  end
  local detail = #(node.children or {}) > 0
    and "\n\nAll rules inside this group will also be removed."
    or ""
  local answer = show_message(
    "Remove \"" .. node.name .. "\"?" .. detail,
    4
  )
  if answer ~= 6 then
    return
  end
  local parent_id = node.parent
  Core.delete_node(config, node.id)
  local parent = parent_id and config.nodes_by_id[parent_id] or nil
  selected_id = parent and parent.id
    or (config.categories[1] and config.categories[1].id)
  mark_dirty("Rule removed. Click Save when finished.")
end

local function move_selected(direction)
  local node = selected_node()
  if not node or node.special then
    set_status("Choose a movable row.", true)
    return
  end
  local siblings = node.parent
    and config.nodes_by_id[node.parent].children
    or config.categories
  local position
  for index, sibling in ipairs(siblings) do
    if sibling.id == node.id then
      position = index
      break
    end
  end
  local target_position = position and position + direction
  local target = target_position and siblings[target_position] or nil
  if not target or target.special then
    set_status("That row is already at the edge of its group.", false)
    return
  end
  node.order, target.order = target.order, node.order
  Core.rebuild(config)
  Core.renumber_siblings(config, node.parent)
  mark_dirty("Order changed. Click Save when finished.")
end

local function is_inside_node(node, possible_parent)
  local current = node
  while current do
    if current.id == possible_parent.id then
      return true
    end
    current = current.parent and config.nodes_by_id[current.parent] or nil
  end
  return false
end

local function move_selected_to()
  local node = selected_node()
  if not node or node.kind ~= "rule" or node.special then
    show_message("Choose a rule or subfolder to move first.")
    return
  end

  local labels = {}
  local destinations = {}
  local function visit(candidate)
    local can_contain = Core.is_layout_node(candidate)
    if can_contain
      and not candidate.special
      and candidate.id ~= node.parent
      and not is_inside_node(candidate, node)
    then
      labels[#labels + 1] = human_path(candidate):gsub("|", "/")
      destinations[#destinations + 1] = candidate
    end
    for _, child in ipairs(candidate.children or {}) do
      visit(child)
    end
  end
  for _, category in ipairs(config.categories or {}) do
    visit(category)
  end

  if #destinations == 0 then
    show_message("There is no other main group or subfolder to move this rule into.")
    return
  end

  gfx.x = math.max(0, gfx.mouse_x)
  gfx.y = math.max(0, gfx.mouse_y)
  local choice = gfx.showmenu(table.concat(labels, "|"))
  local destination = destinations[choice]
  if not destination then
    return
  end

  local ok, message = Core.reparent_node(config, node.id, destination.id)
  if not ok then
    show_message(message)
    return
  end
  collapsed[destination.id] = false
  mark_dirty(
    "Moved \"" .. node.name .. "\" to " .. human_path(destination)
      .. ". Click Save when finished."
  )
end

local function save_config()
  local validation = Core.validate(config, { semantic = true })
  if not validation.ok then
    show_message(
      "The rules were not saved:\n\n"
      .. Core.validation_summary(validation)
    )
    set_status("Save failed validation.", true)
    return false
  end
  if #validation.warnings > 0 then
    local answer = show_message(
      "The rules contain possible conflicts:\n\n"
      .. table.concat(validation.warnings, "\n")
      .. "\n\nSave anyway?",
      4
    )
    if answer ~= 6 then
      set_status("Save cancelled. Review the conflicts first.", true)
      return false
    end
  end
  local ok, message = Core.save_config(
    config,
    active_config_path,
    { validation = validation }
  )
  if not ok then
    show_message("The rules were not saved:\n\n" .. tostring(message))
    set_status("Save failed.", true)
    return false
  end
  dirty = false
  set_status("Saved. The Organizer will use this order next time.", false)
  return true
end

local function reload_config()
  if dirty then
    local answer = show_message(
      "Discard the changes that have not been saved?",
      4
    )
    if answer ~= 6 then
      return
    end
  end
  load_config()
end

local function restore_backup()
  local answer = show_message(
    "Restore the previous saved version of the rules?",
    4
  )
  if answer ~= 6 then
    return
  end
  local ok, message = Core.restore_backup(active_config_path)
  if not ok then
    show_message(message)
    return
  end
  load_config()
  set_status("Previous saved version restored.", false)
end

local function switch_preset(preset)
  if not preset or (active_preset and preset.filename == active_preset.filename) then
    return
  end
  if dirty then
    show_message("Save or reload the current preset before switching presets.")
    return
  end
  remember_preset(preset)
  collapse_initialized = false
  collapsed = {}
  selected_id = nil
  selected_modifier_id = nil
  load_config()
  set_status("Preset selected: " .. preset.name, false)
end

local new_preset_from_current
local delete_current_preset

local function choose_preset_menu()
  refresh_presets()
  if #presets == 0 then
    show_message("No preset files were found in:\n\n" .. PRESETS_DIRECTORY)
    return
  end
  local labels = {}
  for _, preset in ipairs(presets) do
    labels[#labels + 1] = (
      active_preset and preset.filename == active_preset.filename and "!" or ""
    )
      .. tostring(preset.slot) .. "  " .. preset.name
  end
  labels[#labels + 1] = "New preset from current rules..."
  labels[#labels + 1] = "Delete current preset..."
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local choice = gfx.showmenu(table.concat(labels, "|"))
  if presets[choice] then
    switch_preset(presets[choice])
  elseif choice == #presets + 1 then
    new_preset_from_current()
  elseif choice == #presets + 2 then
    delete_current_preset()
  end
end

new_preset_from_current = function()
  if dirty and not save_config() then
    return
  end
  local fields = ask_fields(
    "New preset from current rules",
    { "Preset name" },
    { "New Preset" }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  if name == "" then
    show_message("Enter a preset name.")
    return
  end
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(PRESETS_DIRECTORY, 0)
  end
  refresh_presets()
  local slot = 1
  for _, preset in ipairs(presets) do
    local number = tonumber(preset.filename:match("^(%d+)"))
    if number then
      slot = math.max(slot, number + 1)
    end
  end
  local safe_name = name:gsub("[%c]", " ")
  safe_name = safe_name:gsub("[\\/:*?\"<>|]", "-")
  safe_name = safe_name:gsub("%s+", " "):match("^%s*(.-)%s*$")
  local filename
  local path
  repeat
    filename = string.format("%02d %s.ini", slot, safe_name)
    path = PRESETS_DIRECTORY .. filename
    slot = slot + 1
    local existing = io.open(path, "rb")
    if existing then
      existing:close()
    else
      break
    end
  until false
  local copied = Core.copy_table(config)
  local validation = Core.validate(copied, { semantic = true })
  local ok, message = Core.save_config(
    copied,
    path,
    { validation = validation }
  )
  if not ok then
    show_message("The preset was not created:\n\n" .. tostring(message))
    return
  end
  refresh_presets()
  local preset = Core.find_preset(presets, filename)
  remember_preset(preset)
  load_config()
  if install_preset_action(preset, false) then
    set_status("Preset and Action List action created: " .. name, false)
  else
    set_status("Preset created: " .. name, false)
  end
end

local function move_to_deleted(path)
  if not file_exists(path) then
    return true
  end
  local deleted_path = path .. ".deleted"
  local suffix = 2
  while file_exists(deleted_path) do
    deleted_path = path .. ".deleted." .. tostring(suffix)
    suffix = suffix + 1
  end
  return os.rename(path, deleted_path)
end

delete_current_preset = function()
  if not active_preset then
    show_message("There is no preset file to delete.")
    return
  end
  if is_factory_filename(active_preset.filename) then
    show_message(
      "The five factory presets stay installed because Preset 1-5 actions "
      .. "depend on them.\n\nOnly presets created in Rule Manager can be deleted."
    )
    return
  end
  local warning = "Delete preset '" .. active_preset.name .. "'?\n\n"
    .. "Its rules will be removed from the preset list. "
    .. "Tracks in the REAPER project will not be changed."
  if dirty then
    warning = warning .. "\n\nUnsaved changes in this preset will also be discarded."
  end
  if show_message(warning, 4) ~= 6 then
    return
  end

  local deleted_preset = active_preset
  local action_path = preset_action_path(deleted_preset)
  if not move_to_deleted(deleted_preset.path) then
    show_message("The preset could not be deleted.")
    return
  end
  move_to_deleted(deleted_preset.path .. ".bak")
  if not is_factory_filename(deleted_preset.filename) and file_exists(action_path) then
    if reaper.AddRemoveReaScript then
      reaper.AddRemoveReaScript(false, 0, action_path, true)
    end
    move_to_deleted(action_path)
  end

  if reaper.GetExtState and reaper.SetExtState then
    local default_filename = reaper.GetExtState(
      PRESET_STATE_SECTION,
      "DEFAULT_PRESET_FILE"
    )
    if default_filename == deleted_preset.filename then
      reaper.SetExtState(
        PRESET_STATE_SECTION,
        "DEFAULT_PRESET_FILE",
        "01 Music Mixing.ini",
        true
      )
    end
  end

  dirty = false
  refresh_presets()
  local next_slot = math.min(deleted_preset.slot or 1, #presets)
  remember_preset(presets[next_slot] or presets[1])
  collapse_initialized = false
  collapsed = {}
  selected_id = nil
  selected_modifier_id = nil
  if active_preset then
    load_config()
    set_status("Preset deleted: " .. deleted_preset.name, false)
  else
    show_message(
      "The last preset was deleted. Create or restore a preset before editing rules."
    )
  end
end

local function set_default_preset()
  if not active_preset or not reaper.SetExtState then
    return
  end
  reaper.SetExtState(
    PRESET_STATE_SECTION,
    "DEFAULT_PRESET_FILE",
    active_preset.filename,
    true
  )
  set_status("Default preset: " .. active_preset.name, false)
end

local function append_unknown_to_selected_rule()
  local row = selected_project_row()
  local node = selected_node()
  if not row then
    show_message("Choose an unclassified track first.")
    return
  end
  if not node or node.kind ~= "rule" or node.special then
    show_message(
      "First open RULES and choose the rule this track belongs to.\n\n"
      .. "Then return to OTHER and press this button again."
    )
    return
  end
  local pattern = Core.normalize(row.name, config.settings.case_sensitive)
  for _, existing in ipairs(node.patterns) do
    if Core.normalize(existing, config.settings.case_sensitive) == pattern then
      set_status("That name is already in " .. human_path(node) .. ".", false)
      return
    end
  end
  node.patterns[#node.patterns + 1] = pattern
  mark_dirty("\"" .. row.name .. "\" will now go to " .. human_path(node) .. ".")
end

local function create_rule_from_unknown()
  local row = selected_project_row()
  if not row then
    show_message("Choose an unclassified track first.")
    return
  end
  local parent = usable_parent()
  if not parent then
    return
  end
  new_rule(
    parent,
    row.name,
    Core.normalize(row.name, config.settings.case_sensitive)
  )
end

local function test_track_name()
  local ok, name = reaper.GetUserInputs(
    "Test one track name",
    1,
    "Track name,extrawidth=300",
    ""
  )
  if not ok or name == "" then
    return
  end
  local result = Core.classify(config, name)
  if not result.winner then
    show_message("\"" .. name .. "\"\n\nGoes to:\nOTHER")
    return
  end
  local lines = {
    "\"" .. name .. "\"",
    "",
    "Goes to:",
    human_path(result.winner.node),
    "",
    "Matched name or words:",
    result.winner.pattern,
  }
  if #result.matches > 1 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Other possible rules:"
    for index = 2, math.min(#result.matches, 8) do
      lines[#lines + 1] = "- " .. human_path(result.matches[index].node)
    end
  end
  show_message(table.concat(lines, "\n"))
end

local function show_preview_details()
  local row = selected_project_row()
  if not row then
    return
  end
  local result = row.result
  local lines = { "\"" .. row.name .. "\"", "" }
  if row.is_folder then
    lines[#lines + 1] = "This existing folder stays intact."
    if result.atomic_reason == "homogeneous_category" then
      lines[#lines + 1] = "All recognized tracks inside belong to one category."
    elseif result.atomic_reason == "mixed_categories" then
      lines[#lines + 1] = "It contains tracks from different categories."
    elseif result.atomic_reason == "unclassified_child" then
      lines[#lines + 1] = "At least one track inside is unclassified."
    else
      lines[#lines + 1] = "Its contents cannot be classified safely."
    end
    lines[#lines + 1] = ""
  end
  if not result.winner then
    lines[#lines + 1] = "Goes to: OTHER"
  else
    lines[#lines + 1] = "Goes to:"
    lines[#lines + 1] = human_path(result.winner.node)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Matched:"
    lines[#lines + 1] = result.winner.pattern
  end
  if #result.matches > 1 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Also matched:"
    for index = 2, math.min(#result.matches, 12) do
      lines[#lines + 1] = "- " .. human_path(result.matches[index].node)
    end
    lines[#lines + 1] = ""
    local winner = result.matches[1]
    local runner_up = result.matches[2]
    if winner.priority ~= runner_up.priority then
      lines[#lines + 1] = "Winner: higher priority."
    elseif winner.specificity ~= runner_up.specificity then
      lines[#lines + 1] = "Winner: more specific match."
    else
      lines[#lines + 1] = "Winner: earlier rule order."
    end
  end
  local name_info = Core.name_sort_info(
    row.name,
    config.settings.case_sensitive
  )
  local order_modifiers = Core.matched_order_modifiers(config, name_info)
  if #order_modifiers > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Special order rules:"
    for _, modifier in ipairs(order_modifiers) do
      lines[#lines + 1] = "- " .. modifier.name .. " -> "
        .. modifier_placement_label(modifier.placement)
    end
  end
  if row.is_folder and result.source_results then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Folder contents:"
    for index, source in ipairs(result.source_results) do
      if index > 12 then
        lines[#lines + 1] = "- ..."
        break
      end
      local destination = source.result.winner
        and source.result.winner.category.name or "UNCLASSIFIED"
      lines[#lines + 1] = "- " .. source.name .. " -> " .. destination
    end
  end
  show_message(table.concat(lines, "\n"))
end

local function toggle_selected()
  local node = selected_node()
  if not node or node.special then
    return
  end
  node.enabled = not node.enabled
  mark_dirty(
    node.enabled
      and "\"" .. node.name .. "\" is now on."
      or "\"" .. node.name .. "\" is now off."
  )
end

local function handle_new_menu()
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local choice = gfx.showmenu(
    "New main folder"
    .. "|New main order group (no track)"
    .. "|New subfolder inside selected row"
    .. "|New order group inside selected row (no track)"
    .. "|Rule from selected REAPER track inside selected row"
  )
  if choice == 1 then
    new_main_group("folder")
  elseif choice == 2 then
    new_main_group("order")
  elseif choice == 3 then
    new_subfolder()
  elseif choice == 4 then
    new_order_group()
  elseif choice == 5 then
    add_selected_track_as_rule()
  end
end

local function handle_row_menu(row)
  selected_id = row.node.id
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local toggle_label = row.node.enabled and "Turn off" or "Turn on"
  local move_label = row.node.kind == "rule" and "Move to..." or "#Move to..."
  local below_label = row.node.kind == "rule"
    and "Add rule below" or "#Add rule below"
  local choice = gfx.showmenu(
    "Edit"
    .. "|" .. below_label
    .. "|Add rule inside"
    .. "|" .. move_label
    .. "|New subfolder inside"
    .. "|New order group inside (no track)"
    .. "|Rule from selected REAPER track inside"
    .. "|" .. toggle_label
    .. "|Remove"
    .. "|Move up"
    .. "|Move down"
  )
  if choice == 1 then
    edit_selected()
  elseif choice == 2 then
    new_rule_below()
  elseif choice == 3 then
    new_rule_inside()
  elseif choice == 4 then
    move_selected_to()
  elseif choice == 5 then
    new_subfolder(row.node)
  elseif choice == 6 then
    new_order_group(row.node)
  elseif choice == 7 then
    add_selected_track_as_rule(row.node)
  elseif choice == 8 then
    toggle_selected()
  elseif choice == 9 then
    delete_selected()
  elseif choice == 10 then
    move_selected(-1)
  elseif choice == 11 then
    move_selected(1)
  end
end

local function draw_button(label, x, y, width, height, enabled, left_pressed, font)
  local hovered = inside(x, y, width, height)
  local color = not enabled and COLORS.button_disabled
    or (hovered and COLORS.button_hover or COLORS.button)
  fill_rect(x, y, width, height, color)
  stroke_rect(x, y, width, height, COLORS.line)
  font = font or 2
  gfx.setfont(font)
  local display_label = fit_text(label, math.max(1, width - 12))
  local text_width, text_height = gfx.measurestr(display_label)
  draw_text(
    display_label,
    x + math.max(8, (width - text_width) / 2),
    y + (height - text_height) / 2,
    enabled and COLORS.text or COLORS.muted,
    font
  )
  return enabled and hovered and left_pressed
end

local function draw_tab(label, tab_mode, x, y, width, left_pressed)
  local height = 60
  local active = mode == tab_mode
  local hovered = inside(x, y, width, height)
  fill_rect(
    x,
    y,
    width,
    height,
    active and COLORS.selected or (hovered and COLORS.button_hover or COLORS.button)
  )
  gfx.setfont(2)
  local display_label = fit_text(label, math.max(1, width - 20))
  local text_width, text_height = gfx.measurestr(display_label)
  draw_text(
    display_label,
    x + (width - text_width) / 2,
    y + (height - text_height) / 2,
    COLORS.text,
    2
  )
  if active then
    fill_rect(x, y + height - 4, width, 4, COLORS.accent)
  end
  if hovered and left_pressed then
    mode = tab_mode
    refresh_project()
    selected_project_key = nil
  end
end

local function draw_checkbox(x, y, enabled)
  fill_rect(x, y, 32, 32, enabled and COLORS.green or COLORS.button)
  stroke_rect(x, y, 32, 32, COLORS.line)
  if enabled then
    draw_text("ON", x + 2, y + 4, COLORS.background, 3)
  else
    draw_text("-", x + 9, y + 1, COLORS.muted, 2)
  end
end

local function draw_scrollbar(row_count, visible_count, top, height, offset)
  if row_count <= visible_count or row_count == 0 then
    return
  end
  local track_x = gfx.w - 9
  fill_rect(track_x, top, 5, height, COLORS.header)
  local thumb_height = math.max(24, height * visible_count / row_count)
  local maximum = math.max(1, row_count - visible_count)
  local thumb_y = top + (height - thumb_height) * offset / maximum
  fill_rect(track_x, thumb_y, 5, thumb_height, COLORS.muted)
end

local function handle_double_click(key, action)
  local now = reaper.time_precise()
  if last_clicked_id == key and now - last_click_time < 0.38 then
    last_clicked_id = nil
    last_click_time = 0
    action()
  else
    last_clicked_id = key
    last_click_time = now
  end
end

local function draw_rules_table(top, bottom, left_pressed, right_pressed)
  local header_height = 56
  local row_height = 64
  local x = 16
  local width = gfx.w - 32
  local table_height = bottom - top
  local body_top = top + header_height
  local match_x = x + math.max(340, width * 0.40)
  local exclude_x = x + width * 0.74
  local name_width = math.max(80, match_x - (x + 122) - 18)
  local match_width = math.max(70, exclude_x - match_x - 18)
  local exclude_width = math.max(70, x + width - exclude_x - 18)
  local visible = math.max(1, math.floor((table_height - header_height) / row_height))
  local maximum = math.max(0, #rule_rows - visible)
  scroll.rules = math.max(0, math.min(scroll.rules, maximum))

  fill_rect(x, top, width, header_height, COLORS.header)
  draw_text("ON", x + 14, top + 12, COLORS.muted, 3)
  draw_text("GROUP / RULE", x + 88, top + 12, COLORS.muted, 3)
  draw_text(
    fit_text("MATCH / SAME SORT FAMILY", match_width),
    match_x,
    top + 12,
    COLORS.muted,
    3
  )
  draw_text(
    fit_text("DO NOT MATCH", exclude_width),
    exclude_x,
    top + 12,
    COLORS.muted,
    3
  )

  for visible_index = 1, visible do
    local row_index = scroll.rules + visible_index
    local row = rule_rows[row_index]
    if not row then
      break
    end
    local node = row.node
    local is_folder_rule = node.kind == "rule" and Core.is_folder_node(node)
    local is_order_group = Core.is_order_group_node(node)
    local y = body_top + (visible_index - 1) * row_height
    local selected = node.id == selected_id
    local color
    if selected then
      color = node.kind == "category" and COLORS.selected or COLORS.selected_soft
    elseif node.special then
      color = COLORS.other
    elseif node.kind == "category" or is_folder_rule or is_order_group then
      color = COLORS.group
    else
      color = row_index % 2 == 0 and COLORS.row_alt or COLORS.row
    end
    fill_rect(x, y, width, row_height - 1, color)
    draw_checkbox(x + 14, y + 16, node.enabled)

    local indent = row.depth * 32
    local has_children = #(node.children or {}) > 0
    if has_children then
      draw_text(
        collapsed[node.id] and "+" or "-",
        x + 88 + indent,
        y + 12,
        COLORS.accent,
        2
      )
    end
    local prefix = Core.is_folder_node(node) and "FOLDER  "
      or (is_order_group and "ORDER  " or "- ")
    local name = prefix .. node.name
    local name_color = node.enabled and COLORS.text or COLORS.muted
    draw_text(
      fit_text(name, math.max(40, name_width - indent)),
      x + 122 + indent,
      y + 14,
      name_color,
      (node.kind == "category" or is_folder_rule or is_order_group) and 2 or 1
    )
    if node.kind == "category" then
      if is_order_group then
        draw_text(
          "Order only - creates no track",
          match_x,
          y + 14,
          COLORS.accent,
          3
        )
      else
        local folder = node.special
          and (config.settings.unknown_folder_name or "OTHER")
          or (node.folder ~= "" and node.folder or node.name)
        draw_text(
          fit_text("Folder: " .. folder, match_width),
          match_x,
          y + 14,
          COLORS.muted,
          1
        )
      end
    elseif is_folder_rule then
      local patterns = Core.join_list(node.patterns)
      local folder = node.folder ~= "" and node.folder or node.name
      if patterns ~= "" then
        draw_text(
          fit_text(patterns, match_width),
          match_x,
          y + 3,
          name_color,
          3
        )
        draw_text(
          fit_text("Creates folder: " .. folder, match_width),
          match_x,
          y + 33,
          COLORS.muted,
          3
        )
      else
        draw_text(
          fit_text("Creates folder: " .. folder, match_width),
          match_x,
          y + 14,
          COLORS.muted,
          1
        )
      end
      draw_text(
        fit_text(Core.join_list(node.excludes), exclude_width),
        exclude_x,
        y + 14,
        COLORS.muted,
        1
      )
    elseif is_order_group then
      local patterns = Core.join_list(node.patterns)
      draw_text(
        fit_text(patterns ~= "" and patterns or "Order only - creates no track", match_width),
        match_x,
        y + 3,
        patterns ~= "" and name_color or COLORS.accent,
        3
      )
      if patterns ~= "" then
        draw_text(
          "Order only - creates no track",
          match_x,
          y + 33,
          COLORS.accent,
          3
        )
      end
      draw_text(
        fit_text(Core.join_list(node.excludes), exclude_width),
        exclude_x,
        y + 14,
        COLORS.muted,
        1
      )
    else
      draw_text(
        fit_text(Core.join_list(node.patterns), match_width),
        match_x,
        y + 14,
        name_color,
        1
      )
      draw_text(
        fit_text(Core.join_list(node.excludes), exclude_width),
        exclude_x,
        y + 14,
        COLORS.muted,
        1
      )
    end

    if inside(x, y, width, row_height) then
      local status = is_order_group
        and "Order group: organizes tracks but creates no folder track"
        or node.kind == "category"
          and "Main folder: " .. (node.folder ~= "" and node.folder or node.name)
          or human_path(node)
      if node.kind == "rule" and #node.patterns > 0 then
        status = "One sorting family: " .. Core.join_list(node.patterns)
      end
      set_status(status, false)
      if left_pressed then
        selected_id = node.id
        if gfx.mouse_x < x + 70 then
          toggle_selected()
        elseif has_children
          and gfx.mouse_x >= x + 78 + indent
          and gfx.mouse_x < x + 116 + indent
        then
          collapsed[node.id] = not collapsed[node.id]
          flatten_rules()
        else
          handle_double_click(node.id, edit_selected)
        end
      elseif right_pressed then
        handle_row_menu(row)
      end
    end
  end
  draw_scrollbar(#rule_rows, visible, body_top, table_height - header_height, scroll.rules)
end

local function draw_modifiers_table(top, bottom, left_pressed)
  local header_height = 56
  local row_height = 72
  local x = 16
  local width = gfx.w - 32
  local body_top = top + header_height
  local name_x = x + 88
  local match_x = x + width * 0.36
  local placement_x = x + width * 0.75
  local match_width = placement_x - match_x - 20
  local placement_width = x + width - placement_x - 18
  local visible = math.max(1, math.floor((bottom - body_top) / row_height))
  local maximum = math.max(0, #modifier_rows - visible)
  scroll.modifiers = math.max(0, math.min(scroll.modifiers, maximum))

  fill_rect(x, top, width, header_height, COLORS.header)
  draw_text("ON", x + 14, top + 12, COLORS.muted, 3)
  draw_text("SPECIAL ORDER RULE", name_x, top + 12, COLORS.muted, 3)
  draw_text("WHEN NAME CONTAINS", match_x, top + 12, COLORS.muted, 3)
  draw_text("WHAT IT DOES", placement_x, top + 12, COLORS.muted, 3)

  for visible_index = 1, visible do
    local row_index = scroll.modifiers + visible_index
    local modifier = modifier_rows[row_index]
    if not modifier then
      break
    end
    local y = body_top + (visible_index - 1) * row_height
    local selected = modifier.id == selected_modifier_id
    fill_rect(
      x,
      y,
      width,
      row_height - 1,
      selected and COLORS.selected_soft
        or (row_index % 2 == 0 and COLORS.row_alt or COLORS.row)
    )
    draw_checkbox(x + 14, y + 20, modifier.enabled)
    draw_text(modifier.name, name_x, y + 17, COLORS.text, 2)
    draw_text(
      fit_text(Core.join_list(modifier.patterns), match_width),
      match_x,
      y + 18,
      modifier.enabled and COLORS.text or COLORS.muted,
      1
    )
    draw_text(
      fit_text(modifier_placement_label(modifier.placement), placement_width),
      placement_x,
      y + 20,
      COLORS.accent,
      3
    )
    if inside(x, y, width, row_height) then
      set_status(
        modifier.name .. ": " .. Core.join_list(modifier.patterns)
          .. " -> " .. modifier_placement_label(modifier.placement),
        false
      )
      if left_pressed then
        selected_modifier_id = modifier.id
        if gfx.mouse_x < x + 70 then
          toggle_modifier()
        else
          handle_double_click("modifier:" .. modifier.id, edit_modifier)
        end
      end
    end
  end
  draw_scrollbar(
    #modifier_rows,
    visible,
    body_top,
    bottom - body_top,
    scroll.modifiers
  )
end

local function result_path(result)
  return result.winner and human_path(result.winner.node) or "OTHER"
end

local function draw_project_table(rows, top, bottom, left_pressed, is_preview)
  local header_height = 56
  local row_height = 64
  local x = 16
  local width = gfx.w - 32
  local table_height = bottom - top
  local body_top = top + header_height
  local visible = math.max(1, math.floor((table_height - header_height) / row_height))
  local scroll_key = is_preview and "preview" or "unknown"
  local maximum = math.max(0, #rows - visible)
  scroll[scroll_key] = math.max(0, math.min(scroll[scroll_key], maximum))

  fill_rect(x, top, width, header_height, COLORS.header)
  draw_text("TRACK IN THIS PROJECT", x + 18, top + 12, COLORS.muted, 3)
  draw_text(
    is_preview and "WILL GO TO" or "CURRENT RESULT",
    x + width * 0.48,
    top + 12,
    COLORS.muted,
    3
  )

  if #rows == 0 then
    local message = is_preview
      and "This project has no tracks to preview."
      or "Great — every track in this project is recognized."
    draw_text(message, x + 22, body_top + 34, COLORS.text, 2)
  end

  for visible_index = 1, visible do
    local row_index = scroll[scroll_key] + visible_index
    local row = rows[row_index]
    if not row then
      break
    end
    local y = body_top + (visible_index - 1) * row_height
    local selected = row.key == selected_project_key
    local color = selected and COLORS.selected_soft
      or (row_index % 2 == 0 and COLORS.row_alt or COLORS.row)
    fill_rect(x, y, width, row_height - 1, color)
    local display_name = row.is_folder and ("FOLDER  " .. row.name) or row.name
    draw_text(
      fit_text(display_name, width * 0.45),
      x + 18,
      y + 15,
      COLORS.text,
      1
    )
    local destination = is_preview and result_path(row.result) or "OTHER"
    local destination_color = (is_preview and row.result.conflict)
      and COLORS.yellow
      or (row.result.winner and COLORS.green or COLORS.yellow)
    draw_text(
      fit_text(destination, width * 0.48 - 40),
      x + width * 0.48,
      y + 15,
      destination_color,
      1
    )
    if is_preview and row.result.conflict then
      draw_text("multiple matches", x + width - 210, y + 15, COLORS.yellow, 3)
    end
    if inside(x, y, width, row_height) and left_pressed then
      selected_project_key = row.key
      select_reaper_track(row.track)
      handle_double_click(
        "track:" .. row.key,
        is_preview and show_preview_details or create_rule_from_unknown
      )
    end
  end
  draw_scrollbar(#rows, visible, body_top, table_height - header_height, scroll[scroll_key])
end

local function handle_wheel()
  if gfx.mouse_wheel == 0 then
    return
  end
  local direction = gfx.mouse_wheel > 0 and -3 or 3
  scroll[mode] = math.max(0, (scroll[mode] or 0) + direction)
  gfx.mouse_wheel = 0
end

local function request_close()
  if dirty then
    local answer = show_message(
      "Save your changes before closing?",
      3
    )
    if answer == 6 then
      if not save_config() then
        return false
      end
    elseif answer == 2 then
      return false
    end
  end
  running = false
  gfx.quit()
  return true
end

local function more_menu()
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local choice = gfx.showmenu(
    "Test a track name..."
    .. "|Reload rules from disk"
    .. "|Restore previous saved version"
    .. "|New preset from current rules..."
    .. "|Delete current preset..."
    .. "|Set current preset as default"
    .. "|Close"
  )
  if choice == 1 then
    test_track_name()
  elseif choice == 2 then
    reload_config()
  elseif choice == 3 then
    restore_backup()
  elseif choice == 4 then
    new_preset_from_current()
  elseif choice == 5 then
    delete_current_preset()
  elseif choice == 6 then
    set_default_preset()
  elseif choice == 7 then
    request_close()
  end
end

local function draw_footer(left_pressed)
  local y = gfx.h - 72
  fill_rect(0, y - 10, gfx.w, 82, COLORS.panel)
  fill_rect(0, y - 10, gfx.w, 1, COLORS.line)

  if mode == "rules" then
    local node = selected_node()
    local actions = {
      { "NEW...", 0.8, true, handle_new_menu },
      {
        "ADD BELOW",
        1.2,
        node ~= nil and node.kind == "rule" and not node.special,
        new_rule_below,
      },
      {
        "ADD INSIDE",
        1.25,
        node ~= nil and not node.special,
        new_rule_inside,
      },
      { "EDIT", 0.75, node ~= nil, edit_selected },
      { "REMOVE", 1.0, node ~= nil, delete_selected },
      { "UP", 0.55, node ~= nil, function() move_selected(-1) end },
      { "DOWN", 0.75, node ~= nil, function() move_selected(1) end },
      {
        "MOVE TO...",
        1.1,
        node ~= nil and node.kind == "rule" and not node.special,
        move_selected_to,
      },
    }
    local left = 16
    local right = math.max(left, gfx.w - 274)
    local gap = 6
    local available = math.max(0, right - left - gap * (#actions - 1))
    local total_weight = 0
    for _, action in ipairs(actions) do
      total_weight = total_weight + action[2]
    end
    local x = left
    for _, action in ipairs(actions) do
      local width = available * action[2] / total_weight
      if draw_button(
        action[1],
        x,
        y,
        width,
        52,
        action[3],
        left_pressed,
        3
      ) then
        action[4]()
      end
      x = x + width + gap
    end
  elseif mode == "modifiers" then
    local modifier = selected_modifier()
    if draw_button("NEW ORDER RULE", 16, y, 220, 52, true, left_pressed) then
      new_modifier()
    end
    if draw_button("EDIT", 246, y, 150, 52, modifier ~= nil, left_pressed) then
      edit_modifier()
    end
    if draw_button("REMOVE", 406, y, 170, 52, modifier ~= nil, left_pressed) then
      remove_modifier()
    end
    if draw_button("UP", 586, y, 120, 52, modifier ~= nil, left_pressed) then
      move_modifier(-1)
    end
    if draw_button("DOWN", 716, y, 140, 52, modifier ~= nil, left_pressed) then
      move_modifier(1)
    end
  elseif mode == "unknown" then
    local row = selected_project_row()
    if draw_button(
      "ADD NAME TO CHOSEN RULE",
      16,
      y,
      360,
      52,
      row ~= nil,
      left_pressed
    ) then
      append_unknown_to_selected_rule()
    end
    if draw_button(
      "CREATE NEW RULE",
      386,
      y,
      230,
      52,
      row ~= nil,
      left_pressed
    ) then
      create_rule_from_unknown()
    end
    local node = selected_node()
    local target = node and node.kind == "rule"
      and ("Chosen rule: " .. human_path(node))
      or "Choose a destination rule in RULES first"
    draw_text(fit_text(target, 390), 636, y + 14, COLORS.muted, 3)
  else
    if draw_button("REFRESH", 16, y, 150, 52, true, left_pressed) then
      refresh_project()
      set_status("Preview refreshed.", false)
    end
    if draw_button(
      "DETAILS",
      176,
      y,
      150,
      52,
      selected_project_row() ~= nil,
      left_pressed
    ) then
      show_preview_details()
    end
  end

  if draw_button("SAVE", gfx.w - 264, y, 124, 52, dirty, left_pressed) then
    save_config()
  end
  if draw_button("MORE", gfx.w - 130, y, 114, 52, true, left_pressed) then
    more_menu()
  end
end

local function draw_window(left_pressed, right_pressed)
  fill_rect(0, 0, gfx.w, gfx.h, COLORS.background)
  draw_text("TRACK ORGANIZER RULES", 16, 10, COLORS.text, 4)
  local subtitle = dirty
    and "Unsaved changes"
    or "The row order below is the track order used by Organizer"
  draw_text(
    subtitle,
    16,
    58,
    dirty and COLORS.yellow or COLORS.muted,
    3
  )

  draw_tab("RULES", "rules", 16, 92, 160, left_pressed)
  draw_tab("ORDERING", "modifiers", 186, 92, 210, left_pressed)
  draw_tab(
    "OTHER  (" .. tostring(#unknown_rows) .. ")",
    "unknown",
    406,
    92,
    200,
    left_pressed
  )
  draw_tab("PREVIEW", "preview", 616, 92, 180, left_pressed)
  local preset_label = active_preset
    and ("PRESET " .. tostring(active_preset.slot or "") .. ": " .. active_preset.name)
    or "PRESET: Legacy Track Order"
  if draw_button(
    preset_label,
    816,
    92,
    math.max(120, gfx.w - 832),
    60,
    true,
    left_pressed,
    3
  ) then
    choose_preset_menu()
  end

  local help
  if mode == "rules" then
    help = "Names in one rule form one sorting family. Final numbers are ordered naturally."
  elseif mode == "modifiers" then
    help = "Special cases such as Intro first, Main before Bass, and Outro last. Double-click to edit."
  elseif mode == "unknown" then
    help = "Tracks Organizer cannot recognize yet. Double-click one to create a rule."
  else
    help = "Exactly what Organizer will do. Yellow rows match more than one rule; double-click for details."
  end
  draw_text(help, 16, 164, COLORS.muted, 3)

  local table_top = 202
  local table_bottom = gfx.h - 136
  if mode == "rules" then
    draw_rules_table(table_top, table_bottom, left_pressed, right_pressed)
  elseif mode == "modifiers" then
    draw_modifiers_table(table_top, table_bottom, left_pressed)
  elseif mode == "unknown" then
    draw_project_table(unknown_rows, table_top, table_bottom, left_pressed, false)
  else
    draw_project_table(preview_rows, table_top, table_bottom, left_pressed, true)
  end

  local status_color = status_error and COLORS.red or COLORS.muted
  draw_text(fit_text(status_message, gfx.w - 34), 16, gfx.h - 118, status_color, 3)
  draw_footer(left_pressed)
end

local function initialize_window()
  gfx.init(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, 0)
  gfx.ext_retina = 1
  gfx.setfont(1, "Arial", 32)
  gfx.setfont(2, "Arial", 32)
  gfx.setfont(3, "Arial", 24)
  gfx.setfont(4, "Arial", 40)
end

local function refresh_if_project_changed()
  if not reaper.GetProjectStateChangeCount then
    return
  end
  local current = reaper.GetProjectStateChangeCount(0)
  if project_state_change_count ~= nil
    and current ~= project_state_change_count
  then
    refresh_project()
    set_status("The REAPER project changed. Track lists refreshed.", false)
  else
    project_state_change_count = current
  end
end

local function loop()
  if not running then
    return
  end
  local character = gfx.getchar()
  if character < 0 then
    if request_close() then
      return
    end
    initialize_window()
  end

  refresh_if_project_changed()

  local left = (gfx.mouse_cap % 2) == 1
  local right = (math.floor(gfx.mouse_cap / 2) % 2) == 1
  local left_pressed = left and not previous_left
  local right_pressed = right and not previous_right
  previous_left = left
  previous_right = right

  handle_wheel()
  draw_window(left_pressed, right_pressed)
  gfx.update()
  reaper.defer(loop)
end

initialize_window()
reaper.defer(loop)
