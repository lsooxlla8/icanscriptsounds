-- @description icss_Track Organizer Rule Manager
-- @noindex
-- @author icanseesounds
-- @version 2.2.1
-- @changelog
--   Prevent header overlap and reduce the default window size
-- @about
--   Human-friendly editor for Track Organizer's track-order.ini.
--   Uses REAPER's built-in gfx window and requires no ReaImGui installation.

local function script_directory()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*[\\/])") or ""
end

local DIRECTORY = script_directory()
local CORE_PATH = DIRECTORY .. "TrackOrganizer_Core.lua"
local CONFIG_PATH = DIRECTORY .. "track-order.ini"
local FOLDER_TAG = "P_EXT:ICSS_TRACK_ORGANIZER_FOLDER"
local WINDOW_TITLE = "Track Organizer Rules"
local WINDOW_WIDTH = 1320
local WINDOW_HEIGHT = 860

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
local selected_project_index
local dirty = false
local status_message = ""
local status_error = false
local mode = "rules"
local rule_rows = {}
local project_rows = {}
local unknown_rows = {}
local preview_rows = {}
local scroll = { rules = 0, unknown = 0, preview = 0 }
local collapsed = {}
local collapse_initialized = false
local previous_left = false
local previous_right = false
local last_clicked_id
local last_click_time = 0
local running = true

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
  reaper.SetOnlyTrackSelected(track)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local function set_status(message, is_error)
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

