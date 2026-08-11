-- @noindex
-- Track Organizer shared configuration and classification engine.
-- This module has no dependency on REAPER and is used by both scripts.

local M = {}

M.VERSION = "1.3.1"

local DEFAULT_SETTINGS = {
  create_folders = true,
  move_existing_folders = false,
  existing_folders = "atomic",
  unknown_tracks = "folder",
  unknown_folder_name = "OTHER",
  subfolder_min_tracks = 3,
  numbered_family_min_tracks = 3,
  case_sensitive = false,
  preserve_relative_order = true,
  intro_first = true,
  outro_last = true,
  main_first = true,
  group_similar_names = true,
  natural_name_sort = true,
  dry_run = false,
  debug = false,
}

local SETTING_ORDER = {
  "create_folders",
  "move_existing_folders",
  "existing_folders",
  "unknown_tracks",
  "unknown_folder_name",
  "subfolder_min_tracks",
  "numbered_family_min_tracks",
  "case_sensitive",
  "preserve_relative_order",
  "intro_first",
  "outro_last",
  "main_first",
  "group_similar_names",
  "natural_name_sort",
  "dry_run",
  "debug",
}

local function trim(value)
  return (value or ""):match("^%s*(.-)%s*$")
end

local function copy_table(source)
  local target = {}
  for key, value in pairs(source or {}) do
    if type(value) == "table" then
      target[key] = copy_table(value)
    else
      target[key] = value
    end
  end
  return target
end

local function copy_array(source)
  local target = {}
  for index, value in ipairs(source or {}) do
    target[index] = value
  end
  return target
end

local function parse_boolean(value, default)
  if type(value) == "boolean" then
    return value
  end
  value = trim(value):lower()
  if value == "true" or value == "yes" or value == "1" or value == "on" then
    return true
  end
  if value == "false" or value == "no" or value == "0" or value == "off" then
    return false
  end
  return default
end

local function valid_boolean(value)
  value = trim(value):lower()
  return value == "true" or value == "yes" or value == "1" or value == "on"
    or value == "false" or value == "no" or value == "0" or value == "off"
end

