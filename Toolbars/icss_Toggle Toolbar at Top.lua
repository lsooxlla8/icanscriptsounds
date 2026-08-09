-- @description Toggle Toolbar at Top
-- @author icanseesounds
-- @version 1.2.1
-- @changelog
--   Always switch the toolbar at the top instead of the last focused toolbar
-- @about
--   Switches any toolbar positioned at the top of the main window to the
--   configured target toolbar, then back to the previous toolbar.
--   Restores the window focus that was active before the script ran.
--
--   Requires js_ReaScriptAPI.

-- Set this to the toolbar number you want to toggle to (1-32).
local TARGET_TOOLBAR = 3

local TOOLBAR_COUNT = 32
local EXT_SECTION = "ICSS_ToggleToolbarAtTop"
local EXT_KEY = "PreviousToolbar"

local function show_error(message)
  reaper.ShowMessageBox(message, "Toggle Toolbar at Top", 0)
end

local function get_toolbar_titles()
  local titles = {}
  for toolbar_number = 1, TOOLBAR_COUNT do
    titles[toolbar_number] = "Toolbar " .. toolbar_number
  end

  local separator = package.config:sub(1, 1)
  local menu_file = io.open(
    reaper.GetResourcePath() .. separator .. "reaper-menu.ini",
    "r"
  )

  if not menu_file then
    return titles
  end

  local toolbar_number
  for line in menu_file:lines() do
    local section_number = line:match("^%[Floating toolbar (%d+)%]$")
    if section_number then
      toolbar_number = tonumber(section_number)
    elseif line:sub(1, 1) == "[" then
      toolbar_number = nil
    elseif toolbar_number and toolbar_number <= TOOLBAR_COUNT then
      local title = line:match("^title=(.*)$")
      if title and title ~= "" then
        titles[toolbar_number] = title
      end
    end
  end

  menu_file:close()
  return titles
end

local function get_window_rect(hwnd)
  local ok, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
  if not ok then
    return nil
  end

  return {
    left = math.min(left, right),
    right = math.max(left, right),
    bottom = math.min(top, bottom),
    top = math.max(top, bottom),
  }
end

local function horizontal_overlap(first, second)
  return math.max(
    0,
    math.min(first.right, second.right) - math.max(first.left, second.left)
  )
end

local function get_top_toolbar()
  local main_window = reaper.GetMainHwnd()
  local main_rect = get_window_rect(main_window)
  if not main_rect then
    return nil, nil, main_window
  end

  local titles = get_toolbar_titles()
  local best_toolbar
  local best_window
  local best_score

  for toolbar_number = 1, TOOLBAR_COUNT do
    local toolbar_window = reaper.JS_Window_Find(titles[toolbar_number], true)
    if toolbar_window and reaper.JS_Window_IsVisible(toolbar_window) then
      local toolbar_rect = get_window_rect(toolbar_window)
      if toolbar_rect then
        local toolbar_width = toolbar_rect.right - toolbar_rect.left
        local main_width = main_rect.right - main_rect.left
        local overlap = horizontal_overlap(toolbar_rect, main_rect)

        -- A toolbar in this position spans a substantial part of the main
        -- window and sits closest to its top edge.
        if toolbar_width > 0
          and toolbar_width >= main_width * 0.25
          and overlap >= toolbar_width * 0.75
        then
          local edge_distance = math.abs(main_rect.top - toolbar_rect.top)
          local center_distance = math.abs(
            (main_rect.left + main_rect.right)
              - (toolbar_rect.left + toolbar_rect.right)
          ) / 2
          local score = edge_distance + center_distance * 0.1

          if not best_score or score < best_score then
            best_toolbar = toolbar_number
            best_window = toolbar_window
            best_score = score
          end
        end
      end
    end
  end

  return best_toolbar, best_window, main_window
end