local function refresh_project()
  project_rows = {}
  unknown_rows = {}
  preview_rows = {}
  for index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, index)
    if not is_managed_folder(track) then
      local name = track_name(track)
      local result = Core.classify(config, name)
      local row = {
        track = track,
        index = index + 1,
        name = name,
        result = result,
        key = tostring(track),
      }
      project_rows[#project_rows + 1] = row
      preview_rows[#preview_rows + 1] = row
      if not result.winner then
        unknown_rows[#unknown_rows + 1] = row
      end
    end
  end
end

local function load_config()
  local loaded, errors = Core.load_config(CONFIG_PATH)
  if not loaded then
    show_message(
      "The rules file could not be loaded:\n\n"
      .. table.concat(errors or { "Unknown error." }, "\n")
    )
    return false
  end
  config = loaded
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
    if row.index == selected_project_index then
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
  local ok, returned = reaper.GetUserInputs(
    title,
    #values,
    table.concat(captions, ",") .. ",separator=|,extrawidth=360",
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

local function new_main_group()
  local fields = ask_fields(
    "New main group",
    { "Group name", "Folder track name" },
    { "NEW GROUP", "NEW GROUP" }
  )
  if not fields then
    return
  end
  local name = fields[1]:match("^%s*(.-)%s*$")
  local folder = fields[2]:match("^%s*(.-)%s*$")
  if name == "" then
    show_message("Enter a group name.")
    return
  end
  local id = Core.unique_id(config, Core.slug(name))
  local node = Core.new_category(config, id, name)
  node.folder = folder ~= "" and folder or name
  local other = config.nodes_by_id.other
  if other then
    node.order = other.order - 1
  end
  selected_id = node.id
  Core.rebuild(config)
  Core.renumber_siblings(config, nil)
  mark_dirty("Main group created. Click Save when finished.")
end

local function new_rule(parent, proposed_name, proposed_pattern)
  parent = parent or usable_parent()
  if not parent or parent.special then
    return
  end
  local fields = ask_fields(
    "New rule under " .. parent.name,
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
  collapsed[parent.id] = false
  selected_id = node.id
  mark_dirty("Rule created. Click Save when finished.")
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
  node.priority = 0
  collapsed[parent.id] = false
  collapsed[node.id] = false
  selected_id = node.id
  mark_dirty("Subfolder created. Click Save when finished.")
end

local function add_selected_track_as_rule()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    show_message(
      "Select a track in REAPER first.\n\n"
      .. "Then select the destination group in this window and try again."
    )
    return
  end
  local parent = usable_parent()
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
      { "Group name", "Folder track name" },
      { node.name, node.folder ~= "" and node.folder or node.name }
    )
    if not fields then
      return
    end
    local name = fields[1]:match("^%s*(.-)%s*$")
    if name == "" then
      show_message("Enter a group name.")
      return
    end
    node.name = name
    node.folder = fields[2]:match("^%s*(.-)%s*$")
    if node.folder == "" then
      node.folder = name
    end
  elseif Core.is_folder_node(node) then
    local fields = ask_fields(
      "Edit subfolder",
      {
        "Rule group name",
        "Folder track name",
        "Names or words (optional; separate with ;)",
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
  else
    local fields = ask_fields(
      "Edit rule",
      { "Rule name", "Names or words (separate with ;)", "Do not match (optional)" },
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
  local detail = node.kind == "category"
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

local function save_config()
  local ok, message = Core.save_config(config, CONFIG_PATH)
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
  local ok, message = Core.restore_backup(CONFIG_PATH)
  if not ok then
    show_message(message)
    return
  end
  load_config()
  set_status("Previous saved version restored.", false)
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
    lines[#lines + 1] =
      "The first rule wins because it is the more specific rule."
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

local function handle_add_menu()
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local choice = gfx.showmenu(
    "New main group"
    .. "|New rule under selected row"
    .. "|New subfolder under selected row"
    .. "|Rule from selected REAPER track"
  )
  if choice == 1 then
    new_main_group()
  elseif choice == 2 then
    new_rule()
  elseif choice == 3 then
    new_subfolder()
  elseif choice == 4 then
    add_selected_track_as_rule()
  end
end

local function handle_row_menu(row)
  selected_id = row.node.id
  gfx.x = gfx.mouse_x
  gfx.y = gfx.mouse_y
  local toggle_label = row.node.enabled and "Turn off" or "Turn on"
  local choice = gfx.showmenu(
    "Edit"
    .. "|New rule under this row"
    .. "|New subfolder under this row"
    .. "|Rule from selected REAPER track"
    .. "|" .. toggle_label
    .. "|Remove"
    .. "|Move up"
    .. "|Move down"
  )
  if choice == 1 then
    edit_selected()
  elseif choice == 2 then
    new_rule(row.node)
  elseif choice == 3 then
    new_subfolder(row.node)
  elseif choice == 4 then
    add_selected_track_as_rule()
  elseif choice == 5 then
    toggle_selected()
  elseif choice == 6 then
    delete_selected()
  elseif choice == 7 then
    move_selected(-1)
  elseif choice == 8 then
    move_selected(1)
  end
end

local function draw_button(label, x, y, width, height, enabled, left_pressed)
  local hovered = inside(x, y, width, height)
  local color = not enabled and COLORS.button_disabled
    or (hovered and COLORS.button_hover or COLORS.button)
  fill_rect(x, y, width, height, color)
  stroke_rect(x, y, width, height, COLORS.line)
  gfx.setfont(2)
  local text_width, text_height = gfx.measurestr(label)
  draw_text(
    label,
    x + math.max(8, (width - text_width) / 2),
    y + (height - text_height) / 2,
    enabled and COLORS.text or COLORS.muted,
    2
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
  local text_width, text_height = gfx.measurestr(label)
  draw_text(
    label,
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
    selected_project_index = nil
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
  local visible = math.max(1, math.floor((table_height - header_height) / row_height))
  local maximum = math.max(0, #rule_rows - visible)
  scroll.rules = math.max(0, math.min(scroll.rules, maximum))

  fill_rect(x, top, width, header_height, COLORS.header)
  draw_text("ON", x + 14, top + 12, COLORS.muted, 3)
  draw_text("GROUP / RULE", x + 88, top + 12, COLORS.muted, 3)
  draw_text("MATCH THESE NAMES OR WORDS", x + 520, top + 12, COLORS.muted, 3)
  draw_text("DO NOT MATCH", x + width - 360, top + 12, COLORS.muted, 3)

  for visible_index = 1, visible do
    local row_index = scroll.rules + visible_index
    local row = rule_rows[row_index]
    if not row then
      break
    end
    local node = row.node
    local is_folder_rule = node.kind == "rule" and Core.is_folder_node(node)
    local y = body_top + (visible_index - 1) * row_height
    local selected = node.id == selected_id
    local color
    if selected then
      color = node.kind == "category" and COLORS.selected or COLORS.selected_soft
    elseif node.special then
      color = COLORS.other
    elseif node.kind == "category" or is_folder_rule then
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
    local prefix = node.kind == "category" and ""
      or (is_folder_rule and "FOLDER  " or "- ")
    local name = prefix .. node.name
    local name_color = node.enabled and COLORS.text or COLORS.muted
    draw_text(
      fit_text(name, 390 - indent),
      x + 122 + indent,
      y + 14,
      name_color,
      (node.kind == "category" or is_folder_rule) and 2 or 1
    )
    if node.kind == "category" or is_folder_rule then
      local folder = node.special
        and (config.settings.unknown_folder_name or "OTHER")
        or (node.folder ~= "" and node.folder or node.name)
      draw_text(
        fit_text("Folder: " .. folder, 410),
        x + 520,
        y + 14,
        COLORS.muted,
        1
      )
    else
      draw_text(
        fit_text(Core.join_list(node.patterns), width - 520 - 390),
        x + 520,
        y + 14,
        name_color,
        1
      )
      draw_text(
        fit_text(Core.join_list(node.excludes), 330),
        x + width - 360,
        y + 14,
        COLORS.muted,
        1
      )
    end

    if inside(x, y, width, row_height) then
      set_status(
        node.kind == "category"
          and "Main folder: " .. (node.folder ~= "" and node.folder or node.name)
          or human_path(node),
        false
      )
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
    local selected = row.index == selected_project_index
    local color = selected and COLORS.selected_soft
      or (row_index % 2 == 0 and COLORS.row_alt or COLORS.row)
    fill_rect(x, y, width, row_height - 1, color)
    draw_text(
      fit_text(row.name, width * 0.45),
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
      selected_project_index = row.index
      select_reaper_track(row.track)
      handle_double_click(
        "track:" .. row.index,
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
    .. "|Close"
  )
  if choice == 1 then
    test_track_name()
  elseif choice == 2 then
    reload_config()
  elseif choice == 3 then
    restore_backup()
  elseif choice == 4 then
    request_close()
  end
end

local function draw_footer(left_pressed)
  local y = gfx.h - 72
  fill_rect(0, y - 10, gfx.w, 82, COLORS.panel)
  fill_rect(0, y - 10, gfx.w, 1, COLORS.line)

  if mode == "rules" then
    if draw_button("ADD", 16, y, 118, 52, true, left_pressed) then
      handle_add_menu()
    end
    if draw_button("EDIT", 144, y, 118, 52, selected_node() ~= nil, left_pressed) then
      edit_selected()
    end
    if draw_button("REMOVE", 272, y, 150, 52, selected_node() ~= nil, left_pressed) then
      delete_selected()
    end
    if draw_button("UP", 432, y, 82, 52, selected_node() ~= nil, left_pressed) then
      move_selected(-1)
    end
    if draw_button("DOWN", 524, y, 110, 52, selected_node() ~= nil, left_pressed) then
      move_selected(1)
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

  draw_tab("RULES", "rules", 16, 92, 190, left_pressed)
  draw_tab(
    "OTHER  (" .. tostring(#unknown_rows) .. ")",
    "unknown",
    216,
    92,
    240,
    left_pressed
  )
  draw_tab("PREVIEW", "preview", 466, 92, 200, left_pressed)

  local help
  if mode == "rules" then
    help = "Click + to open a group. Double-click a row to edit. UP / DOWN changes its order."
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