local function split_list(value)
  local result = {}
  local current = {}
  local escaped = false

  for index = 1, #(value or "") do
    local character = value:sub(index, index)
    if escaped then
      current[#current + 1] = character
      escaped = false
    elseif character == "\\" then
      escaped = true
    elseif character == ";" then
      local item = trim(table.concat(current))
      if item ~= "" then
        result[#result + 1] = item
      end
      current = {}
    else
      current[#current + 1] = character
    end
  end

  if escaped then
    current[#current + 1] = "\\"
  end
  local item = trim(table.concat(current))
  if item ~= "" then
    result[#result + 1] = item
  end
  return result
end

local function join_list(values)
  local result = {}
  for _, value in ipairs(values or {}) do
    result[#result + 1] = tostring(value):gsub("\\", "\\\\"):gsub(";", "\\;")
  end
  return table.concat(result, "; ")
end

local function normalize_spaces(value)
  return trim((value or ""):gsub("%s+", " "))
end

function M.normalize(value, case_sensitive)
  value = tostring(value or "")
  value = value:gsub("(%l)(%u)", "%1 %2")
  if not case_sensitive then
    value = value:lower()
  end
  value = value:gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  value = value:gsub("[_%-%.%+/,\\%(%)]", " ")
  value = value:gsub("[^%w%s]", " ")
  return normalize_spaces(value)
end

local function words(value)
  local result = {}
  for word in (value or ""):gmatch("%S+") do
    result[#result + 1] = word
  end
  return result
end

function M.name_sort_info(value, case_sensitive)
  local normalized = M.normalize(value, case_sensitive)
  local tokens = words(normalized)
  local stem_tokens = copy_array(tokens)
  local trailing_number
  if #stem_tokens > 0 then
    local last_token = stem_tokens[#stem_tokens]
    local prefix, digits = last_token:match("^(.-)(%d+)$")
    if digits then
      trailing_number = tonumber(digits)
      if prefix == "" then
        stem_tokens[#stem_tokens] = nil
      else
        stem_tokens[#stem_tokens] = prefix
      end
    end
  end
  local word_set = {}
  for _, token in ipairs(tokens) do
    word_set[token] = true
  end
  return {
    original = tostring(value or ""),
    normalized = normalized,
    tokens = tokens,
    stem_tokens = stem_tokens,
    stem = table.concat(stem_tokens, " "),
    trailing_number = trailing_number,
    word_set = word_set,
  }
end

local function sequence_position(container, sequence)
  if #sequence == 0 or #sequence > #container then
    return nil
  end
  for start_index = 1, #container - #sequence + 1 do
    local matches = true
    for offset = 1, #sequence do
      if container[start_index + offset - 1] ~= sequence[offset] then
        matches = false
        break
      end
    end
    if matches then
      return start_index
    end
  end
  return nil
end


function M.sequence_position(container, sequence)
  return sequence_position(container, sequence)
end

function M.names_similar(first, second)
  first = type(first) == "table" and first or M.name_sort_info(first, false)
  second = type(second) == "table" and second or M.name_sort_info(second, false)
  local first_tokens = first.stem_tokens
  local second_tokens = second.stem_tokens
  if #first_tokens == 0 or #second_tokens == 0 then
    return first.normalized == second.normalized
  end
  if sequence_position(first_tokens, second_tokens)
    or sequence_position(second_tokens, first_tokens)
  then
    return true
  end
  -- A shared first word keeps sibling variants such as Kick In/Kick Out and
  -- Snare Top/Snare Bottom together without merging Lead Vocal/Synth Lead.
  return first_tokens[1] == second_tokens[1]
end

function M.compare_name_info(first, second)
  local count = math.max(#first.stem_tokens, #second.stem_tokens)
  for index = 1, count do
    local first_token = first.stem_tokens[index]
    local second_token = second.stem_tokens[index]
    if first_token == nil then
      return true
    elseif second_token == nil then
      return false
    elseif first_token ~= second_token then
      local first_number = tonumber(first_token)
      local second_number = tonumber(second_token)
      if first_number and second_number then
        return first_number < second_number
      end
      return first_token < second_token
    end
  end
  if first.trailing_number ~= second.trailing_number then
    if first.trailing_number == nil then
      return true
    elseif second.trailing_number == nil then
      return false
    end
    return first.trailing_number < second.trailing_number
  end
  return false
end

function M.name_boundary_rank(info, settings)
  if settings.outro_last and info.word_set.outro then
    return 2
  end
  if settings.intro_first and info.word_set.intro then
    return 0
  end
  return 1
end

function M.main_name_rank(info, settings)
  if settings.main_first and info.word_set.main then
    return 0
  end
  return 1
end

function M.is_folder_node(node)
  return node and (
    node.kind == "category"
    or (type(node.folder) == "string" and node.folder ~= "")
  )
end

local function wildcard_to_lua(value)
  local result = {}
  for index = 1, #value do
    local character = value:sub(index, index)
    if character == "*" then
      result[#result + 1] = ".*"
    elseif character == "?" then
      result[#result + 1] = "."
    elseif character:match("[%%%^%$%(%)%.%[%]%+%-]") then
      result[#result + 1] = "%" .. character
    else
      result[#result + 1] = character
    end
  end
  return "^" .. table.concat(result) .. "$"
end

local function pattern_kind(pattern)
  local kind, body = pattern:match("^(%a+)%s*:%s*(.*)$")
  if not kind then
    return "phrase", pattern
  end
  kind = kind:lower()
  if kind == "exact" or kind == "wildcard" or kind == "lua" or kind == "phrase" then
    return kind, body
  end
  return "phrase", pattern
end

local function match_one(track_name, normalized_name, pattern, case_sensitive)
  local kind, body = pattern_kind(pattern)
  if body == "" then
    return nil
  end

  if kind == "lua" then
    local subject = case_sensitive and track_name or track_name:lower()
    local expression = case_sensitive and body or body:lower()
    local ok, start_index, end_index = pcall(string.find, subject, expression)
    if ok and start_index then
      return {
        pattern = pattern,
        kind = kind,
        length = math.max(1, end_index - start_index + 1),
        words = 1,
      }
    end
    return nil
  end

  local normalized_body
  if kind == "wildcard" or body:find("*", 1, true)
    or body:find("?", 1, true)
  then
    normalized_body = case_sensitive and body or body:lower()
    normalized_body = normalized_body:gsub("[_%-%.%+/,\\%(%)]", " ")
    normalized_body = normalize_spaces(
      normalized_body:gsub("[^%w%s%*%?]", " ")
    )
  else
    normalized_body = M.normalize(body, case_sensitive)
  end

  if kind == "exact" then
    if normalized_name == normalized_body then
      return {
        pattern = pattern,
        kind = kind,
        length = #normalized_body,
        words = select(2, normalized_body:gsub("%S+", "")),
      }
    end
    return nil
  end

  if kind == "wildcard" or body:find("*", 1, true) or body:find("?", 1, true) then
    local expression = wildcard_to_lua(normalized_body)
    if normalized_name:match(expression) then
      return {
        pattern = pattern,
        kind = "wildcard",
        length = #normalized_body:gsub("[%*%?]", ""),
        words = select(2, normalized_body:gsub("%S+", "")),
      }
    end
    return nil
  end

  if (" " .. normalized_name .. " "):find(
    " " .. normalized_body .. " ",
    1,
    true
  ) then
    return {
      pattern = pattern,
      kind = kind,
      length = #normalized_body,
      words = select(2, normalized_body:gsub("%S+", "")),
    }
  end
  return nil
end

local function node_less(first, second)
  if first.order ~= second.order then
    return first.order < second.order
  end
  return first.id < second.id
end

local function rebuild(config)
  config.nodes_by_id = {}
  config.categories = config.categories or {}
  config.rules = config.rules or {}

  for _, category in ipairs(config.categories) do
    category.kind = "category"
    category.parent = nil
    category.children = {}
    config.nodes_by_id[category.id] = category
  end
  for _, rule in ipairs(config.rules) do
    rule.kind = "rule"
    rule.children = {}
    config.nodes_by_id[rule.id] = rule
  end
  for _, rule in ipairs(config.rules) do
    local parent = config.nodes_by_id[rule.parent]
    if parent then
      parent.children[#parent.children + 1] = rule
    end
  end
  table.sort(config.categories, node_less)
  for _, node in pairs(config.nodes_by_id) do
    table.sort(node.children, node_less)
  end

  local function visit(node, category, depth, order_path, path)
    node.category = category or node
    node.depth = depth
    node.order_path = copy_array(order_path)
    node.order_path[#node.order_path + 1] = node.order
    node.path = copy_array(path)
    node.path[#node.path + 1] = node
    for _, child in ipairs(node.children) do
      visit(child, node.category, depth + 1, node.order_path, node.path)
    end
  end

  for _, category in ipairs(config.categories) do
    visit(category, category, 1, {}, {})
  end
end

function M.rebuild(config)
  rebuild(config)
  return config
end

local function new_node(kind, id, values, line_number)
  local enabled = parse_boolean(values.enabled, true)
  local node = {
    kind = kind,
    id = id,
    name = trim(values.name) ~= "" and trim(values.name) or id,
    folder = trim(values.folder),
    parent = trim(values.parent),
    order = tonumber(values.order) or 1000,
    priority = tonumber(values.priority) or 0,
    enabled = enabled,
    special = parse_boolean(values.special, false),
    patterns = split_list(values.patterns),
    excludes = split_list(values.exclude or values.excludes),
    source_line = line_number,
  }
  return node
end

function M.load_config(path)
  local file, open_error = io.open(path, "r")
  if not file then
    return nil, { "Cannot open config: " .. tostring(open_error) }
  end

  local config = {
    path = path,
    settings = copy_table(DEFAULT_SETTINGS),
    categories = {},
    rules = {},
    parse_errors = {},
  }
  local section
  local section_line
  local values = {}
  local seen_sections = {}

  local function finish_section()
    if not section then
      return
    end
    if section == "settings" then
      for key, value in pairs(values) do
        if DEFAULT_SETTINGS[key] == nil then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": unknown setting " .. key
        else
          if type(DEFAULT_SETTINGS[key]) == "boolean" then
            if not valid_boolean(value) then
              config.parse_errors[#config.parse_errors + 1] =
                "Line " .. section_line .. ": invalid boolean for " .. key
            else
              config.settings[key] = parse_boolean(value, DEFAULT_SETTINGS[key])
            end
          elseif type(DEFAULT_SETTINGS[key]) == "number" then
            local number = tonumber(value)
            if not number then
              config.parse_errors[#config.parse_errors + 1] =
                "Line " .. section_line .. ": invalid number for " .. key
            else
              config.settings[key] = number
            end
          else
            config.settings[key] = trim(value)
          end
        end
      end
    else
      local kind, id = section:match("^(category):(.+)$")
      if not kind then
        kind, id = section:match("^(rule):(.+)$")
      end
      if not kind then
        config.parse_errors[#config.parse_errors + 1] =
          "Line " .. section_line .. ": unknown section [" .. section .. "]"
      elseif trim(id) == "" then
        config.parse_errors[#config.parse_errors + 1] =
          "Line " .. section_line .. ": section ID is empty"
      else
        id = trim(id)
        local allowed = kind == "category" and {
          name = true,
          folder = true,
          order = true,
          priority = true,
          enabled = true,
          special = true,
          patterns = true,
          exclude = true,
          excludes = true,
        } or {
          name = true,
          parent = true,
          folder = true,
          order = true,
          priority = true,
          enabled = true,
          patterns = true,
          exclude = true,
          excludes = true,
        }
        for key in pairs(values) do
          if not allowed[key] then
            config.parse_errors[#config.parse_errors + 1] =
              "Line " .. section_line .. ": unknown key " .. key
              .. " in [" .. section .. "]"
          end
        end
        if values.order and not tonumber(values.order) then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": order must be numeric"
        end
        if values.priority and not tonumber(values.priority) then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": priority must be numeric"
        end
        if values.enabled and not valid_boolean(values.enabled) then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": enabled must be boolean"
        end
        if values.special and not valid_boolean(values.special) then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": special must be boolean"
        end
        if values.exclude and values.excludes then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. section_line .. ": use exclude or excludes, not both"
        end
        local node = new_node(kind, id, values, section_line)
        if kind == "category" then
          config.categories[#config.categories + 1] = node
        else
          config.rules[#config.rules + 1] = node
        end
      end
    end
  end

  local line_number = 0
  for raw_line in file:lines() do
    line_number = line_number + 1
    local line = trim(raw_line)
    if line ~= "" and line:sub(1, 1) ~= ";" and line:sub(1, 1) ~= "#" then
      local new_section = line:match("^%[([^%]]+)%]$")
      if new_section then
        finish_section()
        section = trim(new_section):lower()
        section_line = line_number
        values = {}
        if seen_sections[section] then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. line_number .. ": duplicate section [" .. section .. "]"
        end
        seen_sections[section] = true
      else
        local key, value = raw_line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        if not section then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. line_number .. ": key outside a section"
        elseif not key then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. line_number .. ": expected key=value"
        elseif values[key:lower()] ~= nil then
          config.parse_errors[#config.parse_errors + 1] =
            "Line " .. line_number .. ": duplicate key " .. key
        else
          values[key:lower()] = value
        end
      end
    end
  end
  finish_section()
  file:close()

  rebuild(config)
  local validation = M.validate(config)
  for _, message in ipairs(config.parse_errors) do
    validation.errors[#validation.errors + 1] = message
  end
  validation.ok = #validation.errors == 0
  if not validation.ok then
    return nil, validation.errors, validation
  end
  return config, nil, validation
end

local function order_path_less(first, second)
  local count = math.max(#first, #second)
  for index = 1, count do
    local first_value = first[index] or -1
    local second_value = second[index] or -1
    if first_value ~= second_value then
      return first_value < second_value
    end
  end
  return false
end

function M.compare_nodes(first, second)
  return order_path_less(first.order_path, second.order_path)
end

local function is_enabled(node)
  for _, ancestor in ipairs(node.path or {}) do
    if not ancestor.enabled then
      return false
    end
  end
  return true
end

local function node_match(node, track_name, normalized_name, case_sensitive)
  if not is_enabled(node) or node.special or #node.patterns == 0 then
    return nil
  end
  for _, exclude in ipairs(node.excludes) do
    if match_one(track_name, normalized_name, exclude, case_sensitive) then
      return nil
    end
  end

  local best
  for _, pattern in ipairs(node.patterns) do
    local matched = match_one(
      track_name,
      normalized_name,
      pattern,
      case_sensitive
    )
    if matched and (not best or matched.length > best.length) then
      best = matched
    end
  end
  return best
end

local function candidate_better(first, second)
  if first.priority ~= second.priority then
    return first.priority > second.priority
  end
  if first.specificity ~= second.specificity then
    return first.specificity > second.specificity
  end
  if M.compare_nodes(first.node, second.node) then
    return true
  end
  if M.compare_nodes(second.node, first.node) then
    return false
  end
  return first.node.id < second.node.id
end

function M.classify(config, track_name)
  local case_sensitive = config.settings.case_sensitive
  local normalized_name = M.normalize(track_name, case_sensitive)
  local matches = {}

  for _, node in pairs(config.nodes_by_id) do
    local matched = node_match(
      node,
      tostring(track_name or ""),
      normalized_name,
      case_sensitive
    )
    if matched then
      local specificity = matched.length
        + matched.words * 12
        + node.depth * 30
        + (matched.kind == "exact" and 40 or 0)
      matches[#matches + 1] = {
        node = node,
        category = node.category,
        pattern = matched.pattern,
        kind = matched.kind,
        priority = node.priority,
        specificity = specificity,
      }
    end
  end

  table.sort(matches, candidate_better)
  return {
    track_name = track_name,
    normalized_name = normalized_name,
    winner = matches[1],
    matches = matches,
    conflict = #matches > 1,
  }
end

function M.path_names(node, separator)
  local names = {}
  for _, item in ipairs(node and node.path or {}) do
    names[#names + 1] = item.name
  end
  return table.concat(names, separator or " > ")
end

function M.order_string(node)
  local values = {}
  for _, value in ipairs(node and node.order_path or {}) do
    values[#values + 1] = tostring(value)
  end
  return table.concat(values, ".")
end

function M.validation_summary(validation)
  local lines = {}
  if #validation.errors > 0 then
    lines[#lines + 1] = "Errors:"
    for _, message in ipairs(validation.errors) do
      lines[#lines + 1] = "- " .. message
    end
  end
  if #validation.warnings > 0 then
    lines[#lines + 1] = "Warnings:"
    for _, message in ipairs(validation.warnings) do
      lines[#lines + 1] = "- " .. message
    end
  end
  if #lines == 0 then
    return "Configuration is valid."
  end
  return table.concat(lines, "\n")
end

function M.validate(config)
  rebuild(config)
  local result = { ok = true, errors = {}, warnings = {} }
  local seen = {}
  local other_count = 0

  if config.settings.unknown_tracks ~= "folder" then
    result.errors[#result.errors + 1] =
      "unknown_tracks must be folder in this version."
  end
  if config.settings.existing_folders ~= "atomic" then
    result.errors[#result.errors + 1] =
      "existing_folders must be atomic in this version."
  end
  if (tonumber(config.settings.subfolder_min_tracks) or 0) < 1 then
    result.errors[#result.errors + 1] =
      "subfolder_min_tracks must be at least 1."
  end
  if (tonumber(config.settings.numbered_family_min_tracks) or 0) < 3 then
    result.errors[#result.errors + 1] =
      "numbered_family_min_tracks must be at least 3."
  end

  for _, node in ipairs(config.categories) do
    if node.id == "" then
      result.errors[#result.errors + 1] = "A category has an empty ID."
    elseif not node.id:match("^[%l%d][%l%d%._%-]*$") then
      result.errors[#result.errors + 1] = "Invalid category ID: " .. node.id
    elseif seen[node.id] then
      result.errors[#result.errors + 1] = "Duplicate ID: " .. node.id
    end
    seen[node.id] = true
    if node.id == "other" and node.special then
      other_count = other_count + 1
    elseif node.id == "other" or node.special then
      result.errors[#result.errors + 1] =
        "Only [category:other] may use special=true."
    end
  end

  for _, node in ipairs(config.rules) do
    if node.id == "" then
      result.errors[#result.errors + 1] = "A rule has an empty ID."
    elseif not node.id:match("^[%l%d][%l%d%._%-]*$") then
      result.errors[#result.errors + 1] = "Invalid rule ID: " .. node.id
    elseif seen[node.id] then
      result.errors[#result.errors + 1] = "Duplicate ID: " .. node.id
    end
    seen[node.id] = true
    if node.parent == "" or not config.nodes_by_id[node.parent] then
      result.errors[#result.errors + 1] =
        "Rule " .. node.id .. " has missing parent " .. tostring(node.parent)
    end
  end

  for _, node in ipairs(config.rules) do
    local visited = {}
    local current = node
    while current and current.parent do
      if visited[current.id] then
        result.errors[#result.errors + 1] =
          "Parent cycle involving " .. current.id
        break
      end
      visited[current.id] = true
      current = config.nodes_by_id[current.parent]
    end
  end

  if other_count == 0 then
    result.errors[#result.errors + 1] =
      "A special [category:other] category is required."
  elseif other_count > 1 then
    result.errors[#result.errors + 1] =
      "Only one OTHER/special category is allowed."
  end

  local pattern_owners = {}
  for _, node in pairs(config.nodes_by_id) do
    if node.enabled then
      for _, pattern in ipairs(node.patterns) do
        local key = pattern:lower()
        if pattern_owners[key] and pattern_owners[key] ~= node.id then
          result.warnings[#result.warnings + 1] =
            "Pattern '" .. pattern .. "' is shared by "
            .. pattern_owners[key] .. " and " .. node.id
        else
          pattern_owners[key] = node.id
        end
      end
    end
  end

  local function check_sibling_orders(parent_name, children)
    local orders = {}
    for _, child in ipairs(children) do
      if orders[child.order] then
        result.warnings[#result.warnings + 1] =
          "Duplicate order " .. child.order .. " under " .. parent_name
      end
      orders[child.order] = true
    end
  end
  check_sibling_orders("root", config.categories)
  for _, node in pairs(config.nodes_by_id) do
    check_sibling_orders(node.id, node.children)
  end

  result.ok = #result.errors == 0
  return result
end

local function serialize_node(lines, node)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "[" .. node.kind .. ":" .. node.id .. "]"
  lines[#lines + 1] = "name=" .. node.name
  if node.kind == "category" then
    lines[#lines + 1] = "folder=" .. (node.folder ~= "" and node.folder or node.name)
  else
    lines[#lines + 1] = "parent=" .. node.parent
    if node.folder and node.folder ~= "" then
      lines[#lines + 1] = "folder=" .. node.folder
    end
  end
  lines[#lines + 1] = "order=" .. tostring(node.order)
  lines[#lines + 1] = "priority=" .. tostring(node.priority)
  lines[#lines + 1] = "enabled=" .. tostring(node.enabled)
  if node.special then
    lines[#lines + 1] = "special=true"
  end
  if #node.patterns > 0 then
    lines[#lines + 1] = "patterns=" .. join_list(node.patterns)
  end
  if #node.excludes > 0 then
    lines[#lines + 1] = "exclude=" .. join_list(node.excludes)
  end
end

function M.serialize(config)
  rebuild(config)
  local lines = {
    "; Track Organizer configuration",
    "; Plain entries match normalized whole words/phrases.",
    "; Optional prefixes: exact:, wildcard:, lua:.",
    "; Semicolon separates patterns; escape a literal semicolon as \\;.",
    "",
    "[settings]",
  }
  for _, key in ipairs(SETTING_ORDER) do
    lines[#lines + 1] = key .. "=" .. tostring(config.settings[key])
  end

  local function write_tree(node)
    serialize_node(lines, node)
    for _, child in ipairs(node.children) do
      write_tree(child)
    end
  end
  for _, category in ipairs(config.categories) do
    write_tree(category)
  end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_file(path, contents)
  local file, open_error = io.open(path, "wb")
  if not file then
    return false, open_error
  end
  local ok, write_error = file:write(contents)
  file:close()
  if not ok then
    return false, write_error
  end
  return true
end

function M.save_config(config, path)
  local validation = M.validate(config)
  if not validation.ok then
    return false, M.validation_summary(validation), validation
  end

  path = path or config.path
  local serialized = M.serialize(config)
  local temporary_path = path .. ".tmp"
  local backup_path = path .. ".bak"
  local ok, error_message = write_file(temporary_path, serialized)
  if not ok then
    return false, "Cannot write temporary config: " .. tostring(error_message)
  end

  local old_file = io.open(path, "rb")
  local old_contents
  if old_file then
    old_contents = old_file:read("*a")
    old_file:close()
    local backup_ok, backup_error = write_file(backup_path, old_contents)
    if not backup_ok then
      os.remove(temporary_path)
      return false, "Cannot create backup: " .. tostring(backup_error)
    end
  end

  os.remove(path)
  local renamed, rename_error = os.rename(temporary_path, path)
  if not renamed then
    if old_contents then
      write_file(path, old_contents)
    end
    os.remove(temporary_path)
    return false, "Cannot replace config: " .. tostring(rename_error)
  end

  config.path = path
  return true, M.validation_summary(validation), validation
end

function M.restore_backup(path)
  local backup_path = path .. ".bak"
  local file, open_error = io.open(backup_path, "rb")
  if not file then
    return false, "Cannot open backup: " .. tostring(open_error)
  end
  local contents = file:read("*a")
  file:close()

  local temporary_path = path .. ".restore.tmp"
  local ok, write_error = write_file(temporary_path, contents)
  if not ok then
    return false, "Cannot prepare restore: " .. tostring(write_error)
  end
  os.remove(path)
  local renamed, rename_error = os.rename(temporary_path, path)
  if not renamed then
    os.remove(temporary_path)
    return false, "Cannot restore backup: " .. tostring(rename_error)
  end
  return true, "Backup restored."
end

function M.new_category(config, id, name)
  local category = {
    kind = "category",
    id = id,
    name = name or id,
    folder = name or id,
    order = (#config.categories + 1) * 10,
    priority = 0,
    enabled = true,
    special = false,
    patterns = {},
    excludes = {},
  }
  config.categories[#config.categories + 1] = category
  rebuild(config)
  return category
end

function M.new_rule(config, id, parent, name)
  local parent_node = config.nodes_by_id[parent]
  local rule = {
    kind = "rule",
    id = id,
    parent = parent,
    name = name or id,
    folder = "",
    order = parent_node and (#parent_node.children + 1) * 10 or 10,
    priority = 100,
    enabled = true,
    special = false,
    patterns = {},
    excludes = {},
  }
  config.rules[#config.rules + 1] = rule
  rebuild(config)
  return rule
end

function M.delete_node(config, id)
  local remove = { [id] = true }
  local changed = true
  while changed do
    changed = false
    for _, rule in ipairs(config.rules) do
      if remove[rule.parent] and not remove[rule.id] then
        remove[rule.id] = true
        changed = true
      end
    end
  end

  local categories = {}
  for _, category in ipairs(config.categories) do
    if not remove[category.id] then
      categories[#categories + 1] = category
    end
  end
  local rules = {}
  for _, rule in ipairs(config.rules) do
    if not remove[rule.id] then
      rules[#rules + 1] = rule
    end
  end
  config.categories = categories
  config.rules = rules
  rebuild(config)
end

function M.slug(value)
  local slug = M.normalize(value, false):gsub("%s+", ".")
  slug = slug:gsub("[^%w%.]", ""):gsub("%.+", ".")
  slug = slug:gsub("^%.*", ""):gsub("%.*$", "")
  return slug ~= "" and slug or "rule"
end

function M.unique_id(config, base)
  local id = base
  local suffix = 2
  while config.nodes_by_id[id] do
    id = base .. "." .. suffix
    suffix = suffix + 1
  end
  return id
end

function M.renumber_siblings(config, parent_id)
  local siblings = parent_id
    and config.nodes_by_id[parent_id].children
    or config.categories
  for index, node in ipairs(siblings) do
    node.order = index * 10
  end
  rebuild(config)
end

function M.move_before(config, source_id, target_id)
  local source = config.nodes_by_id[source_id]
  local target = config.nodes_by_id[target_id]
  if not source or not target or source.parent ~= target.parent
    or source.kind ~= target.kind
  then
    return false, "Drag-and-drop reordering is limited to siblings."
  end
  local siblings = source.parent
    and config.nodes_by_id[source.parent].children
    or config.categories
  local reordered = {}
  for _, node in ipairs(siblings) do
    if node ~= source then
      if node == target then
        reordered[#reordered + 1] = source
      end
      reordered[#reordered + 1] = node
    end
  end
  for index, node in ipairs(reordered) do
    node.order = index * 10
  end
  rebuild(config)
  return true
end

M.DEFAULT_SETTINGS = DEFAULT_SETTINGS
M.split_list = split_list
M.join_list = join_list
M.copy_table = copy_table

return M