local function get_switch_actions()
  local actions = {}
  local main_section = reaper.SectionFromUniqueID(0)
  local index = 0

  while true do
    local command_id, action_name = reaper.kbd_enumerateActions(
      main_section,
      index
    )
    if command_id == 0 then
      break
    end

    local toolbar_number = action_name:match("Switch to toolbar (%d+)$")
    toolbar_number = tonumber(toolbar_number)
    if toolbar_number
      and toolbar_number >= 1
      and toolbar_number <= TOOLBAR_COUNT
    then
      actions[toolbar_number] = command_id
    end

    index = index + 1
  end

  return actions
end

local function switch_focused_toolbar(
  toolbar_window,
  main_window,
  command_id,
  previous_foreground,
  previous_focus
)
  reaper.JS_Window_SetForeground(main_window)

  reaper.defer(function()
    reaper.JS_Window_SetFocus(toolbar_window)

    -- REAPER chooses which toolbar to switch from its last mouse context, not
    -- only from keyboard focus. A synthetic click on the window border makes
    -- this toolbar the target without moving the pointer or pressing a button.
    reaper.JS_WindowMessage_Send(
      toolbar_window,
      "WM_LBUTTONDOWN",
      1,
      0,
      0,
      0
    )
    reaper.JS_WindowMessage_Send(
      toolbar_window,
      "WM_LBUTTONUP",
      0,
      0,
      0,
      0
    )

    reaper.defer(function()
      reaper.Main_OnCommand(command_id, 0)

      -- Restore the previous top-level window first, then its focused child
      -- after REAPER has completed the toolbar switch.
      reaper.defer(function()
        if previous_foreground
          and reaper.JS_Window_IsWindow(previous_foreground)
        then
          reaper.JS_Window_SetForeground(previous_foreground)
        end

        reaper.defer(function()
          if previous_focus and reaper.JS_Window_IsWindow(previous_focus) then
            reaper.JS_Window_SetFocus(previous_focus)
          end
        end)
      end)
    end)
  end)
end

local function main()
  if TARGET_TOOLBAR < 1
    or TARGET_TOOLBAR > TOOLBAR_COUNT
    or TARGET_TOOLBAR % 1 ~= 0
  then
    show_error("TARGET_TOOLBAR must be an integer from 1 to 32.")
    return
  end

  if not reaper.JS_Window_Find
    or not reaper.JS_Window_GetRect
    or not reaper.JS_Window_IsVisible
    or not reaper.JS_Window_IsWindow
    or not reaper.JS_Window_GetFocus
    or not reaper.JS_Window_GetForeground
    or not reaper.JS_Window_SetFocus
    or not reaper.JS_Window_SetForeground
    or not reaper.JS_WindowMessage_Send
  then
    show_error("This script requires js_ReaScriptAPI.")
    return
  end

  if not reaper.SectionFromUniqueID or not reaper.kbd_enumerateActions then
    show_error("This script requires REAPER 6.71 or newer.")
    return
  end

  local active_toolbar, toolbar_window, main_window = get_top_toolbar()
  if not active_toolbar or not toolbar_window then
    show_error(
      "Could not find a toolbar at the top of the main window."
    )
    return
  end

  local target_toolbar
  if active_toolbar == TARGET_TOOLBAR then
    target_toolbar = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY))
    if not target_toolbar
      or target_toolbar < 1
      or target_toolbar > TOOLBAR_COUNT
      or target_toolbar == TARGET_TOOLBAR
    then
      show_error(
        "No previous toolbar is remembered yet. Switch to another toolbar "
          .. "and run the script once."
      )
      return
    end
  else
    target_toolbar = TARGET_TOOLBAR
    reaper.SetExtState(
      EXT_SECTION,
      EXT_KEY,
      tostring(active_toolbar),
      false
    )
  end

  local switch_actions = get_switch_actions()
  local command_id = switch_actions[target_toolbar]
  if not command_id then
    show_error(
      "Could not find REAPER's switch action for toolbar "
        .. target_toolbar
        .. "."
    )
    return
  end

  local previous_foreground = reaper.JS_Window_GetForeground()
  local previous_focus = reaper.JS_Window_GetFocus()

  switch_focused_toolbar(
    toolbar_window,
    main_window,
    command_id,
    previous_foreground,
    previous_focus
  )
end

main()
